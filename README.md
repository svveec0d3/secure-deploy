# Secure n8n Container Host Deployment
[![CI](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml)
[![Image Promotion](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml)

This repository manages the Infrastructure as Code (IaC) and Secure Supply Chain for deploying n8n on a container host.

## Project Structure
- `.github/workflows/`: Secure image promotion pipeline.
- `iac/n8n/`: Docker Compose and environment configuration for n8n.
- `scripts/`: Implementation-specific scripts/utilities.

## Secure Supply Chain Architecture
To ensure only trusted and secure images are deployed, we use a **Verification & Promotion** model:

1. **Pull**: The [Image Promotion](.github/workflows/image-promotion.yml) workflow pulls the official n8n image from Docker Hub (`n8nio/n8n`).
   - **Docker Content Trust**: `DOCKER_CONTENT_TRUST=1` is enabled to enforce image integrity verification directly from Docker Hub via Notary signatures.
2. **Scan**: [Trivy](https://github.com/aquasecurity/trivy) performs a security scan. 
   - **Gate**: The workflow evaluates vulnerabilities and conditionally pauses if any **CRITICAL** or **HIGH** vulnerabilities are found.
3. **Verify & Attest**: 
   - Generates an **SBOM (Software Bill of Materials)** using Syft.
   - Pushes the image to GHCR and automatically attests both the **SBOM** and **SLSA Build Provenance** dynamically to the image registry using GitHub Actions integrations. This provides cryptographically verifiable proof of compilation and contents.

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

3. **Log In**:
   Follow the URL outputted by the script (e.g., `http://<YOUR_IP>:5678`) to begin building n8n workflows!

## How to Get Started

1. **Clone the repo** on your container host:
   ```bash
   git clone https://github.com/svveec0d3/secure-deploy.git
   cd secure-deploy/iac/n8n
   ```

2. **Run the Interactive Setup Script**:
   We have included an automated script that detects your Host IP, configures your environment, and spins up the container!
   
   **Note**: The script requires the [GitHub CLI (`gh`)](https://github.com/cli/cli#installation) to securely authenticate and cryptographically verify the SLSA provenance and SBOM attachments of the image *before* allowing the deployment to proceed.
   
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

   Follow the URL outputted by the script (e.g., `http://<YOUR_IP>:5678`) to begin building n8n workflows!

## Security Policy
- All images **MUST** be pulled from `ghcr.io/svveec0d3/secure-deploy/*`.
- Direct pulls from Docker Hub on the host are discouraged to maintain provenance and security control.
