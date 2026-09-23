# Company Runtime Bootstrap

## Production artifact

Use only the frozen V2.2 release asset. It models the GitHub Actions Runner lifecycle correctly: extraction does not require `svc.sh`; after successful `config.sh --token`, `svc.sh`, `.runner`, and `.credentials` are all required before service installation.

```text
0bd40d66088ea2d9a3a0168a78c6e9746e6ca094ee75dfbd83e48cab849a1f75  company-runtime-runner-bootstrap-v2.2.sh
```

The registration token is entered once only after `READY_FOR_REGISTRATION=PASS`; it is not part of this repository or release.

## Superseded releases

`bootstrap-v2-1-5a89769e` is **SUPERSEDED_FOR_PRODUCTION** because it required `svc.sh` before runner configuration.

`bootstrap-v2-13f4db4b` is **SUPERSEDED_FOR_PRODUCTION** because its HEAD-only network probe can be a false negative.

`bootstrap-v1-4214d3b7` remains an audit artifact and is **DEPRECATED_FOR_PRODUCTION**. Do not use it for runner registration.
