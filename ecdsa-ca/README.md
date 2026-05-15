# ECDSA Demo CA

This directory contains the committed ECDSA P-256 root used only to authenticate
the local Cactus ACME server over HTTPS.

- `root.key` and `root.crt` are the self-signed demo root.
- `cactus.key` and `cactus.crt` are the Cactus ACME listener key and
  certificate, issued directly by the root.

The Cactus serving certificate is valid for:

- `ca.mtc-demo.test`
- `mtc-ca`
- `localhost`
- `127.0.0.1`

These are demo credentials and must not be used for anything security-sensitive.
