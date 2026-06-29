# Labeling Guide

## Goal

Label resources as live, development, staging, or unknown using explicit evidence.

## Steps

1. Run `bin/map-domains.sh`.
2. Review `artifacts/plans/labeled-resources.md`.
3. Resolve unknowns with service owners.
4. Update `settings/labels.conf` only with organization-approved patterns.
5. Re-run the mapping pass after changes.

## Review Rules

- A label is not a migration decision.
- Environment labels must be confirmed by owners before live cutover.
- Unknown resources must not be migrated automatically.
