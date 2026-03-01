# 🔐 Secure Deploy — Enterprise Vendor Image Ingestion Pipeline

[![CI](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml)
[![Image Promotion](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml)

---

## 🎯 Purpose & Context

Most enterprise security teams focus on securing internally built images but overlook a critical blind spot: **vendor-supplied images pulled directly from public registries like Docker Hub**.

When teams run `docker pull n8nio/n8n:latest` on a production server, they are:
- ❌ Trusting an external party with no internal verification
- ❌ Using a mutable tag that can silently change
- ❌ Skipping vulnerability and exploit checks
- ❌ Leaving no audit trail of what was deployed and when

This repository is a **reference implementation** that demonstrates how an enterprise security team should handle the ingestion, verification, and promotion of vendor-supplied container images before they ever reach production infrastructure.

> **Illustrated use case**: [n8n](https://n8n.io) — a workflow automation platform. The same pipeline pattern applies to any vendor image (Dify, Grafana, Keycloak, etc.).

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CI/CD PIPELINE                           │
│                                                                 │
│  Developer / Scheduler                                          │
│       │                                                         │
│       ▼  trigger: workflow_dispatch (explicit version required) │
│  ┌──────────────┐                                               │
│  │  Scan Job    │                                               │
│  │              │                                               │
│  │ 1. Resolve   │  Fetch SHA256 digest from Docker Hub API      │
│  │    Digest    │  → pull by digest (immutable, tamper-proof)   │
│  │              │                                               │
│  │ 2. CVE Scan  │  Trivy scans ALL severities (CRIT/HIGH/MED/LOW)│
│  │              │                                               │
│  │ 3. KEV Check │  Cross-reference with CISA KEV catalogue      │
│  │              │  (any severity in KEV = escalated risk)       │
│  └──────┬───────┘                                               │
│         │                                                       │
│    ┌────┴──────────────────────────────────────┐               │
│    │                                            │               │
│    ▼ Clean image                                ▼ CRIT/HIGH or KEV hit
│  ┌──────────────┐                        ┌─────────────────┐   │
│  │ Auto-Promote │                        │ Manual Approval │   │
│  │              │                        │ (human reviews  │   │
│  │ Push to GHCR │                        │ scan report)    │   │
│  └──────┬───────┘                        └────────┬────────┘   │
│         └────────────────┬───────────────────────┘            │
│                          ▼                                      │
│              ┌───────────────────────┐                          │
│              │  Attest & Release     │                          │
│              │                       │                          │
│              │ • SLSA Provenance     │                          │
│              │ • SBOM attestation    │                          │
│              │ • GitHub Release      │                          │
│              │   (digest-pinned ref) │                          │
│              └───────────────────────┘                          │
└─────────────────────────────────────────────────────────────────┘

              ↓ deploy

┌──────────────────────────────────────────────────────┐
│                      HOST VM                         │
│                                                      │
│  install.sh                                          │
│   1. Detects host IP                                 │
│   2. Verifies SLSA provenance via GitHub CLI (gh)    │
│      → abort if tampered or not from pipeline        │
│   3. docker compose up -d                            │
└──────────────────────────────────────────────────────┘
```

---

## 🛡️ Security Controls Implemented

| Control | Tool / Mechanism | Purpose |
|---------|-----------------|---------|
| **Immutable Image Pinning** | SHA256 digest from Docker Hub Manifest API | Eliminates mutable tag risk (`latest` banned) |
| **CVE Vulnerability Scan** | [Trivy](https://trivy.dev) — all severities | Detects known vulnerabilities before promotion |
| **CISA KEV Cross-Reference** | [CISA KEV catalogue](https://www.cisa.gov/known-exploited-vulnerabilities-catalog) | Flags CVEs actively exploited in the wild — even if MEDIUM or LOW severity |
| **Conditional Approval Gate** | GitHub Environments (`trusted-promotion`) | Any CRITICAL/HIGH or KEV match requires human sign-off |
| **IaC & Secret Scanning** | Trivy `fs` scan on every commit/PR | Catches misconfigurations and leaked secrets before merge |
| **SLSA Build Provenance** | `actions/attest-build-provenance` | Cryptographically proves the image was built by this pipeline |
| **SBOM Generation** | Syft via `anchore/sbom-action` | Full software inventory for auditing and compliance |
| **Version Control & Rollback** | GitHub Releases with digest-pinned refs | Every promoted image has an immutable rollback reference |
| **Host Verification** | `gh attestation verify` in `install.sh` | Proves to the VM that the image originated from this pipeline |

---

## 📁 Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                  # Pre-merge: IaC misconfiguration & secret scan
│       └── image-promotion.yml     # Vendor image ingestion & promotion pipeline
│
└── iac/
    └── n8n/
        ├── docker-compose.yml      # Container stack definition
        ├── .env.template           # Environment template (copy to .env)
        └── install.sh              # Interactive setup & host verification script
```

---

## 🚀 How to Run

### Step 1 — One-Time GitHub Setup

1. Go to **Settings → Environments** → **New environment** → name it `trusted-promotion`
2. Enable **Required reviewers** and add yourself as a reviewer
3. Go to **Settings → Actions → General → Workflow permissions**
4. Select **Read and write permissions**
5. Go to **Packages** → find `n8n-trusted` → **Package Settings → Change visibility → Public**

### Step 2 — Promote a Trusted Image

1. Go to **Actions → Image Promotion (Trusted Source) → Run workflow**
2. Enter an **explicit version** (e.g. `1.55.3`) — `latest` is not accepted
3. The pipeline will:
   - Resolve the image's immutable SHA256 digest
   - Scan for vulnerabilities (all severities)
   - Cross-check against CISA KEV
   - **Auto-promote** if clean — OR **pause for your approval** if CRITICAL/HIGH or KEV match found
   - On success: attest provenance + SBOM, create a GitHub Release with rollback info

### Step 3 — Deploy to Host VM

```bash
# Clone the repository on your VM
git clone https://github.com/svveec0d3/secure-deploy.git
cd secure-deploy/iac/n8n

# Install GitHub CLI for provenance verification (recommended)
# https://github.com/cli/cli#installation
gh auth login

# Run the setup script
chmod +x install.sh
./install.sh
```

The `install.sh` script will:
- Detect your VM's IP address (with option to override)
- Optionally verify the image's cryptographic provenance against GitHub's attestation store
- Deploy the container via Docker Compose
- Print the access URL

### Step 4 — Rolling Back to a Previous Version

All promoted versions are listed under [Releases](https://github.com/svveec0d3/secure-deploy/releases).

Each release contains the exact digest-pinned pull command. To rollback:

1. Find the release version you want (e.g. `1.54.0`)
2. On your VM, edit `iac/n8n/.env`:
   ```
   N8N_IMAGE_VERSION=1.54.0
   ```
3. Run:
   ```bash
   docker compose pull && docker compose up -d
   ```

---

## 📋 Approval Gate Logic

```
CRITICAL or HIGH CVE detected?    → YES → Manual Approval Required ⚠️
              ↓ NO
Any CVE (any severity) in KEV?    → YES → Manual Approval Required ⚠️
              ↓ NO
         Auto-Promote ✅
```

Reviewers will find a detailed `scan-report-<version>` artifact attached to the workflow run containing:
- Full CVE list split by CRITICAL/HIGH and MEDIUM/LOW
- CISA KEV matches with vendor details and descriptions
- The pinned source digest

---

## 🔒 Security Policy

- Images **must** originate from `ghcr.io/svveec0d3/secure-deploy/*` — never pulled directly from Docker Hub on the host
- Every production image must have a corresponding [GitHub Release](https://github.com/svveec0d3/secure-deploy/releases) with attested SLSA provenance and SBOM
- The `trusted-promotion` environment ensures a human reviewed the risk before any vulnerable or KEV-matched image is promoted
