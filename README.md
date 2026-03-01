# 🔐 Secure Deploy – Enterprise Vendor Image Ingestion Pipeline

[![CI](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml)
[![Image Promotion](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml)

A reference implementation that demonstrates **secure ingestion, verification, and deployment** of vendor‑supplied container images (illustrated with [n8n](https://n8n.io)). It combines industry‑grade best practices – **SLSA**, **CIS Docker Benchmark v1.6.0**, and **NIST SP 800‑53** controls – into an end‑to‑end GitHub‑Actions CI/CD pipeline.

---

## 1️⃣ Threat Model & Risk Impact

| Threat | Description | Risk / Impact |
|-------|-------------|---------------|
| **Mutable tags** | Use of `:latest` or mutable tags allows the image content to change without notice. | Supply‑chain compromise, hidden back‑doors. |
| **Unknown provenance** | No cryptographic proof that the image originates from the vendor. | Tampering, malicious inserts. |
| **Missing audit trail** | No immutable record of which version was deployed, who approved it, and when. | Forensic gaps, regulatory non‑compliance. |
| **Delayed CVE exposure** | Images become vulnerable as new CVEs are disclosed after promotion. | Production breach risk, patch‑lag. |
| **Runtime escape** | Container can break out of its isolation and affect the host. | Privilege escalation, data exfiltration. |
| **Insufficient documentation** | Operators lack clear guidance on remediation and rollback. | Operational error, prolonged downtime. |

---

## 2️⃣ Controls Mapping & Mitigation (with SLSA Level)

| Threat | Control | Implementation Detail | Mitigation | SLSA Maturity |
|-------|--------|----------------------|------------|----------------|
| Mutable tags | **Digest pinning** | Resolve SHA‑256 digest at ingestion; runtime uses `image@sha256:<digest>` | Guarantees immutable image content. | **Level 3** – Provenance attestation & reproducible builds. |
| Unknown provenance | **SLSA Provenance attestation** | `actions/attest-build-provenance` attaches signed provenance to each promoted image. | Cryptographic proof of origin. | **Level 3** |
| Unknown provenance | **Cosign signature verification** | Verify vendor‑signed OCI signatures before promotion. | Detects unsigned or tampered images. | **Level 2** |
| Unknown provenance | **Source allowlist** | `policy/image‑ingestion‑policy.yml` restricts to `n8nio/n8n` with strict `x.y.z` semver. | Blocks unexpected sources. | **Level 2** |
| Missing audit trail | **SBOM generation** | Syft creates SPDX SBOM; stored as artifact and attested. | Full component inventory for compliance. | **Level 2** |
| Missing audit trail | **Versioned GitHub Releases** | Each promotion creates a release with digest, SBOM, and provenance links. | Immutable record of deployment. | **Level 3** |
| Delayed CVE exposure | **Trivy CVE scan** | Scans all severities; fails on CRITICAL/HIGH. | Early detection of vulnerable images. | **Level 2** |
| Delayed CVE exposure | **CISA KEV cross‑reference** | Automated check against known‑exploited CVE list. | Blocks actively exploited vulnerabilities. | **Level 2** |
| Runtime escape | **CIS Docker Benchmark v1.6.0 (Section 5)** | Enforced via `policy/runtime‑hardening‑policy.yml` – read‑only FS, `no‑new‑privileges`, `cap_drop: ALL`, AppArmor profile, non‑root user, resource limits, custom network. | Reduces blast radius, enforces least privilege. | **Level 2** |
| Operational gaps | **Approval gate** | `trusted‑promotion` environment requires manual review for flagged images. | Human risk acceptance decision. | **Level 2** |
| Operational gaps | **Weekly re‑scan** | `rescan.yml` re‑scans all promoted images; opens issue on new findings. | Continuous compliance monitoring. | **Level 2** |
| Operational gaps | **Host verification script** | `install.sh` runs `gh attestation verify` against exact digest before deployment. | Guarantees host runs the exact promoted image. | **Level 3** |

---

## 3️⃣ Pipeline Architecture

```mermaid
flowchart TD
    A[Developer / Scheduler] -->|workflow_dispatch| B[Scan Job]
    B --> C{Policy Checks}
    C -->|allowlist & semver| D[Cosign Verify]
    D --> E[Digest Resolve]
    E --> F[Trivy Scan]
    F --> G[KEV Cross‑Reference]
    G --> H{Result}
    H -->|Clean| I[Auto‑Promote]
    H -->|Vuln / KEV| J["Manual Approval (trusted‑promotion)"]
    I --> K[Attest Provenance & SBOM]
    J --> K
    K --> L[GitHub Release + Rollback Info]
```

* **Auto‑Promote** – No findings, image is pushed to GHCR and released.
* **Manual Approval** – Critical/High CVEs or KEV hit require reviewer sign‑off.
* All steps produce **artifacts** (reports, SBOM, provenance) and write a **Job Summary** for immediate visibility.

---

## 4️⃣ Repository Structure

```
.
├── policy/
│   ├── image-ingestion-policy.yml      # Allowlist, tag pattern, vendor signature mode
│   ├── vulnerability-gate-policy.yml   # CVE/KEV block rules, exception process, re‑scan policy
│   ├── runtime-hardening-policy.yml    # CIS Docker Benchmark v1.6.0 compliance table (Section 5)
│   └── cis-docker-hardening.md         # Human‑readable reference for all CIS checks performed
│
├── .github/workflows/
│   ├── ci.yml               # Pre‑merge: IaC & secret scan + CIS compliance (blocks on findings)
│   ├── image-promotion.yml  # Vendor image ingestion, scanning, attestation, promotion
│   └── rescan.yml           # Weekly re‑scan of all promoted images
│
└── iac/n8n/
    ├── docker-compose.yml   # CIS‑hardened stack (read‑only FS, non‑root, AppArmor, limits)
    ├── .env.template        # Template – copy to .env and populate
    └── install.sh           # Interactive setup: version selection, digest fetch, provenance verify, deploy
```

---

## 5️⃣ Operational Playbooks

### 📦 Promotion Runbook
1. **Actions → Image Promotion (Trusted Source) → Run workflow**
2. Provide a version (e.g. `1.55.3`) or leave blank for auto‑resolve.
3. Pipeline executes: policy → cosign → digest → Trivy → KEV → gate.
4. **Clean** – Auto‑promoted, GitHub Release created with digest & rollback info.
5. **Vulnerable** – Workflow pauses; reviewer downloads `scan-report-<version>` artifact, reviews `trivy-summary.txt` and `vendor-sig-check.txt`, then approves or rejects in the `trusted-promotion` environment.

### ⚖️ Exception / Waiver Process
1. Download the scan artifact as evidence.
2. Document accepted risk (CVE IDs, severity, KEV status, business justification) in the release notes.
3. Set a **review deadline** – date by which a patched version must be deployed or the exception renewed.
4. Update `policy/vulnerability-gate-policy.yml` comments to reflect the new waiver.

### 🔄 Rollback Procedure
```bash
# Edit .env with values from the target release
nano iac/n8n/.env
# Example values
N8N_IMAGE_VERSION=1.54.0
N8N_IMAGE_DIGEST=sha256:abcd1234...
# Apply
docker compose up -d
```
Or re‑run `install.sh` and supply the target version when prompted.

### ⏱️ Re‑Scan & Patch Cadence
| Trigger | Action |
|---------|--------|
| Weekly (Mon 00:00 UTC) | `rescan.yml` re‑scans all GHCR images; opens a GitHub Issue on new findings |
| New CVE in CISA KEV list | Issue opened automatically on next scan – treat as P1 |
| New vendor release | Run promotion pipeline manually |

---

## 6️⃣ Security Policy (High‑Level)
- **Image source**: Must be `ghcr.io/svveec0d3/secure-deploy/*`; never pull directly from Docker Hub in production.
- **SLSA provenance**: Every promoted image is signed with `actions/attest-build-provenance` (SLSA Level 3).
- **SBOM**: Generated via Syft and attested to the registry.
- **CIS hardening**: Enforced by `runtime-hardening-policy.yml` (Section 5 controls).
- **Vulnerability gating**: Trivy + CISA KEV; critical/high findings block promotion.
- **Approval workflow**: `trusted-promotion` environment for manual risk acceptance.
- **Policy changes**: Require a reviewed pull request.

---

## 7️⃣ References & Best‑Practice Guides
- **SLSA** – https://slsa.dev/spec/v1.0
- **CIS Docker Benchmark v1.6.0** – https://www.cisecurity.org/benchmark/docker
- **NIST SP 800‑53 Rev 5** – https://csrc.nist.gov/publications/sp800-53/rev-5
- **CISA Known Exploited Vulnerabilities (KEV)** – https://www.cisa.gov/known-exploited-vulnerabilities-catalog

---

## 8️⃣ One‑Time GitHub Setup
1. **Settings → Environments → New environment** → name `trusted-promotion`; enable required reviewers.
2. **Settings → Actions → General → Workflow permissions** → **Read and write permissions**.
3. **Packages → `n8n‑trusted` → Settings → Change visibility → Public** (required for OCI attestation).

---

## 9️⃣ Deploying to a Host
```bash
# Clone the repository on the VM
git clone https://github.com/svveec0d3/secure-deploy.git
cd secure-deploy/iac/n8n

# Install GitHub CLI (recommended for provenance verification)
# https://github.com/cli/cli#installation
gh auth login

# Run the interactive installer
chmod +x install.sh
./install.sh
# Prompts: host IP, version (or auto‑resolve), resource limits, provenance verification
```
**Automation mode** (no prompts): `./install.sh --skip-verify`

---

*This README is version‑controlled; any changes to policies or controls must be reviewed via pull request to maintain auditability.*
[![CI](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml)
[![Image Promotion](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml)

A reference implementation of how an enterprise team should securely ingest, verify, and deploy vendor-supplied container images — illustrated with [n8n](https://n8n.io).

Do you download Docker images directly from a vendor or public repository in your enterprise? If so, using mutable tags like `latest` can introduce unverified and potentially compromised images. Instead, adopt verification steps such as digest pinning, provenance attestation, and policy enforcement as demonstrated in this repository.

---

## 1. Threat Model

| Threat | Description |
|--------|-------------|
| **Mutable tags** | `:latest` and named tags can silently change content under the same name |
| **Unknown provenance** | No guarantee the image came from the legitimate vendor — supply chain tampering |
| **No audit trail** | No record of what version was running, when it was deployed, or who approved it |
| **Delayed CVE exposure** | A clean image becomes vulnerable as new CVEs are published after promotion |
| **Runtime escape** | An exploited container can escalate or persist if the host is not hardened |

---

## 2. Controls Mapped to Threats

| Threat | Control | Implementation |
|--------|---------|----------------|
| Mutable tags | **Digest pinning** | Docker Hub SHA256 resolved at ingestion; host deploys `@sha256:…`, never a tag |
| Unknown provenance | **SLSA Provenance attestation** | `actions/attest-build-provenance` attaches a cryptographically signed provenance record to every promoted image |
| Unknown provenance | **Upstream cosign check** | Pipeline checks for vendor Sigstore signatures; documents risk gap if absent |
| Unknown provenance | **Source allowlist** | Only `n8nio/n8n` with strict `x.y.z` semver tags permitted — enforced via `policy/image-ingestion-policy.yml` |
| No audit trail | **SBOM generation** | Syft generates a full SPDX SBOM for every promoted image, attested to GHCR |
| No audit trail | **Versioned GitHub Releases** | Every promotion creates an immutable release with digest-pinned pull commands and rollback steps |
| Known CVEs | **Trivy CVE scan** | All severities (CRITICAL → LOW) scanned at promotion time |
| Exploited-in-wild CVEs | **CISA KEV cross-reference** | Any CVE matching the CISA Known Exploited Vulnerabilities catalogue triggers the approval gate, regardless of severity |
| Risk acceptance | **Approval gate** | Blocked images require human review via `trusted-promotion` GitHub Environment before promotion |
| Delayed CVE exposure | **Weekly re-scan** | Scheduled job re-scans all promoted GHCR images; opens a GitHub Issue if a previously clean image acquires new findings |
| Host-level integrity | **Host verification** | `install.sh` runs `gh attestation verify` against the exact digest before deploying |
| Runtime escape | **Container hardening** | CIS Docker Benchmark v1.6.0 Section 5 — `read_only`, `no-new-privileges`, `cap_drop: ALL`, AppArmor, non-root user, resource limits, custom network; enforced by CI |

---

## 3. Pipeline Architecture

```
  Developer / Scheduler
       │
       ▼  workflow_dispatch (explicit version or "latest" auto-resolved)
  ┌─────────────────────────────────────────────────────────┐
  │                     SCAN JOB                            │
  │  1. Policy check   → allowlist + semver enforcement     │
  │  2. Cosign check   → vendor signature or risk-gap log   │
  │  3. Digest resolve → immutable SHA256 from Docker Hub   │
  │  4. Trivy scan     → CRITICAL/HIGH/MEDIUM/LOW CVEs      │
  │  5. KEV check      → CISA catalogue cross-reference     │
  └──────┬──────────────────────────────────────┬───────────┘
         │ Clean                                │ CRIT/HIGH or KEV hit
         ▼                                      ▼
  ┌──────────────┐                     ┌─────────────────────┐
  │ Auto-Promote │                     │  Manual Approval    │
  │ (no gate)    │                     │  (trusted-promotion │
  └──────┬───────┘                     │   environment)      │
         └──────────────┬──────────────┴─────────────────────┘
                        ▼
            ┌───────────────────────┐
            │  Attest & Release     │
            │  • SLSA Provenance    │
            │  • SBOM attestation   │
            │  • GitHub Release     │
            │    digest + rollback  │
            └───────────────────────┘

  Every Monday (rescan.yml):
  Re-scan all GHCR releases → open GitHub Issue if new findings
```

---

## 4. Repository Structure

```
.
├── policy/
│   ├── image-ingestion-policy.yml     # Allowlist, tag pattern, vendor signature mode
│   ├── vulnerability-gate-policy.yml  # CVE/KEV block rules, exception process, re-scan policy
│   ├── runtime-hardening-policy.yml   # CIS Docker Benchmark v1.6.0 compliance table (Section 5)
│   └── cis-docker-hardening.md        # Human-readable reference for all CIS checks performed
│
├── .github/workflows/
│   ├── ci.yml                    # Pre-merge: IaC & secret scan + CIS compliance check (blocks on findings)
│   ├── image-promotion.yml       # Vendor image ingestion, scanning, attestation, and promotion
│   └── rescan.yml                # Scheduled weekly re-scan of all promoted images
│
└── iac/n8n/
    ├── docker-compose.yml        # CIS-hardened container stack (read-only FS, no-root, AppArmor, resource limits)
    ├── .env.template             # Environment template — copy to .env and populate
    └── install.sh                # Interactive setup: version selection, digest fetch, provenance verify, deploy
```

---

## 5. Operational Playbooks

### 5a. Promotion Runbook

1. Go to **Actions → Image Promotion (Trusted Source) → Run workflow**
2. Enter a version (e.g. `1.55.3`) or leave blank to auto-resolve latest
3. The pipeline runs: policy check → cosign → digest pin → Trivy → KEV
4. **If clean**: promotes automatically → creates GitHub Release with digest and rollback info
5. **If CRITICAL/HIGH or KEV match**: pipeline pauses for approval
   - Download the `scan-report-<version>` artifact from the run summary
   - Review `trivy-summary.txt` and `vendor-sig-check.txt`
   - Go to **Review deployments** → Approve (accept risk) or Reject
   - Approved images are promoted with a `⚠️ Manually Approved` release label

### 5b. Exception / Waiver Process

When approving a vulnerable image:
1. Download and retain the `scan-report-<version>` artifact as evidence
2. Document the accepted risk (CVE IDs, severity, KEV status, business justification) in the GitHub Release notes
3. Set a **review deadline** — a date by which either a patched version must be deployed or the exception formally renewed
4. Update `policy/vulnerability-gate-policy.yml` comments if the exception changes policy intent

### 5c. Rollback Procedure

Every GitHub Release contains the exact digest-pinned reference for that version.

```bash
# On the host VM — edit .env with values from the target GitHub Release
nano iac/n8n/.env

# Set:
N8N_IMAGE_VERSION=<previous-version>      # e.g. 1.54.0
N8N_IMAGE_DIGEST=sha256:<digest-from-release>

# Apply
docker compose up -d
```

Or re-run `install.sh` and enter the target version when prompted.

### 5d. Re-Scan and Patch Cadence

| Trigger | Action |
|---------|--------|
| Weekly Monday 00:00 UTC (automated) | `rescan.yml` re-scans all promoted GHCR images + KEV; opens GitHub Issue if findings change |
| GitHub Issue opened by re-scan | Review findings; promote a newer clean version or document exception |
| CISA KEV catalogue updated with a new CVE matching a deployed version | Issue opened automatically on next Monday; treat as P1 — promote or rollback within SLA |
| New n8n release published by vendor | Run the promotion pipeline manually for the new version |

---

## 6. One-Time GitHub Setup

1. **Settings → Environments → New environment** → name it `trusted-promotion`
2. Enable **Required reviewers**, add yourself
3. **Settings → Actions → General → Workflow permissions** → **Read and write permissions**
4. **Packages → `n8n-trusted` → Package Settings → Change visibility → Public**
   (required for OCI attestation push; the repository itself is not affected)

---

## 7. Deploying to a Host

```bash
# Clone on the VM
git clone https://github.com/svveec0d3/secure-deploy.git
cd secure-deploy/iac/n8n

# Install GitHub CLI for provenance verification (strongly recommended)
# https://github.com/cli/cli#installation
gh auth login

# Run the interactive setup script
chmod +x install.sh
./install.sh
# Prompts: Host IP, version, memory/cpu/pids limits, provenance verification
```

The script will:
- Detect your host IP
- Let you choose version (or auto-resolve latest)
- Prompt for container resource limits with safe defaults
- Fetch the image digest from the GitHub Release
- Verify provenance against the **exact digest** before deploying
- Write all values to `.env` and start the container

**Automation mode** (CI/CD, no prompts):
```bash
./install.sh --skip-verify
```

---

## 8. Security Policy

- Images **must** originate from `ghcr.io/svveec0d3/secure-deploy/*` — never pulled directly from Docker Hub on production hosts
- All production images must have a corresponding [GitHub Release](https://github.com/svveec0d3/secure-deploy/releases) with attested SLSA provenance and SBOM
- Image ingestion policy: [`policy/image-ingestion-policy.yml`](policy/image-ingestion-policy.yml) — allowlist and vendor signature rules
- Vulnerability gate policy: [`policy/vulnerability-gate-policy.yml`](policy/vulnerability-gate-policy.yml) — CVE/KEV block conditions and exception process
- Runtime hardening policy: [`policy/runtime-hardening-policy.yml`](policy/runtime-hardening-policy.yml) — CIS Docker Benchmark v1.6.0 compliance
- All policy changes require a reviewed PR
