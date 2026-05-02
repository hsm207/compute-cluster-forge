# --- GCP Probe: Implements standard Cluster Forge health-check interface ---

wait_for_readiness() {
    local PROJECT_ID=$(terraform output -raw project_id 2>/dev/null)
    local REGION=$(echo "var.region" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null | tr -d '"')
    local TARGET_SIZE=$(echo "var.instance_count" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null | tr -d '"')
    local MIG_NAME="hpc-manager"
    
    # Calculate MAX_RETRIES based on the number of zones we are allowed to 'hop' between.
    # We give it 2 attempts per zone (one for initial try, one for a potential retry).
    local ZONE_COUNT=$(gcloud compute instance-groups managed describe "$MIG_NAME" --region="$REGION" --project="$PROJECT_ID" --format="value(distributionPolicy.zones.len())")
    local MAX_RETRIES=$((ZONE_COUNT * 2))
    local ATTEMPT=1

    echo "🎯 GCP Probe: Distribution policy covers $ZONE_COUNT zone(s). Setting max retries to $MAX_RETRIES."

    while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
        echo "⏳ GCP Probe (Attempt $ATTEMPT/$MAX_RETRIES): Waiting for Managed Instance Group '$MIG_NAME' to stabilize..."
        
        # We wait up to 2 minutes for stability per attempt.
        # This gives GCP enough time to reach the 'ZONE_RESOURCE_POOL_EXHAUSTED' error state if capacity is missing.
        gcloud compute instance-groups managed wait-until "$MIG_NAME" --stable --region="$REGION" --project="$PROJECT_ID" --timeout=120 >/dev/null 2>&1
        
        local INSTANCE_INFO_JSON=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" --region="$REGION" --project="$PROJECT_ID" --format="json")
        
        if [[ -z "$INSTANCE_INFO_JSON" || "$INSTANCE_INFO_JSON" == "[]" ]]; then
            echo "   ... No instances found yet, waiting for MIG to initiate..."
            sleep 10
            ((ATTEMPT++))
            continue
        fi

        # Detect resource exhaustion (ZONE_RESOURCE_POOL_EXHAUSTED)
        # Official GCP Docs state that 'ANY' shape MIGs are 'sticky' and won't hop zones on creation failures
        # unless the failing instance is purged.
        local EXHAUSTED_COUNT=$(echo "$INSTANCE_INFO_JSON" | jq '[.[] | select(.lastAttempt.errors.errors[0].code == "ZONE_RESOURCE_POOL_EXHAUSTED_WITH_DETAILS")] | length')
        
        if [[ "$EXHAUSTED_COUNT" -gt 0 ]]; then
            echo "🚨 GCP Probe detected resource exhaustion in the current zone(s)!"
            echo "   - Purging failed instances to force the MIG to hop zones..."
            
            # The most effective way to flush a 'sticky' ANY shape for a single-node run
            # is a quick resize to 0 and back to target_size. This resets the scheduler's zone choice.
            gcloud compute instance-groups managed resize "$MIG_NAME" --size=0 --region="$REGION" --project="$PROJECT_ID" --quiet >/dev/null 2>&1
            sleep 5
            gcloud compute instance-groups managed resize "$MIG_NAME" --size="$TARGET_SIZE" --region="$REGION" --project="$PROJECT_ID" --quiet >/dev/null 2>&1
            
            echo "   - Resize complete. MIG is now scouting for a new zone with capacity."
            ((ATTEMPT++))
            continue
        fi

        # Check for general success
        local UNHEALTHY_COUNT=$(echo "$INSTANCE_INFO_JSON" | jq '[.[] | select(.instanceStatus != "RUNNING" or (.instanceHealth != null and .instanceHealth[0].detailedHealthState != "HEALTHY"))] | length')

        if [[ "$UNHEALTHY_COUNT" -eq 0 ]]; then
            echo "✅ GCP Probe: All instances are healthy and RUNNING."
            return 0
        fi

        # If it's unstable but not exhausted, just wait for the next loop iteration
        echo "   ... Cluster is still stabilizing ($UNHEALTHY_COUNT node(s) not yet ready)..."
        sleep 15
        ((ATTEMPT++))
    done

    # Final Failure Report
    echo "❌ GCP Probe: Cluster failed to stabilize after $MAX_RETRIES attempts."
    exit 1
}

print_summary() {
    local PROJECT_ID=$(terraform output -raw project_id 2>/dev/null)
    local BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null)
    local INSTANCE_PREFIX=$(get_instance_name_prefix)
    local REGION=$(echo "var.region" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null | tr -d '"')
    local ALLOWED_PORTS_RAW=$(echo "var.allowed_ports" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null)

    local INSTANCE_INFO=$(gcloud compute instances list --filter="name ~ $INSTANCE_PREFIX" --project="$PROJECT_ID" --format="csv[no-heading](name,zone)" 2>/dev/null | head -n 1)
    
    if [[ ! -z "$INSTANCE_INFO" ]]; then
        local INSTANCE_NAME=$(echo "$INSTANCE_INFO" | cut -d',' -f1)
        local INSTANCE_ZONE=$(echo "$INSTANCE_INFO" | cut -d',' -f2)
        local GCP_USER=$(get_gcp_user_prefix)

        echo ""
        echo "--------------------------------------------------------------------------------"
        echo "✨  Compute Cluster Forge: Summary Report"
        echo "--------------------------------------------------------------------------------"
        echo "✅ [SUCCESS] Cluster is active in project: $PROJECT_ID"
        echo "📦 Storage Bucket: $BUCKET_NAME"
        echo "🖥️  VM Instance: $INSTANCE_NAME ($INSTANCE_ZONE)"
        echo ""
        echo "🚀 To SSH into your VM:"
        echo "   gcloud compute ssh $INSTANCE_NAME --tunnel-through-iap --project=$PROJECT_ID --zone=$INSTANCE_ZONE"
        
        if [[ ! -z "$ALLOWED_PORTS_RAW" ]]; then
            local PORTS=$(echo "$ALLOWED_PORTS_RAW" | tr -d 'tolist()[]" ' | tr ',' '\n' | grep -v "^")
            for PORT in $PORTS; do
                if [[ "$PORT" != "22" ]]; then
                    echo ""
                    echo "🌐 To Tunnel Port $PORT (Remote $PORT -> Local $PORT):"
                    echo "   gcloud compute start-iap-tunnel $INSTANCE_NAME $PORT --local-host-port=localhost:$PORT --project=$PROJECT_ID --zone=$INSTANCE_ZONE"
                fi
            done
        fi
        
        # Software Feature Summary
        if [[ ! -z "$ALLOWED_PORTS_RAW" && "$ALLOWED_PORTS_RAW" != "[]" ]]; then
            echo ""
            echo "🛠️  Deployment Features:"
            local FEATURE_LIST=$(echo "var.active_features" | terraform console "${FINAL_VAR_ARGS[@]}" 2>/dev/null)
            if [[ ! -z "$FEATURE_LIST" ]]; then
                echo "   $FEATURE_LIST"
            fi
        fi

        echo ""
        echo "--------------------------------------------------------------------------------"
        echo "✅ Cluster deployment and health verification successfully completed."
        echo "--------------------------------------------------------------------------------"
    fi
}
