# Discovery Guide

## Goal

Build a current inventory before writing any move plan.

## Steps

1. Assume or configure a read-only AWS role.
2. Copy `settings/settings.env.example` to `settings/settings.env`.
3. Choose region scope.
4. Run `bin/scan-aws.sh`.
5. Review `inventory/json/`, `inventory/csv/`, and `inventory/summary/`.
6. Confirm the inventory timestamp in `inventory/json/metadata.json`.

## Notes

- Discovery does not modify AWS.
- Multi-region mode increases API calls but still uses read-only operations.
- If ECS or EKS calls are not permitted, disable `DETECT_CONTAINERS`.
