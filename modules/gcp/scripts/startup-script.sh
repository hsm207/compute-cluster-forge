#!/bin/bash

# Ensure all output is logged to the serial console for easy debugging
exec > >(tee -a /var/log/startup-script.log | logger -t startup-script -s 2>/dev/console) 2>&1

echo "🚀 Starting Compute Cluster Forge native software setup..."

echo "📦 Installing required system libraries..."
apt-get update
apt-get install -y libsecret-1-0 zstd

echo "🟩 Checking Node.js installation..."
if command -v node >/dev/null 2>&1; then
    echo "Node.js is already installed! Ensuring it is updated to the absolute latest version..."
else
    echo "Node.js is not installed. Forging the latest version from scratch! 🏗️"
fi

# We use Debian's package manager just to get a temporary foothold
apt-get install -y nodejs npm

# We install 'n', the ultra-lightweight Node version manager
echo "📥 Dynamically fetching the absolute latest bleeding-edge Node.js release..."
npm install -g n
n latest
hash -r # Refresh bash to immediately recognize the new binaries

# Verify the dynamically installed version
echo "🟩 Upgrade complete! Running on Node.js version: $(node -v)"

echo "✨ Installing Gemini CLI globally..."
npm install -g @google/gemini-cli

echo "🪣 Cluster data bucket: ${bucket_name}"

echo "✅ Native Startup script execution complete!"
