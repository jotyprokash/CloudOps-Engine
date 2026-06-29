# Nginx Guide

## Goal

Write generic files to review for target domains.

## Steps

1. Run the AWS scan and mapping pass.
2. Run `bin/write-nginx.sh`.
3. Replace placeholder upstreams and certificate paths.
4. Test with `nginx -t`.
5. Deploy through the normal configuration pipeline.
6. Keep previous configs available for rollback.

## Notes

- Written files are starting points, not deployment automation.
- This kit does not reload or restart Nginx.
- Use environment-specific certificates and upstreams managed outside this repository.
