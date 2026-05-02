#!/bin/bash
# ------------------------------------------------------------------------------
# Feature: Gemma 4 26B (VRAM Optimized)
# Purpose: Orchestrates the retrieval of the Gemma 4 26B model.
# Note: Fits perfectly in 24GB L4 VRAM for 100% GPU offloading.
# Dependency: Requires the 'ollama' feature to be active.
# ------------------------------------------------------------------------------

set -e # Terminate on error

# --- Configuration ---
MODEL_NAME="gemma4:26b"
OLLAMA_API_TIMEOUT=600 # 10 minutes

log() {
    echo "[Gemma4-26B Feature] $1"
}

wait_for_ollama() {
    log "⏳ Waiting for Ollama API to become responsive..."
    local start_time=$(date +%s)
    
    until curl -s http://localhost:11434/api/tags > /dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $OLLAMA_API_TIMEOUT ]; then
            log "❌ Timeout reached waiting for Ollama API."
            exit 1
        fi
        
        log "...still waiting ($elapsed/$OLLAMA_API_TIMEOUT s)..."

        sleep 5
    done
    
    log "🟢 Ollama API is ready!"
}

pull_model() {
    log "📥 Initiating pull for VRAM-optimized model: $MODEL_NAME"
    log "Note: This model fits perfectly in your L4 GPU's 24GB VRAM."
    
    ollama pull "$MODEL_NAME"
}

verify_model() {
    log "🔍 Verifying model availability..."
    # We use $${} to escape the dollar sign for Terraform's templatefile
    if ollama list | grep -q "gemma4:26b"; then
        log "✅ Model $MODEL_NAME is successfully installed and ready for use!"
    else
        log "❌ Model $MODEL_NAME was not found after pull attempt."
        exit 1
    fi
}

# --- Execution ---
log "🚀 Starting Gemma4-26B feature initialization..."
export HOME="/home/${gcp_user}" # This one IS handled by Terraform
wait_for_ollama
pull_model
verify_model
log "✨ Gemma4-26B feature setup complete!"
