MTC Demos
=========

This respository contains documentation and examples about how to use [Merkle
Tree Certificates][mtcs] with existing verification and serving stacks.

## Demos

- [mtc-ca](mtc-ca/) runs a local cactus MTC CA and ACME server in Docker. It
  uses a committed ML-DSA demo key and is reachable from other demo containers
  as `http://ca.mtc-demo.test:14000/directory`.
- [nginx-mldsa](nginx-mldsa/) runs stock `nginx:stable` with a self-signed
  ML-DSA certificate.

[mtcs]: https://datatracker.ietf.org/doc/draft-ietf-plants-merkle-tree-certs/
