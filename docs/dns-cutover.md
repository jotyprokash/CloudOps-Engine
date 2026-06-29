# DNS Cutover Guide

## Goal

Move traffic with reversible DNS changes after checks pass.

## Required Prechecks

- `artifacts/plans/domain-mapping.md` is reviewed.
- New DNS records are created before cutover.
- ACM certificates are issued and valid.
- Nginx configs have passed `nginx -t`.
- Load balancer and target group health checks are green.
- Rollback owner and rollback commands are ready.

## Cutover

1. Capture current DNS answers.
2. Apply the reviewed DNS change outside this toolkit.
3. Validate authoritative and recursive DNS.
4. Validate TLS handshake and certificate names.
5. Validate application health and user journeys.
6. Monitor error rates, latency, and target health.

## Guardrails

- Do not delete old records during cutover.
- Do not revoke old certificates during cutover.
- Do not destroy old infrastructure during cutover.
