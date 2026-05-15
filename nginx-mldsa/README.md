# NGINX ML-DSA TLS Demo

This demo runs the stock official `nginx:stable` image with an ML-DSA-44 leaf
certificate issued by a committed ML-DSA-44 demo root. There is no custom NGINX
or OpenSSL build here.

The current `nginx:stable` image is:

- NGINX `1.30.1`
- built with OpenSSL `3.5.5`
- able to generate and serve ML-DSA-44 certificates

OpenSSL `4.0.0` is the latest OpenSSL stable release as of May 2026, but I did
not find a ready official Docker image for it, and common distro containers are
still on OpenSSL `3.5.x`. OpenSSL `3.5.x` is new enough for this TLS+ML-DSA
demo.

## Certificates

The committed root material is:

- `certs/root.key`
- `certs/root.crt`

On startup, the container creates `certs/leaf.key`, `certs/leaf.csr`, and
`certs/leaf.crt` if the leaf key or certificate is missing. The leaf is signed
directly by the root; there is no intermediate certificate.

All keys and certificate signatures use ML-DSA-44.

## Run

```sh
cd nginx-mldsa
docker compose up -d
```

The service is available from the host on port `14443` and from the `mtc-demo`
Docker network as `nginx-mldsa.mtc-demo.test`.

## Check With OpenSSL

```sh
openssl s_client \
  -connect localhost:14443 \
  -servername nginx-mldsa.mtc-demo.test \
  -showcerts </dev/null
```

The peer certificate should show:

```text
Signature Algorithm: ML-DSA-44
Public Key Algorithm: ML-DSA-44
```

The direct issuer should be the committed root:

```text
issuer=CN=nginx-mldsa demo root
```

## Curl Notes

Your macOS `/usr/bin/curl` uses SecureTransport/LibreSSL, not OpenSSL, and may
not accept ML-DSA certificates yet. An OpenSSL-backed curl with OpenSSL 3.5 or
newer is the expected client for this demo. With an OpenSSL-backed curl, use
the committed root as the trust anchor:

```sh
curl --cacert certs/root.crt https://localhost:14443/
```
