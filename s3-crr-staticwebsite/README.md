# S3 Cross-Region Replication (CRR) Static Website

Automated, Bash-based infrastructure setup for a multi-region static website on Amazon S3. The project provisions a public primary bucket in `us-east-1` (N. Virginia) and uses S3 Cross-Region Replication (CRR) to keep a failover bucket in `us-east-2` (Ohio) in sync.

![AWS](https://img.shields.io/badge/AWS-S3-orange) ![Shell](https://img.shields.io/badge/Bash-scripts-green) ![Regions](https://img.shields.io/badge/regions-us--east--1%20%E2%86%92%20us--east--2-blue)

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [What `setup.sh` Does](#what-setupsh-does)
- [Updating the Website](#updating-the-website)
- [Verifying the Deployment](#verifying-the-deployment)
- [Cleanup](#cleanup)
- [Security Notes](#security-notes)
- [Troubleshooting](#troubleshooting)

---

## Features

- **One-command deployment** of buckets, hosting, policies, IAM role, and replication.
- **Automatic failover copy** of site content in a second region via CRR.
- **Region auto-detection:** `index.html` reads `window.location.hostname` and displays which region is serving the page.
- **Portable scripts:** paths are resolved relative to the script location, so they run from anywhere.

---

## Architecture

```text
                ┌─────────────────────────────┐
                │  Local Machine (Git Bash)   │
                └──────────────┬──────────────┘
                               │  aws s3 cp
                               ▼
┌───────────────────────────────────────────────────────────────┐
│ AWS Cloud                                                     │
│                                                               │
│  ┌──────────────────────────┐  CRR  ┌──────────────────────┐  │
│  │ Source Bucket            ├──────►│ Destination Bucket   │  │
│  │ us-east-1                │       │ us-east-2            │  │
│  ├──────────────────────────┤       ├──────────────────────┤  │
│  │ • Versioning: Enabled    │       │ • Versioning: Enabled│  │
│  │ • Static Hosting: Active │       │ • Static Hosting: On │  │
│  │ • Public Read Policy     │       │ • Public Read Policy │  │
│  └──────────────────────────┘       └──────────────────────┘  │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

| Component | Role |
|---|---|
| **Source bucket** (`us-east-1`) | Primary hosting bucket; receives all site updates. |
| **Destination bucket** (`us-east-2`) | Passive replica kept current by CRR. |
| **IAM replication role** | `s3-crr-replication-role-9988`: lets S3 read from the source and write to the replica. |
| **`index.html`** | Detects the serving hostname and shows the active region. |

---

## Repository Structure

```text
s3-crr-staticwebsite/
├── infrastructure/     # Architecture diagrams & AWS IAM policies
├── scripts/
│   ├── setup.sh        # End-to-end deployment
│   └── update.sh       # Fast asset re-upload
├── website/
│   └── index.html      # Static site entry point
└── README.md
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **AWS CLI v2** | Configured via `aws configure` with valid credentials. |
| **Shell** | Git Bash (Windows) or any Unix-compatible terminal (Linux/macOS). |
| **IAM permissions** | Ability to manage S3 buckets and IAM roles (`s3:*`, `iam:*`, `sts:*`). |

Check your setup:

```bash
aws --version
aws sts get-caller-identity
```

---

## Quick Start

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd s3-crr-staticwebsite

# 2. Make the scripts executable
chmod +x scripts/setup.sh scripts/update.sh

# 3. Deploy everything
./scripts/setup.sh
```

---

## What `setup.sh` Does

1. Resolves absolute paths relative to the script location.
2. Fetches your AWS Account ID via `sts get-caller-identity`.
3. Creates the source (`us-east-1`) and destination (`us-east-2`) buckets.
4. Enables versioning and disables S3 Block Public Access on both buckets.
5. Configures static website hosting (`--website-configuration`).
6. Attaches public-read bucket policies (`s3:GetObject`).
7. Creates the IAM role `s3-crr-replication-role-9988` and attaches replication permissions.
8. Applies the CRR rule on the source bucket.
9. Uploads `website/index.html` to the source bucket and polls the destination until replication completes.

---

## Updating the Website

After editing files in `website/`, re-upload them with:

```bash
./scripts/update.sh
```

CRR replicates the changes to the destination bucket automatically.

---

## Verifying the Deployment

Bucket names follow the pattern `crr-site-<role>-<ACCOUNT_ID>-9988`. Replace `<ACCOUNT_ID>` with your 12-digit AWS account ID.

| Region | Website endpoint (HTTP) | Direct object URL (HTTPS) |
|---|---|---|
| **Primary** (`us-east-1`) | `http://crr-site-source-<ACCOUNT_ID>-9988.s3-website-us-east-1.amazonaws.com` | `https://crr-site-source-<ACCOUNT_ID>-9988.s3.us-east-1.amazonaws.com/index.html` |
| **Replica** (`us-east-2`) | `http://crr-site-dest-<ACCOUNT_ID>-9988.s3-website-us-east-2.amazonaws.com` | `https://crr-site-dest-<ACCOUNT_ID>-9988.s3.us-east-2.amazonaws.com/index.html` |

> The website endpoints are HTTP-only. HTTPS requires putting CloudFront in front of the buckets.

To confirm replication from the CLI:

```bash
aws s3 ls s3://crr-site-dest-<ACCOUNT_ID>-9988/ --region us-east-2
```

---

## Cleanup

Versioned buckets must be fully emptied (including all versions and delete markers) before deletion. To avoid ongoing charges, remove:

1. All objects and versions from both buckets.
2. Both buckets.
3. The IAM role `s3-crr-replication-role-9988` and its attached policy.

---

## Security Notes

- Both buckets are **intentionally public-read** to serve the website. Never upload sensitive files to them.
- Scope IAM permissions down from `s3:*` / `iam:*` to only what you need once deployment is done.
- Consider CloudFront with Origin Access Control for production use (HTTPS, caching, private buckets).

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `AccessDenied` when opening the site | Block Public Access still enabled, or bucket policy missing. |
| Replica bucket stays empty | Versioning not enabled on both buckets, or the IAM role lacks permissions. Note CRR only replicates objects uploaded **after** the rule exists. |
| `BucketAlreadyExists` | Bucket names are global; change the suffix (`9988`) in the script. |
| Script fails on Windows | Run from Git Bash, not CMD or PowerShell. |
