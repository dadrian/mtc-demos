# NGINX MTC ACME Demo

This container uses:

- stock `nginx:stable`
- Debian's unmodified `lego` ACME client package
- OpenSSL 3.5.5 from the NGINX image to generate an ML-DSA-44 leaf key and CSR
- the local cactus MTC CA at `https://ca.mtc-demo.test:14000/directory`

On startup, `issue-and-run.sh` creates an ML-DSA-44 leaf key if needed, builds a
CSR, asks lego to sign that CSR with the MTC CA, writes the returned
standalone MTC PEM to `state/certs/leaf.crt`, and starts NGINX with that PEM.

The ACME client is not patched. The required client behavior is:

- allow a custom HTTPS ACME directory URL
- support signing an externally generated CSR
- tolerate a single-certificate standalone MTC response

`lego` satisfies those requirements here. The ECDSA P-256 root certificate from
`../ecdsa-ca/root.crt` is mounted into the container and selected as the trusted
CA bundle with `SSL_CERT_FILE`.

## Run

Start the CA first:

```sh
cd ../mtc-ca
docker compose up -d
```

Then run this container:

```sh
cd ../nginx-mtc-acme
docker compose up --build -d
```

The service is available from the host on port `15443` and from the `mtc-demo`
Docker network as `nginx-mtc-acme.mtc-demo.test`.

## Check

Use an OpenSSL 3.5+ client:

```sh
docker run --rm --network mtc-demo nginx:stable \
  sh -lc 'openssl s_client -connect nginx-mtc-acme.mtc-demo.test:443 \
    -servername nginx-mtc-acme.mtc-demo.test -showcerts </dev/null'
```

The served certificate should have:

```text
Public Key Algorithm: ML-DSA-44
Signature Algorithm: 1.3.6.1.4.1.44363.47.0
```

The signature algorithm OID is cactus's `id-alg-mtcProof` marker for standalone
MTCs.
