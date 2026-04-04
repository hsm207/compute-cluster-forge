#!/bin/bash

# Default Configuration
CLOUD="gcp"
TYPE="spike"
ACTION="plan"

parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --cloud) CLOUD="$2"; shift ;;
            --type) TYPE="$2"; shift ;;
            --action) ACTION="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done
}

map_cloud_to_module() {
    case $CLOUD in
        gcp) MODULE_DIR="modules/gcp" ;;
        aws) echo "AWS expansion coming soon! 🚀"; exit 1 ;;
        azure) echo "Azure expansion coming soon! 🚀"; exit 1 ;;
        *) echo "Invalid cloud: $CLOUD"; exit 1 ;;
    esac
}

validate_template_path() {
    VAR_FILE="templates/${TYPE}.tfvars"
    if [[ ! -f "$VAR_FILE" ]]; then
        echo "Error: Template file $VAR_FILE not found."
        exit 1
    fi
    VAR_FILE_ABS=$(readlink -f "$VAR_FILE")
}

initialize_workspace() {
    cd "$MODULE_DIR" || exit
    
    if [[ ! -d ".terraform" ]]; then
        terraform init
    fi

    terraform workspace select "$TYPE" 2>/dev/null || terraform workspace new "$TYPE"
}

execute_terraform_action() {
    echo "--------------------------------------------------------------------------------"
    echo "🛠️  Compute Cluster Forge: Executing $ACTION for $CLOUD ($TYPE)"
    echo "--------------------------------------------------------------------------------"

    if [[ "$ACTION" == "plan" || "$ACTION" == "apply" || "$ACTION" == "destroy" || "$ACTION" == "import" || "$ACTION" == "refresh" ]]; then
        local EXTRA_ARGS=""
        if [[ "$ACTION" == "apply" || "$ACTION" == "destroy" ]]; then
            EXTRA_ARGS="-auto-approve"
        fi
        terraform "$ACTION" -var-file="$VAR_FILE_ABS" $EXTRA_ARGS
    else
        terraform "$ACTION"
    fi
}

discover_instance_and_print_summary() {
    local PROJECT_ID=$(terraform output -raw project_id 2>/dev/null)
    local BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null)
    
    # Extract allowed ports from terraform using the correct piping method
    local ALLOWED_PORTS_RAW=$(echo "var.allowed_ports" | terraform console -var-file="$VAR_FILE_ABS" 2>/dev/null)
    
    local INSTANCE_INFO=$(gcloud compute instances list --filter="name ~ hpc-node" --project="$PROJECT_ID" --format="csv[no-heading](name,zone)" 2>/dev/null | head -n 1)
    
    if [[ ! -z "$INSTANCE_INFO" ]]; then
        local INSTANCE_NAME=$(echo "$INSTANCE_INFO" | cut -d',' -f1)
        local INSTANCE_ZONE=$(echo "$INSTANCE_INFO" | cut -d',' -f2)

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
        
        # Show tunnel commands for allowed ports (excluding port 22 which is for SSH)
        if [[ ! -z "$ALLOWED_PORTS_RAW" ]]; then
            # Clean the output (removes tolist, brackets, quotes, and whitespace)
            local PORTS=$(echo "$ALLOWED_PORTS_RAW" | tr -d 'tolist()[]" ' | tr ',' '\n' | grep -v "^$")
            for PORT in $PORTS; do
                if [[ "$PORT" != "22" ]]; then
                    echo ""
                    echo "🌐 To Tunnel Port $PORT (Remote $PORT -> Local $PORT):"
                    echo "   gcloud compute start-iap-tunnel $INSTANCE_NAME $PORT --local-host-port=localhost:$PORT --project=$PROJECT_ID --zone=$INSTANCE_ZONE"
                fi
            done
        fi
        echo "--------------------------------------------------------------------------------"
    fi
}

# --- Main Orchestration Flow ---
parse_arguments "$@"
map_cloud_to_module
validate_template_path
initialize_workspace
execute_terraform_action

# Only show summary on success for high-signal actions
if [[ "$?" -eq 0 && ("$ACTION" == "apply" || "$ACTION" == "refresh" || "$ACTION" == "plan") ]]; then
    discover_instance_and_print_summary
fi
