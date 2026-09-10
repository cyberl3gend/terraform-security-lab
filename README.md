# DevSecOps IaC Security Pipeline

Misconfigured cloud infrastructure is the leading cause of data breaches — exposed S3 buckets, overly permissive security groups, and unencrypted storage are all misconfigurations that slipped past a human reviewer. This project solves that by making security automatic. Every infrastructure change goes through a 5-stage security gate before it can merge to main. If anything fails, the merge is blocked — no manual override, no exceptions.

The pipeline runs three independent security engines against the Terraform code on every pull request, uploads results to GitHub Security for a unified dashboard, and enforces CIS AWS Foundations Benchmark compliance as a hard gate.

---

## How It Works

```text
[ Developer opens a Pull Request ]
           │
           ▼
[ GitHub Actions — 5-Stage Security Gate ]
           │
           ├── Stage 1 · terraform fmt + validate
           ├── Stage 2 · tfsec  (CIS AWS Foundations Benchmark)
           ├── Stage 3 · Checkov  (built-in + custom YAML policies)
           └── Stage 4 · OPA conftest  (Rego — evaluated against plan JSON)
                      │
                      ├── s3_encryption.rego
                      ├── sg_no_public_ingress.rego
                      └── iam_no_wildcard.rego
           │
           ▼
[ Stage 5 · Summary Gate — all 4 must pass ]
           │
           ▼
[ Safe to Merge → main ]
```

tfsec and Checkov results are uploaded as SARIF reports to **GitHub Security → Code Scanning** after every run, whether passing or failing, so you get a single dashboard showing infrastructure vulnerabilities across every scan.

---

## What This Pipeline Blocks

Each security control maps to a real attack scenario. This isn't compliance for its own sake — these checks exist because each one represents something that has caused a real breach.

| Control | Attack It Prevents |
|---|---|
| Default SG override (no rules) | If a resource is accidentally assigned the default security group, it can communicate freely within the VPC. Clearing it makes that a dead end instead of a lateral movement path. |
| VPC flow logs enabled | Without flow logs, an attacker can exfiltrate data and you have no record of the traffic. Flow logs give you forensic evidence after an incident. |
| KMS encryption on log groups | Unencrypted logs sitting in CloudWatch can be read by anyone with broad IAM access. A customer-managed KMS key means you control who can decrypt them. |
| SSH blocked from 0.0.0.0/0 | Open SSH to the public internet is the most common entry point for brute-force and credential stuffing attacks. |
| No wildcard IAM actions | A role with `Action: "*"` can do anything in your AWS account — create users, delete infrastructure, exfiltrate data. Scoped actions limit blast radius if credentials are compromised. |
| S3 HTTPS-only policy | Without this, data in transit can be intercepted. The bucket policy denies any request that isn't over TLS. |
| S3 public access block | Prevents anyone from accidentally making a bucket or object public, even if they try to override it with an ACL or bucket policy. |
| 365-day log retention | CIS requires a full year of logs so you can investigate incidents that happened months ago. 30 or 90 days isn't enough for a serious forensic investigation. |

---

## File Structure

```text
terraform-security-lab/
├── .github/
│   └── workflows/
│       └── devsecops-ci.yml          ← 5-stage CI pipeline definition
├── policies/
│   ├── checkov/
│   │   ├── CKV_CUSTOM_1.yaml         ← Block SSH (22) open to 0.0.0.0/0
│   │   └── CKV_CUSTOM_2.yaml         ← Block S3 buckets with no SSE resource
│   └── rego/
│       ├── s3_encryption.rego        ← OPA: deny unencrypted/SSE-S3 buckets
│       ├── sg_no_public_ingress.rego ← OPA: deny SSH/RDP/HTTP from 0.0.0.0/0
│       └── iam_no_wildcard.rego      ← OPA: deny wildcard actions/resources
├── terraform/
│   ├── modules/
│   │   ├── vpc/                      ← VPC, flow logs, NAT gateway, default SG
│   │   ├── iam/                      ← Least-privilege EC2 role + scoped policies
│   │   └── monitoring/               ← CloudWatch alarms (CIS 3.1/3.3/3.10/3.12/3.14)
│   ├── environments/
│   │   ├── dev.tfvars
│   │   ├── staging.tfvars
│   │   └── prod.tfvars
│   ├── main.tf                       ← Root module — S3, KMS, security group
│   ├── variables.tf
│   └── outputs.tf
├── .checkov.yaml                     ← Checkov scanner configuration
├── .tfsec.yaml                       ← tfsec severity overrides
└── README.md
```

