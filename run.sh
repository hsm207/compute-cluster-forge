#!/bin/bash

# Default values
CLOUD="gcp"
TYPE="spike"
ACTION="plan"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cloud) CLOUD="$2"; shift ;;
        --type) TYPE="$2"; shift ;;
        --action) ACTION="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Map cloud to module directory
case $CLOUD in
    gcp) MODULE_DIR="modules/gcp" ;;
    aws) echo "AWS expansion coming soon! 🚀"; exit 1 ;;
    azure) echo "Azure expansion coming soon! 🚀"; exit 1 ;;
    *) echo "Invalid cloud: $CLOUD"; exit 1 ;;
esac

# Verify template exists
VAR_FILE="templates/${TYPE}.tfvars"
if [[ ! -f "$VAR_FILE" ]]; then
    echo "Error: Template file $VAR_FILE not found."
    exit 1
fi

# Navigate to the cloud module
VAR_FILE_ABS=$(readlink -f "$VAR_FILE")
cd "$MODULE_DIR" || exit

# Initialize terraform if needed
if [[ ! -d ".terraform" ]]; then
    terraform init
fi

# Manage workspaces (isolated state per template type)
terraform workspace select "$TYPE" 2>/dev/null || terraform workspace new "$TYPE"

# Execute action
echo "--------------------------------------------------------------------------------"
echo "🛠️  Compute Cluster Forge: Executing $ACTION for $CLOUD ($TYPE)"
echo "--------------------------------------------------------------------------------"

# Only pass -var-file for actions that support it
if [[ "$ACTION" == "plan" || "$ACTION" == "apply" || "$ACTION" == "destroy" || "$ACTION" == "import" || "$ACTION" == "refresh" ]]; then
    EXTRA_ARGS=""
    if [[ "$ACTION" == "apply" || "$ACTION" == "destroy" ]]; then
        EXTRA_ARGS="-auto-approve"
    fi
    terraform "$ACTION" -var-file="$VAR_FILE_ABS" $EXTRA_ARGS
else
    terraform "$ACTION"
fi

# Post-Execution Summary (Only for success on Apply/Refresh/Plan)
if [[ "$?" -eq 0 && ("$ACTION" == "apply" || "$ACTION" == "refresh" || "$ACTION" == "plan") ]]; then
    
    # We only show the "LIVE" summary if the resources actually exist
    PROJECT_ID=$(terraform output -raw project_id 2>/dev/null)
    BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null)
    
    # Discovery (Suppress errors if instance isn't created yet)
    INSTANCE_INFO=$(gcloud compute instances list --filter="name ~ hpc-node" --project="$PROJECT_ID" --format="csv[no-heading](name,zone)" 2>/dev/null | head -n 1)
    
    if [[ ! -z "$INSTANCE_INFO" ]]; then
        INSTANCE_NAME=$(echo "$INSTANCE_INFO" | cut -d',' -f1)
        INSTANCE_ZONE=$(echo "$INSTANCE_INFO" | cut -d',' -f2)

        echo ""
        echo "--------------------------------------------------------------------------------"
        echo "✨  Compute Cluster Forge: Clean Summary"
        echo "--------------------------------------------------------------------------------"
        echo "✅ Cluster is LIVE in project: $PROJECT_ID"
        echo "📦 Storage Bucket: $BUCKET_NAME"
        echo "🖥️  VM Instance: $INSTANCE_NAME ($INSTANCE_ZONE)"
        echo ""
        echo "🚀 To SSH into your VM:"
        echo "   gcloud compute ssh $INSTANCE_NAME --tunnel-through-iap --project=$PROJECT_ID --zone=$INSTANCE_ZONE"
        echo ""
        echo "🌐 To Tunnel the Web App (Port 8080 -> Local 8080):"
        echo "   gcloud compute start-iap-tunnel $INSTANCE_NAME 8080 --local-host-port=localhost:8080 --project=$PROJECT_ID --zone=$INSTANCE_ZONE"
        echo ""
        echo "📓 To Tunnel Jupyter Lab (Port 8888 -> Local 8888):"
        echo "   gcloud compute start-iap-tunnel $INSTANCE_NAME 8888 --local-host-port=localhost:8888 --project=$PROJECT_ID --zone=$INSTANCE_ZONE"
        echo "--------------------------------------------------------------------------------"
    fi
fi
