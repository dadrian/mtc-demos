# MTC Demo CA

This directory runs a local [cactus](https://github.com/dadrian/cactus/tree/main/signer)
MTC CA and ACME server in Docker. It is intentionally configured with a
committed ML-DSA CA cosigner seed so demo runs are reproducible.

The image builds cactus from `dadrian/cactus` at:

```text
682f9622c84108bf2e9c89aaa6788bfeaaa98b81
```

## Run

```sh
cd mtc-ca
docker compose up --build
```

State is stored in the bind-mounted `state/` directory. That directory contains
the Merkle tree, checkpoint, ACME state, issued cert database, and the decoded
demo key seed, so `docker compose stop` / `docker compose start` will preserve
the CA state.

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

`keys/ca-cosigner.seed` is the committed demo credential generated with
`cactus-keygen`. Docker Compose mounts it read-only at cactus's expected
`/var/lib/cactus/keys/ca-cosigner.seed` path. This is only for repeatable demos
and must not be used as a real CA key.

To reset all CA state while keeping the same committed key:

```sh
docker compose down
rm -rf state
docker compose up -d
```
