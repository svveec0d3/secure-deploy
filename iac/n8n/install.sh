#!/bin/bash

# Exit on error
set -e

echo "============================================="
echo "        n8n Secure Deployment Setup         "
echo "============================================="
echo "This script will help you configure and deploy"
echo "your n8n container stack automatically."
echo ""

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker and Docker Compose first."
    exit 1
fi

# Detect Current Host IP
# This finds the primary IP address facing the default route (typically the one used for external/LAN access)
DETECTED_IP=$(ip -4 route get 8.8.8.8 | awk {'print $7'} | tr -d '\n')

if [ -z "$DETECTED_IP" ]; then
    DETECTED_IP="127.0.0.1"
fi

echo "The HOST_IP is required for n8n Webhook integrations."
echo "I have automatically detected your current Host IP as: $DETECTED_IP"
echo ""
read -p "Enter your Host IP address (or press Enter to use $DETECTED_IP): " USER_IP

if [ -z "$USER_IP" ]; then
    FINAL_IP=$DETECTED_IP
else
    FINAL_IP=$USER_IP
fi

echo ""
echo "✅ Using HOST_IP: $FINAL_IP"

# Create .env from template if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file from template..."
    cp .env.template .env
else
    echo "📝 Updating existing .env file..."
fi

# Update the HOST_IP in the .env file
# Works for both macOS (sed -i '') and Linux (sed -i)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^HOST_IP=.*/HOST_IP=$FINAL_IP/" .env
else
    sed -i "s/^HOST_IP=.*/HOST_IP=$FINAL_IP/" .env
fi

echo "🚀 Deploying n8n container..."
echo "---------------------------------------------"

# Start the docker containers
docker compose up -d

echo "---------------------------------------------"
echo "⏳ Waiting for n8n to start..."
sleep 5

# Check if container is running
if docker ps | grep -q "n8n-trusted"; then
    echo ""
    echo "🎉 SUCCESS! n8n has been successfully deployed."
    echo "============================================="
    echo "🔗 Get started by opening your browser to:"
    echo "http://$FINAL_IP:5678"
    echo "============================================="
    echo "To view logs, run: docker compose logs -f"
else
    echo "⚠️ The container might not have started correctly."
    echo "Run 'docker compose logs' to diagnose any issues."
fi
