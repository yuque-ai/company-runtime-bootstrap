# Company Runtime Bootstrap

This repository distributes the credential-free, frozen bootstrap script for the Company Runtime GitHub Actions self-hosted runner.

## Integrity

Verify the downloaded script before execution:

```text
4214d3b7a47668512d364b1a2efa991b784616555b0cf74f6dab223d8033dec2  company-runtime-runner-bootstrap.sh
```

The script contains no registration token, private key, ECS secret, Feishu secret, or other production credential. The runner registration token is supplied only interactively after the script reports `READY_FOR_REGISTRATION=PASS`.
