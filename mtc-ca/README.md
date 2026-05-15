# MTC Demo CA

This directory runs a local [cactus](https://github.com/mcpherrinm/cactus/tree/main/signer)
MTC CA and ACME server in Docker. It is intentionally configured with a
committed ML-DSA CA cosigner seed so demo runs are reproducible.

The image builds cactus from `mcpherrinm/cactus` at:

```text
c7bcec61c45b3dd20964e2839eb9542ee8e7a5cf
```

## Run

```sh
cd mtc-ca
docker compose up --build
```

The CA is published on the host for quick inspection:

```sh
curl http://localhost:14000/directory
curl http://localhost:14080/checkpoint
curl http://localhost:14090/metrics
```

Inside the `mtc-demo` Docker network, other containers can reach the CA by
Docker DNS at:

```text
http://ca.mtc-demo.test:14000/directory
```

The ACME server uses cactus's `auto-pass` challenge mode, so future demo ACME
clients do not need DNS-01 or HTTP-01 challenge plumbing just to get a
certificate.

## Credentials

`keys/ca-cosigner.seed.b64` is the committed demo credential. The entrypoint
decodes it into `/var/lib/cactus/keys/ca-cosigner.seed` on first start. This is
only for repeatable demos and must not be used as a real CA key.

To reset all CA state while keeping the same committed key:

```sh
docker compose down -v
```
