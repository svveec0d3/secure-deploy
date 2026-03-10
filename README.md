# Secure Deploy

[![CI](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/ci.yml)
[![Image Promotion](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/image-promotion.yml)
[![Re-Scan](https://github.com/svveec0d3/secure-deploy/actions/workflows/rescan.yml/badge.svg)](https://github.com/svveec0d3/secure-deploy/actions/workflows/rescan.yml)

Secure Deploy is a reference pipeline for securely ingesting, reviewing, promoting, and deploying vendor container images. This repository uses `n8nio/n8n` as the working example, but the pattern is meant to show how to combine policy, attestation, vulnerability context, and operational controls into a practical GitHub Actions workflow.

The pipeline is built around a simple principle: do not treat a container tag as trustworthy just because it exists. Resolve the exact digest, scan it, enrich the findings with additional risk signals, decide whether the image is auto-eligible or needs human approval, then publish a promoted image with an auditable release record.

## What This Repository Does

- Pulls vendor images only from an allowlisted source.
- Resolves and pins the immutable image digest before promotion.
- Scans the image with Trivy and enriches findings with KEV, EPSS, and CVE age.
- Captures Tracee runtime reachability data during a smoke run and reports it in vulnerability summaries.
- Uses an approval gate only when `CRITICAL` or `HIGH` findings meet this repository's manual-review criteria.
- Attests promoted images and publishes GitHub Releases with rollback details.
- Re-scans only the latest promoted release on a schedule.
- Keeps only the latest 3 promoted GitHub releases.

## Why This Exists

Typical operational risks for vendor container images:

| Risk | Why it matters | Control in this repo |
| :--- | :--- | :--- |
| Mutable tags | `latest` can change silently. | Digest pinning and semver-only tag policy |
| Weak provenance | You may not know who really produced the image. | Allowlist, cosign verification when available, attestations |
| Incomplete review | Severity alone does not reflect exploitability. | KEV, EPSS, and CVE age enrichment |
| Delayed exposure | An already-promoted image can become riskier later. | Scheduled re-scan of the latest promoted release |
| Weak audit trail | Teams need to know what was approved and why. | GitHub Releases, artifacts, job summaries |
| Unsafe runtime defaults | A good image can still run with bad container settings. | CIS-oriented runtime hardening in `iac/n8n` |

## Approval Gate Logic

The promotion gate is intentionally risk-based, not severity-only.

### What Is a CVE?

`CVE` stands for Common Vulnerabilities and Exposures. A CVE identifier such as `CVE-2026-12345` is a public reference for a known security flaw. By itself, a CVE tells you that a vulnerability exists, but it does not fully answer:

- whether the flaw is being actively exploited
- how likely exploitation is in the near term
- whether the vulnerable code path is actually exercised in your workload
- whether the issue is new and still inside a short patching window, or old and lingering

That is why this repository does not gate promotion on CVE severity alone.

### Why Additional Risk Signals Are Used

The approval gate combines several parameters because each one answers a different risk question.

| Signal | Question it answers | Why it matters for approval |
| :--- | :--- | :--- |
| CVSS / severity from Trivy | How bad could the flaw be if exploited? | Provides base prioritization |
| KEV | Is this CVE already known to be exploited in the wild? | Strong real-world urgency signal |
| EPSS | How likely is exploitation in the next 30 days? | Helps separate theoretical from likely exploitation |
| CVE age | Has the issue remained open long enough that it should no longer be treated as a fresh exception? | Prevents indefinite deferral |
| Reachability | Did the smoke run observe runtime evidence tied to the vulnerable package files? | Useful context, but not trusted enough yet for gating |

### Current Gate Policy

For `CRITICAL` and `HIGH` findings:

- Auto-promotion is allowed when the CVE is under 30 days old, not in KEV, and below this repository's manual-review EPSS threshold.
- Manual approval is required when the CVE is at least 30 days old, in KEV, or falls into this repository's `HIGH` or `CRITICAL` EPSS policy band.

`MEDIUM`, `LOW`, and `UNKNOWN` findings are still recorded and reported, but they do not directly trigger manual approval in the current policy.

## EPSS Policy Cheat Sheet

EPSS is the FIRST Exploit Prediction Scoring System. It estimates the probability that a CVE will be exploited in the next 30 days.

Example: an EPSS score of `2.1%` means an estimated `2.1%` probability of exploitation in the next 30 days. In this repository, that is above the `2.0%` manual-review threshold for `CRITICAL` and `HIGH` findings.

The table below is repository policy, not an official EPSS standard.

| EPSS score | Repository policy band | Meaning | Action |
| :--- | :--- | :--- | :--- |
| `< 0.5%` | Low | Exploitation currently looks unlikely at scale. | Does not block auto-promotion by itself |
| `0.5% to < 2.0%` | Medium | Elevated likelihood, but below manual-review threshold. | Review normally; may still auto-promote |
| `2.0% to < 10.0%` | High | Above this repository's manual-review threshold. | Manual review for `CRITICAL` and `HIGH` findings |
| `>= 10.0%` | Critical | Very high predicted exploitation likelihood. | Treat as urgent; manual review for `CRITICAL` and `HIGH` findings |

## Reachability Status

Tracee reachability data is collected and shown in the vulnerability summaries as `Reachability = Yes/No`.

Current position:

- Reachability is useful analyst context.
- Reachability is not currently used as an approval-gate parameter.

TODO:
- Verify that the current Tracee reachability method is reliable enough for policy decisions across the supported image/runtime combinations.
- Until that verification is complete, keep reachability out of the approval gate.

## Pipeline Flow

```mermaid
flowchart LR
    subgraph Intake["Intake"]
        A["Manual dispatch or weekly version check"]
        B["Allowlist + semver policy"]
        C["Resolve exact vendor digest"]
    end

    subgraph Analysis["Analysis"]
        D["Trivy image scan"]
        E["Tracee smoke run"]
        F["KEV + EPSS + CVE age enrichment"]
    end

    subgraph Decision["Decision"]
        G{"Approval gate"}
        H["Auto promotion"]
        I["Manual approval in trusted-promotion"]
    end

    subgraph Publish["Publish and monitor"]
        J["Push trusted image to GHCR"]
        K["Attest provenance and SBOM"]
        L["Create GitHub Release with rollback data"]
        M["Prune releases to latest 3"]
        N["Weekly re-scan of latest promoted release"]
    end

    A --> B --> C --> D
    C --> E
    D --> F
    E --> F
    F --> G
    G -->|Auto-eligible| H --> J
    G -->|Manual review required| I --> J
    J --> K --> L --> M --> N
```

### Workflow Summary

- `weekly-version-check.yml`
  - Checks whether a newer upstream `n8n` version exists.
  - Triggers promotion only when upstream is newer than the latest promoted release.

- `image-promotion.yml`
  - Pulls the selected upstream image.
  - Pins by digest.
  - Scans and enriches vulnerabilities.
  - Decides between auto-promotion and manual approval.
  - Publishes the trusted image and release record.
  - Prunes old releases, keeping the latest 3.

- `rescan.yml`
  - Re-scans only the latest promoted release.
  - Opens an issue if the latest promoted release now requires manual review under the current policy.

- `ci.yml`
  - Validates repository security checks and the Tracee integration path.

## Repository Structure

```text
.
├── .github/workflows/
│   ├── ci.yml
│   ├── image-promotion.yml
│   ├── rescan.yml
│   └── weekly-version-check.yml
├── .github/scripts/
│   ├── enrich_findings.py
│   ├── generate_summary.py
│   ├── merge_tracee_reachability.py
│   ├── collect_package_files.sh
│   └── run_tracee_reachability.sh
├── policy/
│   ├── image-ingestion-policy.yml
│   ├── runtime-hardening-policy.yml
│   └── vulnerability-gate-policy.yml
└── iac/n8n/
    ├── docker-compose.yml
    ├── install.sh
    ├── upgrade.sh
    └── .env.template
```

## Operating Model

### Promotion

1. Run `Image Promotion (Trusted Source)` manually, or let the weekly version check dispatch it when a newer upstream version exists.
2. The workflow resolves the exact digest and scans the image.
3. Findings are enriched with KEV, EPSS, CVE age, and reachability context.
4. The workflow either:
   - auto-promotes, or
   - pauses for review in the `trusted-promotion` environment.
5. On success, the trusted image is pushed to GHCR, attested, released, and old releases are pruned down to the newest 3.

### Re-Scan

- Schedule: every Monday at `00:00 UTC`
- Scope: latest promoted release only
- Outcome:
  - no action if still acceptable under current policy
  - GitHub issue if the latest promoted release now requires manual review

### Release Retention

- Keep the latest 3 promoted GitHub releases.
- Intended retention model:
  - latest active release
  - previous release
  - one extra rollback candidate

## Security Controls Summary

| Control | Purpose |
| :--- | :--- |
| Source allowlist | Restrict ingestion to expected vendor image source |
| Semver-only tags | Block moving targets such as mutable tags |
| Digest pinning | Ensure the scanned image is the promoted image |
| Trivy scanning | Discover package vulnerabilities across severities |
| KEV enrichment | Flag actively exploited CVEs |
| EPSS enrichment | Add near-term exploitation probability |
| CVE age tracking | Distinguish fresh issues from stale exposure |
| Tracee reachability reporting | Provide runtime context for analyst review |
| SBOM attestation | Preserve software inventory and downstream evidence |
| Provenance attestation | Provide origin and build integrity evidence |
| GitHub Releases | Preserve rollback details and approval history |

## One-Time GitHub Setup

1. Create the `trusted-promotion` environment and add required reviewers.
2. Set Actions workflow permissions to `Read and write`.
3. Ensure the `n8n-trusted` package visibility matches your intended deployment model.

## Deploying to a Host

```bash
git clone https://github.com/svveec0d3/secure-deploy.git
cd secure-deploy/iac/n8n
chmod +x install.sh
./install.sh
```

`install.sh` supports:

- selecting a target version or latest promoted release
- provenance verification with `gh attestation verify`
- runtime resource limits
- deployment and rollback support
- optional auto-upgrade via `upgrade.sh`

## References

- [SLSA v1.0](https://slsa.dev/spec/v1.0)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [NIST SP 800-53 Rev. 5](https://csrc.nist.gov/publications/sp800-53/rev-5)
- [CISA KEV](https://www.cisa.gov/known-exploited-vulnerabilities-catalog)
- [FIRST EPSS](https://www.first.org/epss/)

This README is policy-adjacent documentation. If the workflow behavior changes, keep this file aligned with the actual workflow logic.
