# S3 Cross-Region Replication (CRR) Static Website

A fully automated infrastructure-as-code (Bash) setup for deploying a multi-region static website on Amazon S3. This project provisions a primary public bucket in `us-east-1` (N. Virginia) and automatically replicates assets to a secondary failover bucket in `us-east-2` (Ohio) using S3 Cross-Region Replication (CRR).

---

## Architecture Overview

```
                          ┌───────────────────────────┐
                          │   Local Machine (Git Bash)│
                          └─────────────┬─────────────┘
                                        │ (aws s3 cp)
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ AWS Cloud                                                                    │
│                                                                              │
│   ┌─────────────────────────────────┐   CRR    ┌──────────────────────────┐  │
│   │  Source S3 Bucket (us-east-1)   ├─────────►│ Dest S3 Bucket (us-east-2)│  │
│   ├─────────────────────────────────┤          ├──────────────────────────┤  │
│   │ • Versioning: Enabled           │          │ • Versioning: Enabled    │  │
│   │ • Static Hosting: Active        │          │ • Static Hosting: Active │  │
│   │ • Public Read Bucket Policy     │          │ • Public Read Bucket Policy│  │
│   └─────────────────────────────────┘          └──────────────────────────┘  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

```

* **Source Region (`us-east-1`):** Primary hosting bucket accepting site updates.
* **Destination Region (`us-east-2`):** Passive replica bucket automatically updated via S3 CRR.
* **IAM Replication Role:** AssumeRole-enabled identity granting S3 permissions to read from the source and write to the replica.
* **Dynamic Client Routing:** Embedded JavaScript in `index.html` detects `window.location.hostname` to display active region metadata automatically.

---

## Repository Structure

```text
s3-crr-staticwebsite/
├── infrastructure/     # Architecture diagrams & AWS IAM policies
├── scripts/
│   ├── setup.sh        # Main end-to-end deployment script
│   └── update.sh       # Rapid asset re-upload script
├── website/
│   └── index.html      # Static site entry point with region auto-detection
└── README.md           # Project documentation

```

---

## Prerequisites

Before running the deployment scripts, ensure your environment is configured with:

1. **AWS CLI v2** installed and configured (`aws configure` with valid credentials).
2. **Git Bash** (or a Unix-compatible terminal environment on Linux/macOS).
3. **IAM Permissions** to manage S3 Buckets and IAM Roles (`s3:*`, `iam:*`, `sts:*`).

---

## Step-by-Step Setup

### 1. Clone the Repository & Verify Directory Structure

```bash
git clone 
cd s3-crr-staticwebsite

```

### 2. Make Scripts Executable

```bash
chmod +x scripts/setup.sh scripts/update.sh

```

### 3. Deploy the Infrastructure & Site

Run the complete automated setup script:

```bash
./scripts/setup.sh

```

**What `setup.sh` performs:**

1. Resolves absolute paths dynamically relative to script location.
2. Fetches the active AWS Account ID via `sts get-caller-identity`.
3. Provisions source (`us-east-1`) and destination (`us-east-2`) S3 buckets.
4. Enables object versioning and disables S3 Block Public Access on both buckets.
5. Configures Static Website Hosting endpoints (`--website-configuration`).
6. Attaches public-read bucket policies (`s3:GetObject`).
7. Configures the IAM Role (`s3-crr-replication-role-9988`) and attaches replication permissions.
8. Configures S3 CRR rules on the source bucket.
9. Uploads `website/index.html` to the source bucket and polls the destination bucket until replication completes.

---



## Endpoint Verification

Once `setup.sh` finishes execution, the public static website endpoints will be formatted as follows:

* **Primary Endpoint (`us-east-1`):**
`http://crr-site-source--9988.s3-website-us-east-1.amazonaws.com`
* **Replica Endpoint (`us-east-2`):**
`http://crr-site-dest--9988.s3-website-us-east-2.amazonaws.com`



