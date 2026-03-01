# Secure n8n Container Host Deployment

This repository manages the Infrastructure as Code (IaC) and Secure Supply Chain for deploying n8n on a container host.

## Project Structure
- `.github/workflows/`: Secure image promotion pipeline.
- `iac/n8n/`: Docker Compose and environment configuration for n8n.
- `scripts/`: Implementation-specific scripts/utilities.

## Secure Supply Chain Architecture
To ensure only trusted and secure images are deployed, we use a **Verification & Promotion** model:

1. **Pull**: The [Image Promotion](.github/workflows/image-promotion.yml) workflow pulls the official n8n image from Docker Hub (`n8nio/n8n`).
2. **Scan**: [Trivy](https://github.com/aquasecurity/trivy) performs a security scan. 
   - **Gate**: The workflow fails if any **CRITICAL** or **HIGH** vulnerabilities are found.
3. **Verify**: Integrity is checked via image digests. (Optional: Cosign provenance verification).
4. **Push**: Verified images are pushed to GitHub Container Registry (GHCR) as your **Trusted Source**.

## How to Get Started

### 1. Populate Trusted Source
Go to **Actions** -> **Image Promotion (Trusted Source)** -> **Run workflow**. This ensures the images exist in your GHCR.

### 2. Deploy to Container Host
On your host:
```bash
git clone <this-repo-url>
cd iac/n8n
cp .env.template .env
# Update .env with your secure passwords and host configuration (HOST_IP)
docker compose up -d
```

## Security Policy
- All images **MUST** be pulled from `ghcr.io/swee/container-host/*`.
- Direct pulls from Docker Hub on the host are discouraged to maintain provenance and security control.
