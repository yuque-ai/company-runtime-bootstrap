# Company Runtime Bootstrap

## Production artifact

Use only the frozen V2 release asset. It implements GitHub Actions runner registration with the official explicit `config.sh --token` contract and keeps the token out of the bootstrap source, Git history, and release asset.

```text
13f4db4b0c115e43f3075ab6cba9e90f629226b5f709f1a4678f9a63cfcd57e2  company-runtime-runner-bootstrap-v2.sh
```

The registration token is entered once only after `READY_FOR_REGISTRATION=PASS`; it is not part of this repository or release.

## V1 status

`bootstrap-v1-4214d3b7` remains an audit artifact and is **DEPRECATED_FOR_PRODUCTION**. Do not use it for runner registration.
