# CloudOps Engine

Read-only AWS domain migration toolkit for Route53 inventory, ACM checks, load balancer mapping, Nginx routing files, validation, and rollback notes.

## Safety

- Reads AWS only; does not create, update, or delete resources.
- Never deletes DNS records.
- Keeps real inventory and artifacts out of git.
- Leaves cutover changes to your normal infrastructure workflow.

## How To Use This

```bash
cp settings/settings.env.example settings/settings.env
aws configure list-profiles
aws sts get-caller-identity --profile <profile-name>
aws configure get region --profile <profile-name>
```

Edit `settings/settings.env`:

```bash
AWS_PROFILE=<profile-name>
DISCOVERY_REGION_MODE=current
DETECT_CONTAINERS=true
```

```bash
bin/scan-aws.sh
bin/map-domains.sh
bin/write-report.sh
```

Or run the same flow in one pass:

```bash
bin/full-pass.sh
```

Open the report:

```text
artifacts/report/index.html
```

Run checks after reviewing the generated plan:

```bash
bin/check-dns.sh
bin/check-certs.sh
bin/check-acm.sh
```

Generate Nginx files only after the target upstream and certificate paths are known:

```bash
bin/write-nginx.sh --upstream http://__UPSTREAM_HOST__:__UPSTREAM_PORT__ --cert /path/to/fullchain.pem --key /path/to/privkey.pem
```

## Outputs

- Inventory: `inventory/json/`, `inventory/csv/`, `inventory/summary/`
- Plans: `artifacts/plans/`
- HTML report: `artifacts/report/index.html`
- Optional Nginx files: `artifacts/nginx/`
- Validation output: `artifacts/validation/`
