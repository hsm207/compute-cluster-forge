#!/bin/bash

# Default Configuration
CLOUD="gcp"
TYPE="spike"
ACTION="plan"
LAYERS=()
EXTRA_TF_VARS=()
FINAL_VAR_ARGS=()

parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --cloud) CLOUD="$2"; shift ;;
            --type) TYPE="$2"; shift ;;
            --action) ACTION="$2"; shift ;;
            --layer) LAYERS+=("$2"); shift ;;
            --var) EXTRA_TF_VARS+=("$2"); shift ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done
}

map_cloud_to_module() {
    case $CLOUD in
        gcp) MODULE_DIR="modules/gcp" ;;
        *) echo "Cloud $CLOUD not supported yet! 🚀" >&2; exit 1 ;;
    esac
}

# Resolve all variable files (base + layers) and overrides BEFORE changing directories
resolve_paths_and_vars() {
    local BASE_VAR_FILE="templates/${TYPE}.tfvars"
    if [[ -f "$BASE_VAR_FILE" ]]; then
        FINAL_VAR_ARGS+=("-var-file=$(readlink -f "$BASE_VAR_FILE")")
    fi
    
    for LAYER in "${LAYERS[@]}"; do
        local LAYER_PATH="templates/${LAYER}.tfvars"
        if [[ ! -f "$LAYER_PATH" ]]; then
            echo "Error: Layer file $LAYER_PATH not found." >&2
            exit 1
        fi
        FINAL_VAR_ARGS+=("-var-file=$(readlink -f "$LAYER_PATH")")
    done

    for OVERRIDE in "${EXTRA_TF_VARS[@]}"; do
        FINAL_VAR_ARGS+=("-var" "$OVERRIDE")
    done
}

initialize_workspace() {
    cd "$MODULE_DIR" || exit
    [[ ! -d ".terraform" ]] && terraform init
    terraform workspace select "$TYPE" 2>/dev/null || terraform workspace new "$TYPE"
}

execute_terraform_action() {
    echo "--------------------------------------------------------------------------------"
    echo "🛠️  Compute Cluster Forge: Executing $ACTION for $CLOUD ($TYPE)"
    [[ ${#LAYERS[@]} -gt 0 ]] && echo "🥞 Layers applied: ${LAYERS[*]}"
    [[ ${#EXTRA_TF_VARS[@]} -gt 0 ]] && echo "🎯 Manual overrides applied!"
    echo "--------------------------------------------------------------------------------"

    if [[ "$ACTION" == "plan" || "$ACTION" == "apply" || "$ACTION" == "destroy" || "$ACTION" == "import" || "$ACTION" == "refresh" ]]; then
        local EXTRA_ARGS=()
        [[ "$ACTION" == "apply" || "$ACTION" == "destroy" ]] && EXTRA_ARGS+=("-auto-approve")
        
        terraform "$ACTION" "${FINAL_VAR_ARGS[@]}" "${EXTRA_ARGS[@]}"
    else
        terraform "$ACTION"
    fi
}

discover_instance_and_print_summary() {
    local PROJECT_ID=$(terraform output -raw project_id 2>/dev/null)
    local BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null)
    
    # Use the same resolved args for the console call
    local ALLOWED_PORTS_RAW=$(echo "var.allowed_ports" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null)
    local REGION=$(echo "var.region" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null | tr -d '"')
    
    echo ""
    echo "⏳ Waiting for Instance Group Manager to finish deploying new VMs... (this may take a few minutes)"
    gcloud compute instance-groups managed wait-until hpc-manager --version-target-reached --region="$REGION" --project="$PROJECT_ID" --timeout=600 >/dev/null 2>&1
    
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
        
        if [[ ! -z "$ALLOWED_PORTS_RAW" ]]; then
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
resolve_paths_and_vars
initialize_workspace
execute_terraform_action

if [[ "$?" -eq 0 && ("$ACTION" == "apply" || "$ACTION" == "refresh" || "$ACTION" == "plan") ]]; then
    discover_instance_and_print_summary
fi
