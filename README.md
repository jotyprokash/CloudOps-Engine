# CloudOps Engine

Small Bash toolkit for AWS domain cleanup: scan first, label from evidence, write the cutover notes, and keep the actual changes in your normal change process.

It does not modify AWS.

## Safety Model

- Read-only by default.
- No AWS create, update, delete, or revoke APIs.
- No automatic DNS deletion.
- No hardcoded company names, domains, secrets, IPs, or AWS account IDs.
- Real inventory data and artifacts are gitignored by default.
- Unknown resources remain blocked until reviewed.
- New DNS records should be created before cutover.

## What It Reads

- Route53 hosted zones and records.
- ACM certificates.
- EC2 instances.
- Application and Network Load Balancers.
- Target Groups.
- Security Groups.
- Elastic IPs.
- Optional ECS and EKS cluster detection.

## Layout

```text
CloudOps Engine/
  inventory/
    json/       # Raw AWS JSON exports, gitignored
    csv/        # CSV exports, gitignored
    summary/    # TSV summaries used by Bash, gitignored
  bin/
  nginx/snippets/
  settings/
  docs/
  artifacts/
    nginx/      # Nginx files, gitignored
    plans/      # Cutover notes and mappings, gitignored
    validation/ # Check inputs and outputs, gitignored
```

## Quick Start

```bash
cd "CloudOps Engine"
cp settings/settings.env.example settings/settings.env
chmod +x bin/*.sh
bin/full-pass.sh
```

For a single-region run, set `AWS_REGION` or `AWS_DEFAULT_REGION`. For multi-region discovery, set:

```bash
DISCOVERY_REGION_MODE=all
```

or provide an explicit list:

```bash
DISCOVERY_REGIONS=us-east-1,us-west-2
```

## Files Written

The AWS scan writes:

- `inventory/json/*.json`
- `inventory/csv/*.csv`
- `inventory/summary/*.tsv`

The mapping pass writes:

- `artifacts/plans/labeled-resources.md`
- `artifacts/plans/domain-mapping.md`
- `artifacts/plans/migration-plan.md`
- `artifacts/plans/validation-checklist.md`
- `artifacts/plans/rollback-plan.md`

Nginx writing creates:

- `artifacts/nginx/*.conf`

Checks write:

- `artifacts/validation/dns-results.txt`
- `artifacts/validation/ssl-results.txt`
- `artifacts/validation/acm-results.txt`

## Labeling

Labels are pattern-based. Tune them here:

```text
settings/labels.conf
```

The default classes are:

- `live`
- `development`
- `staging`
- `unknown`

Unknown means there is not enough evidence. Do not move traffic for unknown resources until ownership and environment are confirmed.

## Commands

```bash
bin/scan-aws.sh
bin/map-domains.sh
bin/write-nginx.sh
bin/check-dns.sh
bin/check-certs.sh
bin/check-acm.sh
```

`bin/check-dns.sh` uses Route53 authoritative DNS tests. `bin/check-certs.sh` validates ACM certificate state, names, expiry, and DNS validation records.

## Required AWS Permissions

Use a read-only role. The commands call read/list/describe APIs such as:

- `route53:ListHostedZones`
- `route53:ListResourceRecordSets`
- `acm:ListCertificates`
- `acm:DescribeCertificate`
- `ec2:DescribeRegions`
- `ec2:DescribeInstances`
- `ec2:DescribeSecurityGroups`
- `ec2:DescribeAddresses`
- `elasticloadbalancing:DescribeLoadBalancers`
- `elasticloadbalancing:DescribeTargetGroups`
- `ecs:ListClusters`
- `eks:ListClusters`

## Live Cutover

Use this repo for evidence and notes. Apply changes through your normal infrastructure workflow. Keep old DNS, certificates, load balancers, and Nginx files available through the rollback window.
