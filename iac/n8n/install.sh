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

# Check if provenance verification is possible
VERIFY_PROVENANCE=false
if command -v gh &> /dev/null && gh auth status &> /dev/null 2>&1; then
    VERIFY_PROVENANCE=true
else
    echo ""
    echo "⚠️  Optional: Cryptographic provenance verification requires the GitHub CLI (gh) and login."
    echo "   Install it at: https://github.com/cli/cli#installation"
    read -p "   Skip provenance verification and continue anyway? (Y/n): " SKIP_VERIFY
    SKIP_VERIFY=${SKIP_VERIFY:-Y}
    if [[ "$SKIP_VERIFY" =~ ^[Nn]$ ]]; then
        echo "Aborted. Please install and authenticate the GitHub CLI first."
        exit 1
    fi
    echo "   ⚠️  Skipping provenance verification."
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

echo "---------------------------------------------"
echo "🔐 Verifying Cryptographic Provenance & SBOM..."
echo "---------------------------------------------"
# This command verifies that the image was completely unaltered from our GitHub Actions CI/CD pipeline
# It checks both the SLSA provenance and the SBOM attestation.
if [ "$VERIFY_PROVENANCE" = true ]; then
    if gh attestation verify oci://ghcr.io/svveec0d3/secure-deploy/n8n-trusted:latest -o svveec0d3; then
        echo "✅ Image Signature and Provenance successfully verified!"
    else
        echo "❌ SECURITY ALERT: Image signature verification failed! The image might have been tampered with or did not originate from your trusted CI/CD pipeline."
        echo "Deployment aborted."
        exit 1
    fi
else
    echo "   ⚠️  Provenance check skipped."
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
