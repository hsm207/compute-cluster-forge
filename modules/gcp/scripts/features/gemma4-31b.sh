#!/bin/bash
# ------------------------------------------------------------------------------
# Feature: Gemma 4 31B QAT (High Performance)
# Purpose: Orchestrates the retrieval of the quantized Gemma 4 31B model.
# Dependency: Requires the 'ollama' feature to be active.
# ------------------------------------------------------------------------------

set -e # Terminate on error

# --- Configuration ---
MODEL_NAME="gemma4:31b"
OLLAMA_API_TIMEOUT=600 # 10 minutes

log() {
    echo "[Gemma4-31B Feature] $1"
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
    log "📥 Initiating pull for high-performance model: $MODEL_NAME"
    log "Note: This is a heavy model and will take time to download."
    
    ollama pull "$MODEL_NAME"
}

verify_model() {
    log "🔍 Verifying model availability..."
    if ollama list | grep -q "gemma4:31b"; then
        log "✅ Model $MODEL_NAME is successfully installed and ready for use!"
    else
        log "❌ Model $MODEL_NAME was not found after pull attempt."
        exit 1
    fi
}

# --- Execution ---
log "🚀 Starting Gemma4-31B feature initialization..."
export HOME="/home/${gcp_user}" # This one IS handled by Terraform
wait_for_ollama
pull_model
verify_model
log "✨ Gemma4-31B feature setup complete!"
