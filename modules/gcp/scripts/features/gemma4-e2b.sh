#!/bin/bash
# ------------------------------------------------------------------------------
# Feature: Gemma 4 E2B (Experimental)
# Purpose: Orchestrates the retrieval of the Gemma 4 E2B model.
# Dependency: Requires the 'ollama' feature to be active.
# ------------------------------------------------------------------------------

set -e # Terminate on error

# --- Configuration ---
MODEL_NAME="gemma4:e2b"
OLLAMA_API_TIMEOUT=600 # 10 minutes

log() {
    echo "[Gemma4-E2B Feature] $1"
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
    log "📥 Initiating pull for model: $MODEL_NAME"
    ollama pull "$MODEL_NAME"
}

verify_model() {
    log "🔍 Verifying model availability..."
    if ollama list | grep -q "gemma4:e2b"; then
        log "✅ Model $MODEL_NAME is successfully installed and ready for use!"
    else
        log "❌ Model $MODEL_NAME was not found after pull attempt."
        exit 1
    fi
}

# --- Execution ---
log "🚀 Starting Gemma4-E2B feature initialization..."
export HOME="/home/${gcp_user}" # This one IS handled by Terraform
wait_for_ollama
pull_model
verify_model
log "✨ Gemma4-E2B feature setup complete!"