---

## Security Controls

### VPC & Network Security (CIS AWS 3.9, 4.3)

When I first ran the pipeline, Checkov flagged two violations in the VPC module: the default security group still had open rules, and VPC flow logs weren't enabled.

The default security group is something AWS creates automatically and most people ignore. The problem is if a resource accidentally gets assigned to it, it can communicate freely within the VPC. I overrode it explicitly with no ingress or egress rules so it becomes a dead end.

For flow logs, I provisioned the full stack: a CloudWatch log group to store the traffic data, an IAM role that grants the VPC flow logs service permission to write there, and the flow log resource itself wiring everything together. I then added a customer-managed KMS key to encrypt the log group at rest and set retention to 365 days. The IAM policy is scoped to that log group's ARN specifically — not a wildcard.

- Default security group overridden with zero rules (CIS AWS 4.3)
- VPC flow logs enabled, capturing ALL traffic (CIS AWS 3.9)
- CloudWatch log group encrypted with a customer-managed KMS key (CKV_AWS_158)
- Log retention set to 365 days minimum (CKV_AWS_338)
- IAM role policy scoped to the specific log group ARN — not `"*"` (CKV_AWS_355)

### S3 Encryption (CIS AWS 2.1.1, 2.1.2)

Every S3 bucket uses SSE-KMS with a customer-managed key, bucket key enabled to reduce KMS API costs, and automatic key rotation. A bucket policy denies all non-HTTPS requests at the policy level, and versioning is enabled for a full audit trail.

- SSE-KMS encryption with customer-managed key
- `bucket_key_enabled = true` — reduces KMS API call costs significantly at scale
- `enable_key_rotation = true` — key automatically rotates annually
- Bucket policy denying all HTTP access
- Versioning enabled

### IAM Least Privilege (CIS AWS 1.x)

Every policy is scoped to exact actions and specific resource ARNs — no wildcards anywhere. The EC2 role has four separate policies, each covering exactly one function:

| Policy | Allowed Actions | Resource Scope |
|---|---|---|
| `s3-read-policy` | GetObject, ListBucket | Specific bucket ARN |
| `cwlogs-write-policy` | CreateLogStream, PutLogEvents | Specific log group ARN |
| `ssm-read-policy` | GetParameter, GetParametersByPath | `/project/env/*` path |
| `kms-decrypt-policy` | Decrypt, GenerateDataKey | Specific KMS key ARN |

The account password policy enforces CIS 1.x: 16-character minimum, complexity requirements, 90-day rotation, and 24-password history.

### Security Groups (CIS AWS 4.1, 4.2)

- HTTPS (443) is the only public ingress — no port 80, no RDP, no unrestricted SSH
- SSH (22) is locked to a management CIDR variable; Terraform validates that it can never be `0.0.0.0/0`
- The custom Checkov policy `CKV_CUSTOM_1` enforces the SSH restriction at the policy scan level as well
- Outbound is HTTPS-only (least-privilege egress)

### CloudWatch Alarms (CIS AWS 3.x)

Five alarms are wired to an SNS topic and fire on the following events:

| Alarm | CIS Control | What It Catches |
|---|---|---|
| Unauthorized API Calls | 3.1 | Any `AccessDenied` or `UnauthorizedAccess` event |
| Root Account Usage | 3.3 | Any non-service root account activity |
| Security Group Changes | 3.10 | Create, modify, or delete SG rules |
| Network ACL Changes | 3.12 | Any NACL modification |
| VPC Changes | 3.14 | VPC create, delete, or modification |

---

## CIS Benchmark Coverage

