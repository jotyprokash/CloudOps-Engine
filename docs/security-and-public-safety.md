# Security And Public Safety

## Public Repository Rules

- Do not commit real inventory files.
- Do not commit artifacts from a real account unless sanitized.
- Do not hardcode domains, company names, AWS account IDs, secrets, IPs, or ARNs.
- Use placeholders in examples.

## Local Data Handling

Survey files can contain sensitive metadata, including internal DNS names, ARNs, public IPs, certificate names, and tags. The `.gitignore` keeps these files local by default.

## AWS Access

Run with the minimum read-only permissions required for discovery. Prefer short-lived credentials from SSO or an assumed role.
