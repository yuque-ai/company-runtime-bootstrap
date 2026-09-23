# Company Runtime Bootstrap

## Production artifact

Use only the frozen V2.1 release asset. It replaces HEAD-only network preflight with bounded HTTPS GET probes and implements GitHub Actions runner registration with the official explicit `config.sh --token` contract.

```text
5a89769e2e60d92ee09ba986b4a69b2433269cc9ec8d7be1c2cdb9fc1b280d5f  company-runtime-runner-bootstrap-v2.1.sh
```

The registration token is entered once only after `READY_FOR_REGISTRATION=PASS`; it is not part of this repository or release.

## Superseded releases

`bootstrap-v2-13f4db4b` is **SUPERSEDED_FOR_PRODUCTION** because its HEAD-only network probe can be a false negative.

`bootstrap-v1-4214d3b7` remains an audit artifact and is **DEPRECATED_FOR_PRODUCTION**. Do not use it for runner registration.
