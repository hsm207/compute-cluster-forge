#!/bin/bash

# --- Global Paths ---
# Capture the absolute repository root BEFORE any 'cd' operations
REPO_ROOT=$(cd "$(dirname "$0")" && pwd)

# Default Configuration
CLOUD="gcp"
TYPE="spike"
ACTION="plan"
LAYERS=()
EXTRA_TF_VARS=()
FINAL_VAR_ARGS=()

# --- Utilities ---

# Resolves the current GCP user account and formats it for Linux/SSH compatibility
get_gcp_user_prefix() {
    local RAW_EMAIL=$(gcloud config get-value account 2>/dev/null)
    echo "$RAW_EMAIL" | tr '@.' '__'
}

get_instance_name_prefix() {
    terraform output -raw instance_name_prefix 2>/dev/null || echo "hpc-node"
}

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

inject_windows_ssh_config() {
    local PROJ_ID="$1"
    local ZONE="$2"
    local INSTANCE_PREFIX="$3"
    
    # Only run this block if the user is executing the script inside Windows Subsystem for Linux (WSL)
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo ""
        echo "🔍 WSL Environment Detected. Delegating SSH config injection to Windows PowerShell (pwsh)..."

        local GCP_USER=$(get_gcp_user_prefix)

        # 1. Resolve the absolute Linux path of the script using the global REPO_ROOT
        local SCRIPT_PATH_LINUX="$REPO_ROOT/modules/gcp/inject-ssh-config.ps1"
        
        # 2. Safely translate the Linux absolute path into an absolute Windows path
        local PS_SCRIPT_WIN_PATH=$(wslpath -w "$SCRIPT_PATH_LINUX")

        # 3. Execute pwsh.exe with the translated path and sever stdin (< /dev/null) to prevent hangs
        pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN_PATH" \
            -ProjectId "$PROJ_ID" \
            -Zone "$ZONE" \
            -GcpUser "$GCP_USER" \
            -InstancePrefix "$INSTANCE_PREFIX" < /dev/null
    fi
}

discover_instance_and_print_summary() {
    local PROJECT_ID=$(terraform output -raw project_id 2>/dev/null)
    local BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null)
    local INSTANCE_PREFIX=$(get_instance_name_prefix)

    # Use the same resolved args for the console call
    local ALLOWED_PORTS_RAW=$(echo "var.allowed_ports" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null)
    local REGION=$(echo "var.region" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null | tr -d '"')
    
    echo ""
    echo "⏳ Waiting for Instance Group Manager to finish deploying new VMs... (this may take a few minutes)"
    gcloud compute instance-groups managed wait-until hpc-manager --version-target-reached --region="$REGION" --project="$PROJECT_ID" --timeout=600 >/dev/null 2>&1
    
    local INSTANCE_INFO=$(gcloud compute instances list --filter="name ~ $INSTANCE_PREFIX" --project="$PROJECT_ID" --format="csv[no-heading](name,zone)" 2>/dev/null | head -n 1)
    
    if [[ ! -z "$INSTANCE_INFO" ]]; then
        local INSTANCE_NAME=$(echo "$INSTANCE_INFO" | cut -d',' -f1)
        local INSTANCE_ZONE=$(echo "$INSTANCE_INFO" | cut -d',' -f2)
        local GCP_USER=$(get_gcp_user_prefix)

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

        local HOST_PATTERN="${INSTANCE_PREFIX}-*"
        echo ""
        echo "💻 VS Code Remote-SSH Configuration (Linux/macOS Pattern):"
        echo "   Add this to your ~/.ssh/config for infinite scale:"
        echo ""
        echo "   Host $HOST_PATTERN"
        echo "       ProxyCommand gcloud compute start-iap-tunnel %h %p --listen-on-stdin --project=$PROJECT_ID --zone=$INSTANCE_ZONE"
        echo "       User $GCP_USER"
        echo ""
        echo "🔍 To find active node names for VS Code:"
        echo "   gcloud compute instances list --filter=\"name ~ $INSTANCE_PREFIX\" --format=\"value(name)\""
        echo "--------------------------------------------------------------------------------"
        
        # Cross-OS injection execution
        inject_windows_ssh_config "$PROJECT_ID" "$INSTANCE_ZONE" "$INSTANCE_PREFIX"
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