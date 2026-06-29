# Rollback Guide

## Goal

Restore the previous routing path quickly without destructive actions.

## Rollback Triggers

- DNS resolves to unexpected targets.
- TLS validation fails.
- Application health checks fail.
- Error rate or latency breaches thresholds.
- Security issue detected after cutover.

## Steps

1. Freeze additional migration changes.
2. Restore previous DNS target through the approved change process.
3. Restore previous Nginx settings if proxy routing caused the issue.
4. Validate DNS, TLS, HTTP, and application health.
5. Communicate status to stakeholders.
6. Preserve evidence for follow-up review.

## Guardrails

- Do not delete DNS records.
- Do not revoke certificates.
- Do not terminate compute resources.
- Do not remove load balancers or target groups.
