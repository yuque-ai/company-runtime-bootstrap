# Company Runtime Bootstrap

## Production artifact

Use only the frozen V2 release asset. It implements GitHub Actions runner registration with the official explicit `config.sh --token` contract and keeps the token out of the bootstrap source, Git history, and release asset.

```text
c37ddad339911f44fb3868c7ec2b7d277bb77aa685ef9d745507667af8828bf2  company-runtime-runner-bootstrap-v2.sh
```

The registration token is entered once only after `READY_FOR_REGISTRATION=PASS`; it is not part of this repository or release.

## V1 status

`bootstrap-v1-4214d3b7` remains an audit artifact and is **DEPRECATED_FOR_PRODUCTION**. Do not use it for runner registration.