| CIS Control | Description | Enforced By |
|---|---|---|
| 1.x | IAM password policy | `aws_iam_account_password_policy` |
| 2.1.1 | S3 server-side encryption | Checkov `CKV_AWS_19`, custom `CKV_CUSTOM_2` |
| 2.1.2 | S3 deny non-HTTPS requests | Checkov `CKV_AWS_20` |
| 3.1 | Unauthorized API call alarm | CloudWatch alarm |
| 3.3 | Root account usage alarm | CloudWatch alarm |
| 3.9 | VPC flow logs enabled | `aws_flow_log` resource |
| 3.10 | Security group change alarm | CloudWatch alarm |
| 3.12 | Network ACL change alarm | CloudWatch alarm |
| 3.14 | VPC change alarm | CloudWatch alarm |
| 4.1 | SSH not open to 0.0.0.0/0 | tfsec, Checkov `CKV_CUSTOM_1`, OPA Rego |
| 4.2 | RDP not open to 0.0.0.0/0 | tfsec, OPA Rego |
| 4.3 | Default SG restricts all traffic | `aws_default_security_group` override |

---

## Policy Engines

### Checkov

Static analysis on Terraform source code, running CIS benchmark checks plus two custom YAML policies:

- `CKV_CUSTOM_1` — blocks any security group that opens port 22 to `0.0.0.0/0`
- `CKV_CUSTOM_2` — blocks any S3 bucket with no `aws_s3_bucket_server_side_encryption_configuration`

```bash
pip install checkov
checkov --config-file .checkov.yaml
```

### tfsec

CIS benchmark scanning with severity overrides in `.tfsec.yaml` that escalate S3 encryption, public SG access, and IAM wildcard checks to `ERROR` so they hard-fail the pipeline rather than warn.

```bash
brew install tfsec
tfsec terraform/ --config-file .tfsec.yaml
```

### OPA / conftest

Rego policies run against the Terraform **plan JSON** — not the source code. This catches misconfigurations that only appear at runtime, like a dynamic CIDR value that evaluates to `0.0.0.0/0` at plan time but looks fine in source.

```bash
# Install conftest
brew install conftest

# Generate plan JSON
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform plan -var-file="environments/dev.tfvars" -out=tfplan.binary
terraform -chdir=terraform show -json tfplan.binary > tfplan.json

# Run Rego policies
conftest test --policy policies/rego/ --all-namespaces tfplan.json
```

---

## Multi-Environment Setup

Each environment has its own `.tfvars` file with isolated CIDR ranges and configuration:

| Environment | VPC CIDR | Availability Zones | SNS Alarms |
|---|---|---|---|
| `dev` | `10.0.0.0/16` | 2 | Optional |
| `staging` | `10.1.0.0/16` | 2 | Required |
| `prod` | `10.2.0.0/16` | 3 | Required |

```bash
# Plan against a specific environment
terraform -chdir=terraform plan -var-file="environments/staging.tfvars"

# Apply (requires real AWS credentials)
terraform -chdir=terraform apply -var-file="environments/prod.tfvars"
```

---

## Pipeline Flow

Stages 2, 3, and 4 run in parallel after Stage 1 passes. Stage 5 evaluates all results and fails the workflow if any job didn't succeed — the PR cannot merge until everything is green.

```
Stage 1: Format + Validate  ──────────────────────────────────┐
Stage 2: tfsec              ── (after Stage 1) ────────────────┤
Stage 3: Checkov            ── (after Stage 1) ────────────────┤→ Stage 5: Gate
Stage 4: OPA conftest       ── (after Stage 1) ────────────────┘
```

---

## Known Limitations

This pipeline covers static analysis and plan-level policy enforcement. It does not cover:

- **Runtime security** — GuardDuty threat detection, Security Hub findings, or runtime anomaly detection are outside scope
- **Secrets scanning** — hardcoded credentials in source code are not detected (use a dedicated tool like truffleHog or GitHub secret scanning)
- **Container image scanning** — if workloads run in containers, image-level vulnerabilities (CVEs in base images) are not checked here
- **Drift detection** — the pipeline only runs on code changes; it does not detect if infrastructure is manually changed outside of Terraform
- **Multi-account** — this setup assumes a single AWS account; a full enterprise implementation would add AWS Organizations and Service Control Policies

---

## Skills Demonstrated

Terraform module design, multi-engine security scanning, CIS AWS Foundations Benchmark enforcement, KMS encryption, IAM least-privilege design, OPA Rego policy authoring, and CI/CD security gating — relevant to Platform Engineer, Cloud Security, and DevOps roles.