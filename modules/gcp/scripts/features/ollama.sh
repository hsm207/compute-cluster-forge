#!/bin/bash
# ------------------------------------------------------------------------------
# Feature: Ollama Local LLM Runner
# Purpose: Installs and configures Ollama for secure local model execution.
# ------------------------------------------------------------------------------

set -e # Terminate on error

# --- Configuration ---
OLLAMA_INSTALL_URL="https://ollama.com/install.sh"
SYSTEMD_OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"

log() {
    echo "[Ollama Feature] $1"
}

install_ollama() {
    if command -v ollama >/dev/null 2>&1; then
        log "Ollama is already installed. Skipping installation."
        return
    fi

    log "📥 Fetching and executing Ollama installer..."
    curl -fsSL "$OLLAMA_INSTALL_URL" | sh
}

configure_service() {
    log "⚙️  Configuring systemd overrides for IAP compatibility..."
    
    mkdir -p "$SYSTEMD_OVERRIDE_DIR"
    
    cat <<EOF > "$SYSTEMD_OVERRIDE_DIR/override.conf"
[Service]
# Bind to 0.0.0.0 to allow IAP TCP forwarding to reach the service
Environment="OLLAMA_HOST=0.0.0.0"
# Keep models in memory for 24h to ensure low-latency responsiveness
Environment="OLLAMA_KEEP_ALIVE=24h"
EOF

    log "🔄 Restarting Ollama service with new configuration..."
    systemctl daemon-reload
    systemctl restart ollama
}

verify_installation() {
    log "🔍 Verifying service health..."
    if systemctl is-active --quiet ollama; then
        log "✅ Ollama service is active and healthy!"
    else
        log "❌ Ollama service failed to start. Check journalctl -u ollama."
        exit 1
    fi
}

# --- Execution ---
log "🚀 Starting Ollama feature initialization..."
install_ollama
configure_service
verify_installation
log "✨ Ollama feature setup complete!"
