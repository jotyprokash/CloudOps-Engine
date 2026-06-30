# CloudOps Engine

Read-only AWS cutover toolkit for separating live and development domains with Route53 inventory, ACM checks, load balancer mapping, Nginx routing files, DNS validation, and rollback notes.

## Safety

- Reads AWS only; does not create, update, or delete resources.
- Never deletes DNS records.
- Keeps real inventory and artifacts out of git.
- Leaves cutover changes to your normal infrastructure workflow.

## What It Reads

- Route53 hosted zones and records
- ACM certificates
- EC2 instances
- ALB/NLB resources
- Target Groups
- Security Groups
- Elastic IPs
- Optional ECS/EKS clusters

## How To Use This

```bash
cp settings/settings.env.example settings/settings.env
```

Set `AWS_PROFILE`, `DISCOVERY_REGION_MODE`, or `DISCOVERY_REGIONS` in `settings/settings.env` if needed.

```bash
bin/scan-aws.sh
bin/map-domains.sh
bin/write-nginx.sh --upstream http://__UPSTREAM_HOST__:__UPSTREAM_PORT__ --cert /path/to/fullchain.pem --key /path/to/privkey.pem
bin/check-dns.sh
bin/check-certs.sh
bin/check-acm.sh
```

One-pass run:

```bash
bin/full-pass.sh
```

## Outputs

- `inventory/json/`, `inventory/csv/`, `inventory/summary/`
- `artifacts/plans/`
- `artifacts/nginx/`
- `artifacts/validation/`

## AWS Access

Use a read-only role. A starter policy is available at:

```text
docs/aws-readonly-policy.example.json
```
