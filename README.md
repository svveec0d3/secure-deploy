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

### GitHub Actions Setup
1. Go to your repository **Settings > Environments**.
2. Click **New Environment** and name it `trusted-promotion`.
3. Check the **Required reviewers** box and add yourself.
4. Go to **Settings > Actions > General > Workflow permissions**.
5. Ensure **Read and write permissions** is selected so the Action can push to GHCR.

### Triggering the Pipeline
1. Upon any push to `main` (or via manual `workflow_dispatch`), the pipeline triggers.
2. The **Security Scan** job will run Trivy and upload a `trivy-vulnerability-report` Artifact. Download this from the Actions run summary to review existing Critical/High vulnerabilities.
3. If no vulnerabilities are found, the image is automatically tagged and pushed. 
4. If Critical/High vulnerabilities exist, the **Manual Approval Promotion** job will pause. Click **Review deployments** to manually override and approve the push to your trusted GHCR registry based on your assessment of the attached report.

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
