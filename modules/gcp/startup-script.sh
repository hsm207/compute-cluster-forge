#!/bin/bash

# Ensure all output is logged to the serial console for easy debugging
exec > >(tee -a /var/log/startup-script.log | logger -t startup-script -s 2>/dev/console) 2>&1

echo "🚀 Starting Compute Cluster Forge native software setup..."

# 1. Update OS and Install Packages
echo "📦 Installing essential packages..."
apt-get update
apt-get install -y git python3-pip htop

# 2. Demonstrate Data Bucket Integration
echo "🪣 Cluster data bucket: ${bucket_name}"

# 3. Create Web App Landing Page
echo "🌐 Building Web App Landing Page..."
mkdir -p /var/www/html
echo "<h1>HPC Cluster Running</h1>" > /var/www/html/index.html
echo "<p>Connected to GCS Bucket: <b>${bucket_name}</b></p>" >> /var/www/html/index.html

# 4. Start the Web Server (Port 8080)
echo "🚀 Starting Python HTTP Server on Port 8080..."
nohup python3 -m http.server 8080 --directory /var/www/html &

echo "✅ Native Startup script execution complete!"
