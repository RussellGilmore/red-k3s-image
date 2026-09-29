---
name: Bug Report
about: Report a bug or unexpected behavior
title: "[BUG] "
labels: bug
assignees: ""
---

## Bug Description

<!-- A clear and concise description of what the bug is -->

## Environment

-   **Packer Version:** <!-- e.g., 1.14.0 -->
-   **Base OS / AMI:** <!-- e.g., Ubuntu 26.04 arm64 (Resolute) -->
-   **Region:** <!-- e.g., us-east-1 -->
-   **Failure Stage:**
    <!-- e.g., packer build, first boot / cloud-init, cert issuance, mumble start -->

## Steps to Reproduce

<!-- Provide steps to reproduce the behavior -->

1.
2.
3.

## Expected Behavior

<!-- What you expected to happen -->

## Actual Behavior

<!-- What actually happened -->

## Build / Runtime Configuration

<!-- Relevant Packer vars or instance user-data (SANITIZE all secrets:
     passwords, domains you don't want public, account IDs) -->

```hcl
# Packer vars or user-data here (sanitized)
```

## Logs

<!-- Relevant output. For build issues: packer build output. For runtime
     issues: /var/log/cloud-init-output.log, journalctl -u mumble-server,
     /var/log/letsencrypt/letsencrypt.log -->
