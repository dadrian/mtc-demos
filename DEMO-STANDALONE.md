# MTC Demo Walkthrough

> The Paxos algorithm, when presented in plain English, is very simple.

A standalone MTC, when consumed by a server, is very simple! Standalone Merkle
Tree Certificates (MTCs) look like ordinary X.509 certificates to the software
that serves them; the only difference is the `signatureAlorithm` OID.

Don't believe me? Well, let's define a couple requirements, and then go through
a few examples.

Certificates are relevant to _authenticating_ an HTTPS connection. For the
public Web PKI, we also want an additional property, _transparency_, meaning
that there is cryptographic proof that every certificate is _publicly logged_.
Historically, transparency has come from the [certificate transparency
(CT)][transparency] ecosystem. While not perfect, the existence of transparency
is what prevents CAs from being the juiciest possible target for malicious
actors. For a maliciously-issued certificate to be used to authenticate a
website, it needs to be disclosed, which ultimately reduces the efficacy of
malicious issuance as an attack vector, compared to [the before
times][diginotar].

For HTTPS, there are effectively two options for post-quantum certificates:
- **Chonky X.509**, where we simply copy/paste key and signature algorithms from
  pre-quantum to post-quantum. Effectively, anywhere an RSA or ECDSA key or
  signature was used, we use an ML-DSA key or signature instead. Transparency
  would then be layered in via CT for the public PKI, but could be excluded for
  private PKIs where the issuer and authenticating party are the same.
- **Merkle Tree Certificates (MTCs)**, which are a mechanism for embedding
  [transparency information][transparency] directly into an X.509 certificate.

MTCs can technically be used with an key type, but for the purposes of this,
let's assume we're always talking about MTCs with ML-DSA, the post-quantum
signature algorithm. MTCs are still X.509 certificates, however the contents and
expectations around the signature algorithm used on the certificate change.

While an MTC CA needs to operate a tree, an MTC itself is just a certificate
with a fancy signature algorithm. MTCs come in two variants---the larger
_standalone_ certificate, and smaller _landmark-relative_ certificate. In both
cases, the MTC part of the certificate is entirely contained within the
`signatureAlgorithm` field in the certificate. The certificate is still X.509,
and the key in the certificate of the end-entity (i.e. the web server) is a
normal ML-DSA key. For a server to use either form of MTC to authenticate itself
(assuming it has obtained one---more on that another time), it just needs to be
able to sign with the end-entity key. Servers don't actually interact with the
_signature_ from the CA!

Let's look at this from the clients perspective. First, back to chonky X.509.
What would the client need to verify a chonky X.509 ML-DSA certificate? Well,
the client would need some sort of representation of the trust anchor, probably
an X.509 root certificate in PEM format, to provide a root of trust. It also
needs to understand some new (relative to pre-quantum) algorithmIdentifier, \TK,
and understand that identifier means ML-DSA, and its X.509 stack needs to be
updated to know how to verify a signature using the indicated algorithm.

What about a standalone MTC? Well, once again, the client would need some sort
of representation on an MTC CA, likely an X.509 certificate in PEM format. It
also needs to understand some new (relative to pre-quantum)
`algorithmIdentifier`, \TK, and understand that identifier means "ML-DSA in a
Merkle Tree", and then its X.509 stack needs be updated to know how to verify
using the indicated algorithm.

You might notice that these are effectively the same requirements, the only
difference is _what_ algorithm is executed by the verifier in the X.509 stack.
With Chonky X.509, the algorithm is "feed the bytes of the certificate into
ML-DSA Verify()". With Chonky X.509, the algorithm is "\TODO". In both cases,
all of the information needed to verify the certificate is contained in the
signatureAlgorithm, and the only update required for the client is to speak the
new signature algorithm, and the only data the client needs to bootstrap the
verification is an X.509 certificate to use as a trust anchor.

For clients, the situation is slightly more complicated for landmark-relative
certificates. We'll save that for another demo.

At this point, you might be lost, so let's look at two things:
1. Configuring a server and client to use a Chonk X.509 ML-DSA certificate and root
2. Configuring a server and client to use an MTC certificate and MTC CA

For both examples, we'll use NGINX as our web server with an out-of-the box
OpenSSL 3.5.

## Requirements

To use ML-DSA with OpenSSL and NGINX, you need at least OpenSSL 3.5. This is not
yet available on MacOS without Homebrew. For compatibility for ML-DSA
operations, the walkthrough uses short-lived `nginx:stable` helper containers
because that image currently has OpenSSL 3.5.x and curl built against it.

All the examples here are orchestrated with Docker Compose, so you'll need that
if you want to follow along in your terminal. The Docker network name for allJ
examples (so they can talk to each other) is `mtc-demo`.

## Chonky X.509

Let's start out with Chonky X.509 without transparency. ML-DSA isn't defined
publicly trusted certificates, so we'll use our own [ML-DSA root
certificate](./nginx-mldsa/certs/root.key) as a trust anchor.

This is the baseline: an ordinary X.509 certificate, directly issued by a demo
root, where the leaf public key and certificate signatures are ML-DSA-44. This
is standard, but Chonky X.509 using ML-DSA signatures, without an intermediate
certificate.

## 1. Start `nginx-mldsa`

```sh
docker compose -f nginx-mldsa/docker-compose.yml up -d
```

On first execution, the container creates a new ML-DSA-44 leaf at startup and
signs it with the committed ML-DSA-44 demo root, storing it in
`nginx-mldsa/certs`. Normally, this certificate would come from ACME or some
other mechanism for communicating with a CA. The scripting for issuing the
certificate isn't important---what is important is "how do we configure NGINX to
use it?". You can [view the file directly](./nginx-mldsa/conf.d/default.conf), or
just look at the relevant bits below.

```
server {

    # ...
    ssl_protocols TLSv1.3;

    ssl_certificate /etc/nginx/certs/leaf.crt;
    ssl_certificate_key /etc/nginx/certs/leaf.key;

    # ...
}
```

From the server's perspective, we needed two things:
1. An OpenSSL that supported ML-DSA
2. A certificate that use ML-DSA

Actually getting certificates can be complicated! I'm not downplaying it! But
fundamentally, this configuration is the exact same as what you might apply if
you were serving an RSA or ECDSA certificate instead.

Let's look at what it would take to get a client, such as curl, to verify a
connection using this certificate. To do that, we need:
1. A version of curl that supports ML-DSA
2. To specify our root CA as a trust anchor.

The standalone curl command would be:

```sh
curl --fail --silent --show-error --cacert ./nginx-mldsa/root.crt https://nginx-mldsa.mtc-demo.test
```

The `--cacert` specifies our trust anchor, and the other flags just make curl
shut up but still output errors sanely. Since our server is running on a Docker
network, we'll run the same command but jammed through the `nginx:stable` Docker
image with `root.crt`. This also guarantees we'll have an up-to-date curl that
supports ML-DSA.

```sh
docker run --rm --network mtc-demo \
  -v "$PWD/nginx-mldsa/certs/root.crt:/root.crt:ro" \
  nginx:stable \
  sh -lc 'curl --fail --silent --show-error --cacert /root.crt \
    https://nginx-mldsa.mtc-demo.test/'
```

Expected response:

```text
nginx-mldsa: ML-DSA certificate served by stock nginx:stable
```

Look at that! Given a server that spoke ML-DSA, and a client that had the
correct trust anchor, we verified the connection.

\TODO: dadrian edited through here

## 2. Start `mtc-ca`

This starts Cactus. The Cactus CA signs the MTC log state with its committed
ML-DSA-44 cosigner seed and exposes an ACME directory over HTTPS for local demo
clients.

```sh
docker compose -f mtc-ca/docker-compose.yml up -d
```

Successful output looks like:

```text
Container mtc-ca  Recreate
Container mtc-ca  Recreated
Container mtc-ca  Starting
Container mtc-ca  Started
```

Check the ACME directory from a helper container:

```sh
docker run --rm --network mtc-demo \
  -v "$PWD/ecdsa-ca/root.crt:/root.crt:ro" \
  nginx:stable \
  sh -lc 'curl --fail --silent --show-error --cacert /root.crt \
    https://ca.mtc-demo.test:14000/directory'
```

Expected response:

```json
{"newNonce":"https://ca.mtc-demo.test:14000/new-nonce","newAccount":"https://ca.mtc-demo.test:14000/new-account","newOrder":"https://ca.mtc-demo.test:14000/new-order"}
```

## 3. Start `nginx-mtc-acme`

This container creates an ML-DSA-44 leaf key, builds a CSR, asks Cactus for a
standalone MTC over ACME using unmodified lego, writes the returned PEM to its
mounted state directory, and starts NGINX with that PEM.

```sh
docker compose -f nginx-mtc-acme/docker-compose.yml up -d --build
```

Successful output looks like:

```text
nginx-mtc-acme  Built
Container nginx-mtc-acme  Recreate
Container nginx-mtc-acme  Recreated
Container nginx-mtc-acme  Starting
Container nginx-mtc-acme  Started
```

The important certificate issuance happens in the `nginx-mtc-acme` logs:

```sh
docker logs --tail 40 nginx-mtc-acme
```

Successful issuance looks like:

```text
2026/05/15 19:15:19 [INFO] [nginx-mtc-acme.mtc-demo.test, localhost] acme: Obtaining SAN certificate given a CSR
2026/05/15 19:15:19 [INFO] [nginx-mtc-acme.mtc-demo.test] AuthURL: https://ca.mtc-demo.test:14000/authz/7618bab60a043840e13bb241afa7f4b6
2026/05/15 19:15:19 [INFO] [localhost] AuthURL: https://ca.mtc-demo.test:14000/authz/7ed9e58a68965d4f578015b21d6b1079
2026/05/15 19:15:19 [INFO] [nginx-mtc-acme.mtc-demo.test] acme: authorization already valid; skipping challenge
2026/05/15 19:15:19 [INFO] [localhost] acme: authorization already valid; skipping challenge
2026/05/15 19:15:19 [INFO] [nginx-mtc-acme.mtc-demo.test, localhost] acme: Validations succeeded; requesting certificates
2026/05/15 19:15:20 [INFO] [nginx-mtc-acme.mtc-demo.test] Server responded with a certificate.
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Check that NGINX responds:

```sh
docker run --rm --network mtc-demo nginx:stable \
  sh -lc 'curl --insecure --fail --silent --show-error \
    https://nginx-mtc-acme.mtc-demo.test/'
```

Expected response:

```text
nginx-mtc-acme: standalone MTC from ACME with an ML-DSA leaf key
```

## Get the ordinary ML-DSA X.509 certificate as PEM

This command uses curl inside `nginx:stable` to connect to `nginx-mldsa`, verify
with the committed ML-DSA demo root, and print the served certificate as PEM.

```sh
docker run --rm --network mtc-demo \
  -v "$PWD/nginx-mldsa/certs/root.crt:/root.crt:ro" \
  nginx:stable \
  sh -lc 'curl --silent --show-error --fail --cacert /root.crt \
    --write-out "%{certs}" --output /dev/null \
    https://nginx-mldsa.mtc-demo.test/ | \
    sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p"'
```

Sample PEM:

```pem
-----BEGIN CERTIFICATE-----
MIIP9zCCBm2gAwIBAgIRAObu9/GH0jjXkzWv8eqxcrowCwYJYIZIAWUDBAMRMCAx
HjAcBgNVBAMMFW5naW54LW1sZHNhIGRlbW8gcm9vdDAeFw0yNjA1MTUxODMzMTha
Fw0yNjA2MTQxODMzMThaMCQxIjAgBgNVBAMMGW5naW54LW1sZHNhLm10Yy1kZW1v
LnRlc3QwggUyMAsGCWCGSAFlAwQDEQOCBSEAyvqMzDXruiE6jnLJi9ScLrk3T5oq
QqmoS7ttann+H/eSrVZgNv190MNTnTht8NRHt9jgT7zHOUPtOhG7GYtiGe6vcGRo
HIErsYy0JBch7pObTsetKOu9eACElC898GjVYWA2EVoo5zfTxsOR+2sa4LOl6dqS
05zp/OPWx6pu8exE4l2or6I/yCplIYvX27eR6cO7pxqTaEDWuzSVBfg4uxaQswQE
XGiNK0ePWBn7PcNhFkdo5cjclfZFqvfu8dB6j5dsgWgpq6ayxD8sJULwr/lmEl7Z
EKz7zYAD/slS+sXPIGIpXD58CIq7+TCmkrKh+0aSEwgxo95xvBFcxapPrDh75rGq
GXwfaa6S6kwBS7uOgyi9xgwHa5yN4cNqfemewLoYK9LMkBP41+F1R8jRxXtftgkG
1JlbG5UGkUqbH1wB+7eLVc6nzH4WKH1HWHuqoLUVMi2WRLPtV4FE8kMB2ziu/6l5
QUiW7JVmMKvKkdmb7t2OBTgqMLkquFiPgv5rBdRhNcRHp3WUcJc2u6UXs66F5L04
ikHfLQun5Rmv3TWbZdAi2RAYxEpcXkDSpBnyDGUi63V+WvyJTKorfzm6fBARQdd5
6hPP0ZoMpzK+ZgTxX5ACn5PRfL3KC12tzyBR2Ve9HPk6goVBNeDOJtbMpGQ60yj2
YYjRgfz6+eU1ZWsQKijObIpUYIz2S3sb53RJrdBWtqzK5gHxx0Ufk324ajLCSKGP
w8uwmK/X5/1Omb8WUFwtiPR+HizDIs3XEES+DcJAqpU/BEN4hRpRQBuwO26jx4qu
eSkMavCbdvWF1I4oWtgxzxLxqw3tuuHMx4WckjM9QddxkOH1yDnmsvZqkGJD6Wej
o5Os0C4O7gG9+0c2bd03RJk+HqkyDsWA6NtbIPrWXeaI7obJKoMHg3wxfbZMubon
hh6lMpMghFMrm7UXffItKZAhLMl7NjYOovvne4uQpV3zUxbe0l49ICS8QvjBPc1R
+AuuNLC/N2SIlNUWNZrj/jzelDIAphg6V9Txv9dtYlTBeuPTrlVC07jnIwXBOnL7
RaFvYtQtWEkdMtwX2Gy2/P1inUN1upLus0+B7QmanaUniu5cgf8liLtYdNSz7IkA
bimnEBBplGVx+t4jBngyLyz9jBJMwdSpAEgAJMnlR8A/rPHz9l/fdYTsUnLCC0wf
549VO4bY3hzGzEctfXgpJtXRPsxMYBbeJWMhypE5dMSa9mcqO5y1uE6SFgLU90Y7
KpChhlidWYf/M50iVoCzFRyFYqk9rSXJol92VqRl8ulR78fbxMe3nBcZlzLi91C7
ePl18719QUVEqXP9nfZijC6Nu0Xv6PrnBX1ZhimZ7eh61vsieBojXzrxqT8JSGTn
JCqpKsDFC84dy6hJ0RHODOjlA+MaGnjKd/PseITXZgSOIf1a4NX7ZigKnIeQ+h1T
GdwrNp2HvAJ1SnWiQnjNKkVkWFxmSfUq1e5Jepp6HA/Phhu9FoqmyQT49DOBkwkx
jyruSyAacHj10fmzs6mBtcnYHCkPU4K63LzxcDgYT9pVj+ZouL5lWFb7RxG1HfR+
F+IDDoFoF/IdCI47XbZaE47UXUjYU+bHTQNHE2sbc9hdhxTJtlhhSdeTo3syePYw
wM9dKzPGlae4wtzPnptwPgtL0Hstk8ceXfkLDFhv0LqCsJ1l3bzvrinEAyLJvkn5
8oTdI0bsiyTofBE7t5BaFn9H0EFUIRXRcCFBxBiykRw6UZKdQcEPHMkrgKOBpzCB
pDAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEF
BQcDATAvBgNVHREEKDAmghluZ2lueC1tbGRzYS5tdGMtZGVtby50ZXN0gglsb2Nh
bGhvc3QwHQYDVR0OBBYEFLqoscVdeZO1BCRRe8/xR856r5J0MB8GA1UdIwQYMBaA
FBVv5Ez5AOahLm52onoSAh6uR96IMAsGCWCGSAFlAwQDEQOCCXUA+N5yiplEgRKe
Hyv7rmGtMeqPf6Rrkw886YDu+8dppt/8XiL6nDd+jn357K9of8xAiE8yznb/gW0d
cha2KXdn2VojFOjeSoF7pOtjk7lzdY09wqLi3DNvOlfK0pFzTPYa5o38oRWFwxm/
4ZqiN3XtoVNAuTTmEd1+UP6Lvwot3ODksjv+/5V7it2hXQJ/JUrQ2oDqTSoZxH/h
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
AAAAAAAAABceMEE=
-----END CERTIFICATE-----
```

OpenSSL text form:

```sh
docker run --rm --network mtc-demo \
  -v "$PWD/nginx-mldsa/certs/root.crt:/root.crt:ro" \
  nginx:stable \
  sh -lc 'curl --silent --show-error --fail --cacert /root.crt \
    --write-out "%{certs}" --output /dev/null \
    https://nginx-mldsa.mtc-demo.test/ | \
    sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" | \
    openssl x509 -noout -text'
```

Sample `openssl x509 -text` output:

```text
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            e6:ee:f7:f1:87:d2:38:d7:93:35:af:f1:ea:b1:72:ba
        Signature Algorithm: ML-DSA-44
        Issuer: CN=nginx-mldsa demo root
        Validity
            Not Before: May 15 18:33:18 2026 GMT
            Not After : Jun 14 18:33:18 2026 GMT
        Subject: CN=nginx-mldsa.mtc-demo.test
        Subject Public Key Info:
            Public Key Algorithm: ML-DSA-44
                ML-DSA-44 Public-Key:
                pub:
                    ca:fa:8c:cc:35:eb:ba:21:3a:8e:72:c9:8b:d4:9c:
                    2e:b9:37:4f:9a:2a:42:a9:a8:4b:bb:6d:6a:79:fe:
                    1f:f7:92:ad:56:60:36:fd:7d:d0:c3:53:9d:38:6d:
                    f0:d4:47:b7:d8:e0:4f:bc:c7:39:43:ed:3a:11:bb:
                    19:8b:62:19:ee:af:70:64:68:1c:81:2b:b1:8c:b4:
                    24:17:21:ee:93:9b:4e:c7:ad:28:eb:bd:78:00:84:
                    94:2f:3d:f0:68:d5:61:60:36:11:5a:28:e7:37:d3:
                    c6:c3:91:fb:6b:1a:e0:b3:a5:e9:da:92:d3:9c:e9:
                    fc:e3:d6:c7:aa:6e:f1:ec:44:e2:5d:a8:af:a2:3f:
                    c8:2a:65:21:8b:d7:db:b7:91:e9:c3:bb:a7:1a:93:
                    68:40:d6:bb:34:95:05:f8:38:bb:16:90:b3:04:04:
                    5c:68:8d:2b:47:8f:58:19:fb:3d:c3:61:16:47:68:
                    e5:c8:dc:95:f6:45:aa:f7:ee:f1:d0:7a:8f:97:6c:
                    81:68:29:ab:a6:b2:c4:3f:2c:25:42:f0:af:f9:66:
                    12:5e:d9:10:ac:fb:cd:80:03:fe:c9:52:fa:c5:cf:
                    20:62:29:5c:3e:7c:08:8a:bb:f9:30:a6:92:b2:a1:
                    fb:46:92:13:08:31:a3:de:71:bc:11:5c:c5:aa:4f:
                    ac:38:7b:e6:b1:aa:19:7c:1f:69:ae:92:ea:4c:01:
                    4b:bb:8e:83:28:bd:c6:0c:07:6b:9c:8d:e1:c3:6a:
                    7d:e9:9e:c0:ba:18:2b:d2:cc:90:13:f8:d7:e1:75:
                    47:c8:d1:c5:7b:5f:b6:09:06:d4:99:5b:1b:95:06:
                    91:4a:9b:1f:5c:01:fb:b7:8b:55:ce:a7:cc:7e:16:
                    28:7d:47:58:7b:aa:a0:b5:15:32:2d:96:44:b3:ed:
                    57:81:44:f2:43:01:db:38:ae:ff:a9:79:41:48:96:
                    ec:95:66:30:ab:ca:91:d9:9b:ee:dd:8e:05:38:2a:
                    30:b9:2a:b8:58:8f:82:fe:6b:05:d4:61:35:c4:47:
                    a7:75:94:70:97:36:bb:a5:17:b3:ae:85:e4:bd:38:
                    8a:41:df:2d:0b:a7:e5:19:af:dd:35:9b:65:d0:22:
                    d9:10:18:c4:4a:5c:5e:40:d2:a4:19:f2:0c:65:22:
                    eb:75:7e:5a:fc:89:4c:aa:2b:7f:39:ba:7c:10:11:
                    41:d7:79:ea:13:cf:d1:9a:0c:a7:32:be:66:04:f1:
                    5f:90:02:9f:93:d1:7c:bd:ca:0b:5d:ad:cf:20:51:
                    d9:57:bd:1c:f9:3a:82:85:41:35:e0:ce:26:d6:cc:
                    a4:64:3a:d3:28:f6:61:88:d1:81:fc:fa:f9:e5:35:
                    65:6b:10:2a:28:ce:6c:8a:54:60:8c:f6:4b:7b:1b:
                    e7:74:49:ad:d0:56:b6:ac:ca:e6:01:f1:c7:45:1f:
                    93:7d:b8:6a:32:c2:48:a1:8f:c3:cb:b0:98:af:d7:
                    e7:fd:4e:99:bf:16:50:5c:2d:88:f4:7e:1e:2c:c3:
                    22:cd:d7:10:44:be:0d:c2:40:aa:95:3f:04:43:78:
                    85:1a:51:40:1b:b0:3b:6e:a3:c7:8a:ae:79:29:0c:
                    6a:f0:9b:76:f5:85:d4:8e:28:5a:d8:31:cf:12:f1:
                    ab:0d:ed:ba:e1:cc:c7:85:9c:92:33:3d:41:d7:71:
                    90:e1:f5:c8:39:e6:b2:f6:6a:90:62:43:e9:67:a3:
                    a3:93:ac:d0:2e:0e:ee:01:bd:fb:47:36:6d:dd:37:
                    44:99:3e:1e:a9:32:0e:c5:80:e8:db:5b:20:fa:d6:
                    5d:e6:88:ee:86:c9:2a:83:07:83:7c:31:7d:b6:4c:
                    b9:ba:27:86:1e:a5:32:93:20:84:53:2b:9b:b5:17:
                    7d:f2:2d:29:90:21:2c:c9:7b:36:36:0e:a2:fb:e7:
                    7b:8b:90:a5:5d:f3:53:16:de:d2:5e:3d:20:24:bc:
                    42:f8:c1:3d:cd:51:f8:0b:ae:34:b0:bf:37:64:88:
                    94:d5:16:35:9a:e3:fe:3c:de:94:32:00:a6:18:3a:
                    57:d4:f1:bf:d7:6d:62:54:c1:7a:e3:d3:ae:55:42:
                    d3:b8:e7:23:05:c1:3a:72:fb:45:a1:6f:62:d4:2d:
                    58:49:1d:32:dc:17:d8:6c:b6:fc:fd:62:9d:43:75:
                    ba:92:ee:b3:4f:81:ed:09:9a:9d:a5:27:8a:ee:5c:
                    81:ff:25:88:bb:58:74:d4:b3:ec:89:00:6e:29:a7:
                    10:10:69:94:65:71:fa:de:23:06:78:32:2f:2c:fd:
                    8c:12:4c:c1:d4:a9:00:48:00:24:c9:e5:47:c0:3f:
                    ac:f1:f3:f6:5f:df:75:84:ec:52:72:c2:0b:4c:1f:
                    e7:8f:55:3b:86:d8:de:1c:c6:cc:47:2d:7d:78:29:
                    26:d5:d1:3e:cc:4c:60:16:de:25:63:21:ca:91:39:
                    74:c4:9a:f6:67:2a:3b:9c:b5:b8:4e:92:16:02:d4:
                    f7:46:3b:2a:90:a1:86:58:9d:59:87:ff:33:9d:22:
                    56:80:b3:15:1c:85:62:a9:3d:ad:25:c9:a2:5f:76:
                    56:a4:65:f2:e9:51:ef:c7:db:c4:c7:b7:9c:17:19:
                    97:32:e2:f7:50:bb:78:f9:75:f3:bd:7d:41:45:44:
                    a9:73:fd:9d:f6:62:8c:2e:8d:bb:45:ef:e8:fa:e7:
                    05:7d:59:86:29:99:ed:e8:7a:d6:fb:22:78:1a:23:
                    5f:3a:f1:a9:3f:09:48:64:e7:24:2a:a9:2a:c0:c5:
                    0b:ce:1d:cb:a8:49:d1:11:ce:0c:e8:e5:03:e3:1a:
                    1a:78:ca:77:f3:ec:78:84:d7:66:04:8e:21:fd:5a:
                    e0:d5:fb:66:28:0a:9c:87:90:fa:1d:53:19:dc:2b:
                    36:9d:87:bc:02:75:4a:75:a2:42:78:cd:2a:45:64:
                    58:5c:66:49:f5:2a:d5:ee:49:7a:9a:7a:1c:0f:cf:
                    86:1b:bd:16:8a:a6:c9:04:f8:f4:33:81:93:09:31:
                    8f:2a:ee:4b:20:1a:70:78:f5:d1:f9:b3:b3:a9:81:
                    b5:c9:d8:1c:29:0f:53:82:ba:dc:bc:f1:70:38:18:
                    4f:da:55:8f:e6:68:b8:be:65:58:56:fb:47:11:b5:
                    1d:f4:7e:17:e2:03:0e:81:68:17:f2:1d:08:8e:3b:
                    5d:b6:5a:13:8e:d4:5d:48:d8:53:e6:c7:4d:03:47:
                    13:6b:1b:73:d8:5d:87:14:c9:b6:58:61:49:d7:93:
                    a3:7b:32:78:f6:30:c0:cf:5d:2b:33:c6:95:a7:b8:
                    c2:dc:cf:9e:9b:70:3e:0b:4b:d0:7b:2d:93:c7:1e:
                    5d:f9:0b:0c:58:6f:d0:ba:82:b0:9d:65:dd:bc:ef:
                    ae:29:c4:03:22:c9:be:49:f9:f2:84:dd:23:46:ec:
                    8b:24:e8:7c:11:3b:b7:90:5a:16:7f:47:d0:41:54:
                    21:15:d1:70:21:41:c4:18:b2:91:1c:3a:51:92:9d:
                    41:c1:0f:1c:c9:2b:80
        X509v3 extensions:
            X509v3 Basic Constraints: critical
                CA:FALSE
            X509v3 Key Usage: critical
                Digital Signature
            X509v3 Extended Key Usage:
                TLS Web Server Authentication
            X509v3 Subject Alternative Name:
                DNS:nginx-mldsa.mtc-demo.test, DNS:localhost
            X509v3 Subject Key Identifier:
                BA:A8:B1:C5:5D:79:93:B5:04:24:51:7B:CF:F1:47:CE:7A:AF:92:74
            X509v3 Authority Key Identifier:
                15:6F:E4:4C:F9:00:E6:A1:2E:6E:76:A2:7A:12:02:1E:AE:47:DE:88
    Signature Algorithm: ML-DSA-44
    Signature Value:
        f8:de:72:8a:99:44:81:12:9e:1f:2b:fb:ae:61:ad:31:ea:8f:
        7f:a4:6b:93:0f:3c:e9:80:ee:fb:c7:69:a6:df:fc:5e:22:fa:
        9c:37:7e:8e:7d:f9:ec:af:68:7f:cc:40:88:4f:32:ce:76:ff:
        81:6d:1d:72:16:b6:29:77:67:d9:5a:23:14:e8:de:4a:81:7b:
        a4:eb:63:93:b9:73:75:8d:3d:c2:a2:e2:dc:33:6f:3a:57:ca:
        d2:91:73:4c:f6:1a:e6:8d:fc:a1:15:85:c3:19:bf:e1:9a:a2:
        37:75:ed:a1:53:40:b9:34:e6:11:dd:7e:50:fe:8b:bf:0a:2d:
        dc:e0:e4:b2:3b:fe:ff:95:7b:8a:dd:a1:5d:02:7f:25:4a:d0:
        da:80:ea:4d:2a:19:c4:7f:e1:d1:3f:a2:10:bb:3f:02:b9:d9:
        fa:bb:e7:16:2e:32:e5:0a:64:94:10:cd:35:45:1c:a1:2b:e1:
        84:2c:de:65:e9:35:1f:d4:b8:f5:3f:9a:4d:63:b4:49:b0:d6:
        94:9e:07:15:ce:38:dd:fd:4b:97:d5:c5:a0:51:79:d4:9f:26:
        1f:12:94:33:39:6a:b4:84:13:a3:2e:3a:a2:49:82:16:6b:34:
        19:a7:9b:0f:4d:d9:e0:67:68:12:db:06:91:58:e8:06:fb:d6:
        fc:f4:3d:cd:2c:6d:08:d7:18:e7:e4:19:26:2f:e0:24:f2:a6:
        17:53:9b:4d:15:ef:9d:99:a4:49:c2:9b:5c:42:31:d5:b9:69:
        63:34:6a:60:10:1e:dc:ad:a4:fb:55:d4:80:d3:e5:fc:f7:da:
        aa:8a:f5:9c:a7:21:6a:e1:ce:6c:62:18:2b:7a:88:36:9f:03:
        8f:3c:40:41:63:f6:a2:73:af:62:fc:00:07:74:23:63:a1:12:
        72:05:1f:40:f0:cc:82:95:1c:4b:06:ac:22:57:af:47:0c:75:
        c9:35:a8:3b:83:99:a0:53:f2:2b:c9:ec:fb:85:6d:45:50:f8:
        f1:c3:77:4d:78:6e:06:ce:d9:46:7f:d1:f7:47:22:0f:d5:d7:
        cb:91:d2:00:38:02:1a:c8:d8:e2:dc:74:15:83:60:35:f5:0c:
        18:1c:3c:14:b9:65:17:fa:be:98:74:e5:bc:24:ac:bd:56:66:
        5e:f5:28:18:b8:ff:b3:df:03:14:33:8a:33:72:76:3f:0e:ab:
        a6:88:44:5b:45:b4:5b:e2:16:c9:2e:0b:ca:c5:a6:0f:29:d8:
        f9:cf:6a:88:7a:b0:03:3f:93:d6:c6:c0:15:7f:77:d5:b4:46:
        a2:2a:43:c8:94:41:a4:cb:90:b1:09:39:d2:98:d0:24:3c:6a:
        e8:d9:58:0a:f1:ba:ca:30:3a:31:48:c5:10:03:fd:f7:a7:fc:
        43:76:f2:25:f0:c4:ad:33:a0:59:b4:69:95:bf:9f:6b:9c:d5:
        e9:3b:4b:70:f1:6a:b4:ef:ec:4a:d2:6f:e4:6a:18:1a:51:47:
        d5:36:55:a6:1e:4f:72:31:4f:10:a6:06:b0:2c:43:53:2d:75:
        9a:58:a5:b8:d5:50:33:2e:d3:97:e9:d4:be:e6:86:22:48:f1:
        93:00:49:c3:2a:20:ca:a8:c4:15:ac:97:2e:b7:44:8a:3b:77:
        a2:48:a0:07:a0:09:0b:3d:97:31:09:e9:25:8d:06:3b:9d:97:
        65:b1:dd:a2:c4:e7:9e:5f:a2:32:6f:61:03:63:e5:c1:d5:87:
        55:8e:28:91:65:b8:9e:69:90:34:40:03:ef:30:f1:04:f6:1d:
        eb:99:76:19:bc:78:08:49:e0:88:b1:c9:6b:2f:dd:a1:f2:6e:
        76:4f:5a:05:bf:39:dd:1b:49:dd:83:75:6d:ae:9c:78:00:7e:
        cd:3d:4c:11:e1:53:ff:fb:63:3e:35:c5:8d:1d:3d:46:18:2b:
        3c:a9:40:5d:49:8b:f9:36:ef:f5:e9:27:61:63:18:d2:9f:93:
        27:0d:c1:bd:c9:6e:a7:cb:b3:a9:0d:02:f1:96:f0:9e:d7:e5:
        34:15:27:35:9a:b2:7d:85:21:10:41:25:ae:1f:7c:52:56:8f:
        2c:41:5c:05:d3:cf:be:c5:21:e1:9e:5f:61:1b:e3:fe:f6:25:
        78:60:fb:e1:8a:5e:75:3f:f9:7e:85:4a:c3:26:6a:ab:29:7d:
        f3:60:6c:76:bd:2b:0e:27:5f:67:c4:06:c3:df:ab:a5:91:37:
        3f:4d:af:04:96:98:09:14:38:7e:ad:2b:b4:c1:56:61:7b:f5:
        ca:33:a7:c9:b5:8a:6a:54:8b:2f:f2:f0:b6:ce:1c:7b:0c:66:
        1e:c5:0c:82:a1:ff:bb:90:5d:8c:64:04:c7:5d:b3:77:fe:fd:
        3c:14:cd:e0:f4:1f:bf:42:ff:23:cf:53:83:45:ef:52:24:3a:
        ba:20:67:14:72:16:75:ac:bc:42:a7:57:c5:0c:e1:8a:3a:e8:
        eb:e7:19:fd:58:f5:6a:d8:40:fb:cf:54:84:cd:4f:8e:62:95:
        c4:a4:a6:c4:cd:73:ed:2d:01:5c:5e:11:70:37:91:a1:cb:3c:
        cb:80:0f:ca:a4:da:a2:e8:7a:d8:30:f1:ff:9d:5c:cf:9d:01:
        57:ad:cf:bf:7e:9e:53:84:69:ce:17:1a:8c:eb:f7:5c:55:92:
        37:ed:e8:0e:22:d9:76:bf:5f:d5:f5:c7:f8:8b:bf:a3:05:a1:
        cf:9a:c1:fe:fe:92:07:33:48:78:dc:bd:8c:e0:db:dd:f0:20:
        7c:cc:74:1d:a7:e4:85:3b:03:93:5d:63:0f:bf:43:8b:df:47:
        2b:a7:1d:75:f9:df:bd:71:75:a2:f2:26:da:6e:af:39:70:52:
        f0:e5:f0:51:00:7a:44:85:1f:6e:fa:06:0d:1b:dd:5c:75:8f:
        83:13:eb:50:ef:4b:16:d3:5f:02:19:3d:bd:a7:c9:9b:0d:18:
        8c:bd:d3:ec:b1:c2:6b:f7:b7:a3:33:9e:f4:64:fd:0d:6e:37:
        39:a5:b0:98:c0:d5:2e:9e:bd:e1:46:99:c7:a4:9a:94:cc:48:
        bc:cd:23:66:1f:dd:46:00:c0:38:0c:3f:31:85:f4:d9:ed:04:
        52:b6:c2:4f:1b:71:f9:63:df:30:3f:3d:29:ba:75:ac:75:d8:
        31:1c:34:b8:1e:d1:93:5f:3b:c1:3a:57:be:2e:27:7b:0b:96:
        75:89:17:72:5d:0a:e2:06:59:7e:91:fb:25:cc:e2:81:21:f4:
        b6:02:f2:9b:68:c6:fc:cc:79:e4:8d:d0:fd:16:89:c9:64:5f:
        50:83:67:e9:7d:b3:9d:b6:49:2c:84:d7:f6:ec:3b:cf:31:09:
        b6:b0:65:1b:ee:f4:db:d0:dd:56:09:8c:a8:58:24:9d:d0:f2:
        e0:c6:2e:81:30:24:0b:31:92:26:87:f2:18:f9:63:a3:16:8c:
        a3:06:66:0f:ac:85:9a:ad:97:43:44:fb:aa:4c:0d:dc:b9:60:
        4e:b3:10:7b:a4:df:de:d3:c5:df:7c:b4:a1:bb:7f:3e:93:4b:
        dc:45:25:de:28:3c:5f:80:b5:6a:0d:91:0e:24:ca:fd:77:a7:
        1b:85:db:7a:15:b7:fd:8f:70:29:8d:11:29:eb:8f:b0:76:6a:
        4f:e4:92:12:8e:48:1b:97:db:cc:08:a3:db:33:c1:1f:d2:1c:
        a0:c3:ad:39:8d:fb:5c:cc:fe:d8:8b:4a:a1:46:0b:bc:48:ac:
        1c:4f:f3:44:37:f5:97:90:fc:48:5e:4a:eb:e7:38:b9:3d:bb:
        6b:27:0a:61:61:34:60:51:28:58:bd:22:a0:e1:9c:21:95:f3:
        b8:c9:05:7a:ed:f7:c6:64:b9:eb:08:39:58:bb:e7:be:66:8c:
        de:f3:9f:1c:4a:fd:c3:b9:a5:df:fc:19:92:37:d4:41:13:7c:
        1f:33:e7:1e:4d:5c:e0:73:a0:ca:f8:b3:ea:35:b6:00:2a:b8:
        27:73:3e:87:48:1a:ee:01:15:25:17:e2:5b:9c:89:2c:a0:56:
        52:63:10:64:9f:78:e9:67:a3:79:7a:5c:4e:75:75:18:46:64:
        27:47:7b:f0:56:d5:c7:61:90:b0:ae:f6:a4:af:3e:51:8e:66:
        74:be:ae:2c:eb:fa:dc:01:10:67:b3:07:23:ca:17:82:0d:88:
        3f:68:62:52:f3:1d:40:a6:b6:e9:aa:a0:6c:07:92:c0:55:75:
        4b:54:fa:bc:a9:0b:d7:a6:fa:21:2d:bd:db:2f:b4:31:d8:df:
        ea:6a:22:c0:22:bb:97:2a:a8:30:5a:3f:1a:fe:0d:6e:4b:aa:
        3e:57:b7:5d:77:9e:43:58:ea:28:7b:e0:fb:43:8c:62:39:9d:
        93:0f:9e:2c:2b:4b:8c:d9:fe:ba:25:82:97:a1:03:e5:79:8e:
        a4:0c:f0:01:c7:9a:09:01:3c:bd:51:a2:79:25:03:0e:3d:ec:
        57:25:60:ec:fa:a3:97:09:61:49:34:c0:8f:46:91:2c:20:63:
        ae:3c:7a:fb:19:bd:cc:5f:cf:fd:7c:f4:17:aa:7b:e3:1d:eb:
        dd:ce:d4:77:ad:25:76:7d:8b:38:43:a1:26:1d:bf:ad:56:4a:
        2f:2b:d8:6e:91:dc:70:38:10:c1:a5:06:ff:5c:ce:6f:4c:b6:
        d6:5c:a7:0a:7c:d9:58:68:17:ef:2d:fd:7e:4f:84:3c:37:cf:
        c4:99:d0:c1:5c:9c:c1:c5:09:70:df:25:66:21:f1:b0:6a:5b:
        aa:4c:24:73:37:86:c0:09:48:75:ca:12:79:6b:f5:85:b7:fb:
        89:10:5e:ca:fd:b6:7e:c9:20:52:69:35:47:0a:5c:82:17:b5:
        41:a6:44:59:23:06:56:f0:4a:45:99:fa:a9:dd:94:19:73:a2:
        60:49:04:a9:5c:43:c0:92:5f:0b:c5:f9:54:20:51:5b:e2:d3:
        f9:49:72:93:a8:a1:58:f6:b0:34:f0:cd:f6:12:56:2f:2a:ca:
        5e:b8:66:7b:7f:1b:33:91:4d:b5:9a:8d:1a:ec:71:30:cc:0d:
        4a:4c:9b:5e:ef:54:e4:15:28:fa:21:03:61:5b:79:6f:e9:44:
        d3:37:dc:66:a9:66:21:84:88:7f:a7:bb:2b:8f:b7:89:ad:ad:
        1f:74:05:e7:b1:ac:85:81:c8:53:e7:f2:47:f3:be:28:8c:66:
        7e:71:ef:14:0f:46:d5:5b:32:7d:f4:82:c4:4a:a2:1c:65:33:
        46:3f:8f:d3:32:da:a0:2e:c1:5b:37:f9:aa:4f:a3:32:1e:be:
        e1:6b:a6:6c:71:b0:05:5a:26:fa:2b:f3:f5:ec:af:d5:61:8a:
        4e:13:4b:d4:27:46:cb:4b:35:ba:4d:1e:da:45:ec:77:fd:fb:
        d6:ec:87:df:bf:68:b6:04:4e:2e:60:54:4a:d2:fd:81:b4:0f:
        0a:bc:39:24:c3:ec:29:8a:c5:6d:06:81:c6:21:51:f4:ea:7f:
        2f:0d:46:e7:35:9c:ce:6e:53:22:72:b7:55:ae:27:9d:c1:e9:
        0a:9a:ab:c4:b0:60:57:07:0a:7b:85:76:a5:67:8b:55:e9:d1:
        10:bf:3e:97:35:bf:fd:28:16:4d:36:49:d0:0c:08:b7:38:4c:
        4c:4b:0c:61:41:77:92:33:12:79:e5:c4:33:86:b8:a7:51:5b:
        ea:4e:3b:94:a3:71:3a:24:4a:6c:79:ee:aa:15:e8:0a:95:91:
        d5:be:35:c2:d1:5f:d2:c2:ca:6b:8a:be:d6:2b:18:30:e2:8b:
        8d:9e:b7:f7:26:80:73:f7:27:a7:93:f3:84:bc:39:e6:44:4f:
        4a:6d:0d:e4:c1:9c:ab:3e:69:c2:5c:82:ca:27:ef:e9:57:ad:
        c4:a5:99:28:10:48:39:ad:7b:de:1a:8a:c2:3c:5a:23:94:82:
        8f:53:0b:6d:4b:b5:86:e0:9d:cf:e9:6d:9b:17:5f:45:69:d5:
        10:6b:8e:3c:36:cc:0a:8b:c9:a7:5e:a6:28:4e:a2:85:6c:98:
        9c:44:c0:30:ee:68:1c:40:b3:f3:31:d4:5e:36:3c:fd:70:8f:
        4a:b4:f6:18:d8:96:d1:16:24:48:e6:7e:37:95:c5:68:a7:3e:
        3b:1e:7b:23:7a:92:59:d6:20:e4:6f:4f:81:a0:5e:7e:44:9a:
        f2:fa:7e:88:78:b0:1e:e7:37:69:38:1c:7d:71:5b:2e:c8:cd:
        fa:08:2e:55:38:ba:b7:02:60:f8:16:bb:c3:4e:90:44:d4:91:
        be:5e:3e:04:6d:b7:53:3a:72:95:a7:1c:54:77:18:20:21:33:
        40:43:49:54:5c:5e:7a:a4:a6:aa:ab:b7:c1:c8:d5:dc:e5:e7:
        ef:09:10:47:7b:a1:ac:e5:10:16:19:31:3d:55:5b:76:78:79:
        91:96:a3:a9:b0:e1:e3:fb:01:14:24:29:3b:50:53:70:74:82:
        88:89:8e:9d:b5:d7:fc:00:00:00:00:00:00:00:00:00:00:00:
        00:00:00:00:17:1e:30:41
```

## Get the standalone MTC as PEM

This command uses curl inside `nginx:stable` to connect to `nginx-mtc-acme` and
print the served standalone MTC certificate as PEM. The `--insecure` flag is
used because stock TLS clients do not yet validate MTC proof signatures as a
traditional X.509 chain.

```sh
docker run --rm --network mtc-demo nginx:stable \
  sh -lc 'curl --insecure --silent --show-error --fail \
    --write-out "%{certs}" --output /dev/null \
    https://nginx-mtc-acme.mtc-demo.test/ | \
    sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p"'
```

Sample PEM:

```pem
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
```

OpenSSL text form:

```sh
docker run --rm --network mtc-demo nginx:stable \
  sh -lc 'curl --insecure --silent --show-error --fail \
    --write-out "%{certs}" --output /dev/null \
    https://nginx-mtc-acme.mtc-demo.test/ | \
    sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" | \
    openssl x509 -noout -text'
```

Sample `openssl x509 -text` output:

```text
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 9 (0x9)
        Signature Algorithm: 1.3.6.1.4.1.44363.47.0
        Issuer: 1.3.6.1.4.1.44363.47.1=1.3.6.1.4.1.44363.47.42.1
        Validity
            Not Before: May 15 19:15:19 2026 GMT
            Not After : May 22 19:15:19 2026 GMT
        Subject: CN=nginx-mtc-acme.mtc-demo.test
        Subject Public Key Info:
            Public Key Algorithm: ML-DSA-44
                ML-DSA-44 Public-Key:
                pub:
                    ba:9f:6e:96:f7:b1:2e:30:2e:85:21:aa:28:af:7a:
                    bf:30:78:b6:23:f5:98:90:e8:c5:06:8f:2f:c0:b9:
                    74:e7:c9:6d:73:dc:2f:b6:62:d9:d9:ab:9c:31:82:
                    cf:94:cf:24:6b:84:5a:7d:22:b4:d4:a6:66:dd:48:
                    14:7e:ee:68:d0:5a:f0:d5:0e:d1:07:8a:4c:09:ee:
                    7b:97:a5:14:b5:6c:f4:f9:fd:5e:1b:6e:78:91:42:
                    ed:79:a9:a7:76:be:4c:33:d3:30:99:a9:c0:15:54:
                    89:b9:4d:ff:5b:9d:00:8e:8d:3d:dd:ab:a1:09:59:
                    e2:be:ad:39:8c:ed:b0:69:ee:6a:01:67:54:1b:ef:
                    8f:96:99:64:4d:5d:0c:11:55:f2:9c:c4:ab:f4:29:
                    78:50:aa:d6:2b:12:ec:8f:19:cb:27:65:9c:11:b2:
                    4c:54:0f:5e:c7:bb:84:0e:fc:d4:c3:e6:53:eb:bc:
                    21:b1:4b:7b:bd:ce:a1:d4:0b:c8:0a:de:43:15:3f:
                    f4:27:61:b6:94:75:6b:1f:43:b9:11:d9:43:f8:2c:
                    a1:a8:3b:65:75:75:47:d8:b9:15:98:98:9f:80:82:
                    46:00:6a:ec:ee:58:cc:4d:e9:67:4a:3a:66:07:3c:
                    72:b1:77:ae:41:3a:09:84:43:52:10:14:dd:09:c9:
                    3d:87:e2:3a:57:b0:9e:47:43:7f:e3:de:67:e4:61:
                    c9:76:e9:a4:84:87:ae:2d:0d:49:be:34:b5:65:88:
                    60:58:0f:d5:07:05:68:5f:07:f7:4c:8c:d6:69:d5:
                    1c:76:4f:4e:b3:83:5a:e6:33:cc:8d:c5:bc:b7:1f:
                    1e:4a:4b:09:1a:b7:e4:9b:7a:1f:f1:03:44:6c:ec:
                    29:e5:2c:57:cb:f9:bb:e8:6a:e9:3a:c5:25:68:c2:
                    3a:bd:9e:2a:53:1a:4b:9c:61:d5:07:9b:f7:5c:98:
                    78:02:86:7b:5b:64:df:e4:21:ea:35:90:24:67:73:
                    57:cb:87:84:86:3f:91:3c:ea:27:5c:f1:90:76:73:
                    03:aa:da:d4:07:be:96:b9:11:ff:e5:e2:a8:d2:93:
                    c9:97:0a:20:22:2c:e7:61:e7:bc:59:5a:d8:09:6a:
                    c4:5f:e8:57:e9:cf:7d:23:65:09:0b:19:b1:c2:5f:
                    b2:94:6d:b8:d2:39:09:78:1a:31:9b:a4:2a:eb:de:
                    ef:58:92:8e:36:a5:8a:24:95:e9:14:ac:3e:cc:a0:
                    aa:f4:33:4c:4b:ba:72:f3:84:a8:c2:b1:53:2d:bb:
                    b8:f4:6c:1c:2b:42:6e:fd:7d:d2:6c:7b:72:af:f7:
                    45:5f:ff:d6:13:c1:35:3c:b5:c6:24:6e:fd:8b:03:
                    b0:ab:f4:b8:da:aa:05:87:1e:39:be:3a:8c:39:c8:
                    37:96:cf:ad:8d:3d:e8:42:97:73:7b:45:9f:f1:23:
                    9b:e1:1b:01:fa:1a:24:46:0f:c5:52:95:ba:c1:83:
                    54:59:62:ca:83:59:27:3a:88:24:8b:26:29:2d:21:
                    56:f9:3e:7b:ca:83:71:ff:50:3a:f1:14:09:7c:3a:
                    73:41:13:bf:66:5f:85:ea:fa:3d:12:e3:6b:82:83:
                    e3:51:82:2c:e0:61:b3:be:ec:03:10:90:d3:78:04:
                    f2:a1:ab:6a:60:a6:47:e0:7e:eb:cb:ac:c4:80:94:
                    e9:46:5c:1c:6f:d9:0a:93:b0:ed:86:f4:31:e1:74:
                    56:f3:71:9c:6a:7d:ec:e7:ed:8c:c1:a6:2d:7c:a7:
                    57:05:40:81:00:df:e6:de:dd:20:9c:64:ca:e7:90:
                    a4:d4:49:f2:f1:96:8c:67:79:a5:50:ea:6d:6e:04:
                    f0:ca:95:7b:a3:2b:b2:99:53:9c:08:88:e2:48:98:
                    2e:ff:80:2e:bd:7c:ed:19:85:41:ed:66:fa:8d:e9:
                    e0:3f:ca:c6:f7:6a:02:6e:50:56:b3:84:67:01:ea:
                    b5:b7:27:19:bc:af:ee:af:34:c3:a9:23:bc:72:17:
                    68:8c:a4:23:14:be:6e:ff:24:6f:0b:74:1d:27:e8:
                    8b:50:e6:4f:b5:e7:e5:5d:54:de:e8:05:cb:1b:3c:
                    dd:71:3b:a3:c1:ca:6d:eb:af:a2:ae:64:06:52:be:
                    af:7c:c7:30:0a:4e:ae:89:4b:26:e4:58:e1:6e:05:
                    3b:b3:10:c2:4a:73:7f:05:96:25:b2:ed:12:c5:da:
                    69:05:8e:9f:6e:fc:f5:75:c5:d9:cd:9a:6b:51:48:
                    e6:78:b6:37:6a:b6:2e:ea:4b:92:07:c8:cf:76:ca:
                    ba:ab:69:a6:df:11:22:6e:0d:88:fe:ae:6e:36:aa:
                    b5:29:6b:25:82:42:78:da:09:9c:83:b2:ba:59:14:
                    fd:8d:d1:16:54:d1:7d:cb:9f:4b:f3:7e:8e:09:37:
                    64:0e:cf:36:83:05:2f:b8:af:21:1a:e0:df:5b:f0:
                    eb:01:59:25:82:96:69:f8:15:9d:b8:8d:1e:33:f3:
                    7b:6d:3d:49:16:ca:b9:8e:69:78:95:e4:98:09:05:
                    3e:62:6c:45:d8:6c:df:dd:02:b9:c0:58:2b:80:a8:
                    56:b0:d8:54:66:38:85:dd:a5:89:65:fe:cd:6d:24:
                    8f:bc:5d:3d:e5:7f:e8:b9:30:15:f8:96:8d:05:7d:
                    ee:37:43:e1:be:da:89:78:7c:46:7f:4d:cf:b5:28:
                    6f:a0:78:eb:8c:f4:df:62:78:b6:c3:9b:ce:28:7a:
                    e0:10:35:f9:57:1c:30:b4:0c:18:10:1f:65:26:a1:
                    bb:10:b9:7e:6b:62:df:76:4b:47:e8:32:9f:67:18:
                    0e:58:14:af:d5:5c:cf:b7:32:c1:29:84:db:ca:64:
                    8c:3b:2c:24:b7:55:be:b8:8a:c6:5e:44:2e:8b:5e:
                    f3:06:1b:62:72:06:86:b9:17:fb:ec:52:05:7a:7b:
                    2c:8d:05:56:26:92:85:e5:92:9e:f7:88:1d:6e:c8:
                    85:65:c6:4f:1a:9e:ea:b8:40:31:60:8a:38:6f:bd:
                    b0:f2:57:6f:18:55:66:10:33:38:38:1a:2a:a4:94:
                    a1:dd:65:df:0f:82:d5:e0:a2:18:6e:c0:67:64:62:
                    a0:03:d0:81:27:65:99:04:16:0b:fc:b0:b5:f4:1c:
                    c6:33:b4:44:06:e5:20:a0:9a:83:bd:39:91:33:cb:
                    91:48:fe:df:7c:83:5e:28:e8:cc:16:b4:89:94:7a:
                    13:ea:7d:f8:92:4d:d5:9f:54:c8:95:a9:26:d6:f7:
                    04:e6:af:99:02:6b:32:80:2a:2f:87:05:07:ee:8d:
                    3d:93:26:69:39:f0:69:00:5f:5d:62:ca:65:8a:d8:
                    7d:a0:ac:4a:a7:ed:56:03:84:6c:8f:63:98:8f:1f:
                    97:49:c5:18:d8:c9:7f:fb:f6:88:d4:4d:b0:e9:29:
                    fa:94:38:8c:8e:1f:73:18:ed:a2:bb:ea:dd:63:04:
                    6b:0c:da:e2:fa:f8:1c:ca:12:62:b2:78:25:1b:06:
                    0f:f6:04:16:94:1e:6f
        X509v3 extensions:
            X509v3 Subject Alternative Name:
                DNS:nginx-mtc-acme.mtc-demo.test, DNS:localhost
    Signature Algorithm: 1.3.6.1.4.1.44363.47.0
    Signature Value:
        00:00:00:00:00:00:00:09:00:00:00:00:00:00:00:0a:00:00:
        09:93:1c:31:2e:33:2e:36:2e:31:2e:34:2e:31:2e:34:34:33:
        36:33:2e:34:37:2e:34:32:2e:31:2e:63:61:09:74:6c:14:67:
        5c:63:b1:76:5d:4b:5b:42:b6:97:47:4e:4c:42:6a:f3:f7:f7:
        c5:f6:ca:ba:37:79:06:38:51:62:55:0f:f3:25:0f:f8:e7:1a:
        be:28:56:04:9c:be:7d:56:3e:86:66:dc:59:41:c7:35:b7:e7:
        ac:06:02:ae:4f:e0:4d:01:3e:44:c3:0a:ae:b7:0f:73:ae:4f:
        49:2b:d9:1f:a0:c4:ea:27:09:ef:19:da:e2:80:6a:9e:49:ff:
        98:5b:63:f2:85:df:65:d9:82:f8:d2:85:41:3c:e7:43:e9:5c:
        4c:be:75:f8:64:69:ae:7f:0d:5c:e5:e5:ed:52:07:c0:15:7f:
        aa:bf:c0:9a:86:ff:94:7a:5f:a4:20:3a:ce:66:c3:ac:4e:ff:
        78:81:65:3e:f7:ed:24:5e:86:a3:51:a1:e5:71:29:69:9c:bc:
        e5:36:d3:39:78:94:b9:a1:e0:63:e0:98:1a:b4:04:13:f4:ea:
        25:69:77:74:c8:5e:54:1b:bb:cc:f0:4c:bd:e6:7d:9c:c4:c5:
        bf:d3:c6:45:6c:64:80:8e:0a:ec:a5:16:e7:7a:24:0f:ca:cb:
        cd:97:f7:c6:b4:cc:6b:a0:04:5a:18:1a:39:89:f5:1b:51:b8:
        5e:6b:16:ed:10:59:64:a7:94:23:f7:1f:0e:8f:70:ae:cd:98:
        0a:ee:97:0d:44:9e:10:fe:63:73:a9:9d:46:31:75:0a:ea:c8:
        df:6d:d3:e2:cc:20:69:c6:e3:0f:69:d5:64:45:46:ef:ae:34:
        48:8d:64:60:81:db:b9:5e:a3:a1:f2:f0:e3:df:52:b7:a9:55:
        f6:88:fd:09:a9:e2:11:cc:00:0a:03:c3:73:2e:2c:99:04:95:
        9d:be:3b:3c:42:3e:64:45:c5:58:1b:1b:6c:c4:14:85:71:56:
        23:1b:8f:74:d6:90:0d:15:aa:f3:e2:a7:9b:08:9a:82:21:6c:
        69:f1:e0:da:61:3c:50:bd:08:cc:6b:4a:f6:aa:9e:33:7a:d5:
        b9:36:ad:dc:d1:6d:db:f5:ee:24:2d:15:1d:56:46:02:9b:c0:
        20:3c:0d:d6:62:ef:19:ad:da:9e:3b:65:63:c7:d9:8e:95:67:
        03:07:bb:61:b6:19:d9:c6:7f:54:c3:7c:bd:72:ef:12:7f:c5:
        7e:27:d1:50:4c:06:98:67:f8:a4:e6:11:27:19:bf:49:5c:b7:
        88:dc:6b:84:d2:ac:c1:e1:c6:7c:b4:d2:a8:18:59:5a:89:0e:
        5e:d9:66:f3:52:b2:1f:b2:75:06:0b:c1:c9:c6:d6:44:ed:6f:
        a7:1f:b7:15:49:12:0a:af:be:b2:41:e6:a5:d1:53:d1:0d:7a:
        7d:f9:ed:71:77:9f:14:50:57:ad:d9:b6:77:cd:c3:6d:d9:b5:
        5b:e5:61:e3:28:69:07:46:d3:f3:64:23:b7:8f:6b:90:4a:d4:
        c9:ca:9f:a0:ab:20:ff:e0:79:46:48:87:24:69:8c:3e:c2:6c:
        6e:09:f2:17:6a:43:ab:1c:ff:4a:29:f2:91:c3:90:0f:b7:e8:
        37:2d:e9:e4:df:33:c0:08:42:13:36:65:39:f9:6f:2c:f1:b8:
        09:59:58:ca:0f:4d:bc:e1:ed:0a:3a:97:b7:5f:b9:1c:ae:bd:
        df:01:d0:0e:d7:83:1f:a3:93:b9:dd:5f:7a:2c:f9:92:97:1d:
        bf:f2:63:f2:fb:60:d6:28:5b:65:eb:0c:c2:dd:d6:6f:9c:e4:
        5e:a6:6a:9a:37:1d:e9:cc:16:bc:6a:43:66:7d:13:df:ca:ed:
        c5:d7:dd:91:12:e4:1e:c7:c0:e0:35:e3:63:88:68:ab:c6:a9:
        e8:e7:00:a9:19:8f:fa:00:64:2c:02:f1:61:9a:18:55:9a:e4:
        31:da:62:f4:39:c5:a0:06:87:a1:32:e3:9c:a7:ca:39:ad:f0:
        ba:24:c5:79:cb:77:d5:7b:71:69:a4:2c:19:bf:75:dd:cb:b6:
        21:2a:fa:c2:c1:cd:9b:85:88:bf:df:69:a2:c8:de:6c:d7:8d:
        fa:fc:00:b5:f4:20:40:b9:a9:8c:b1:f4:55:a3:a9:cd:04:a2:
        24:a7:a9:20:b1:46:e4:7f:ed:95:27:21:07:a1:01:d6:22:83:
        6f:1c:70:7a:16:f8:bb:10:80:80:33:cb:b7:b2:28:83:b8:f3:
        e5:de:a5:76:d2:60:1e:66:26:a2:46:8f:e8:bc:36:99:15:bc:
        42:da:9f:50:17:7f:36:b1:07:fa:31:db:d0:15:5e:1b:4d:15:
        57:f2:61:0a:9f:00:36:41:df:d1:e2:8e:17:9b:b2:2b:aa:0a:
        77:65:69:eb:65:53:f0:e7:a8:2c:56:5f:88:70:88:41:73:fe:
        d8:8a:42:93:6a:49:dd:44:02:fa:84:82:38:79:45:e7:5f:62:
        2c:2c:06:56:25:f6:b5:1d:09:4a:2b:b4:c5:3d:97:ad:b8:a2:
        43:f3:63:99:37:67:68:fe:4b:3b:8b:a1:fb:fd:66:54:e9:ab:
        44:e4:39:82:34:16:06:49:c8:3e:99:b8:ea:4e:93:80:7e:8d:
        7e:d2:88:87:ca:b6:6a:b9:ff:0b:6d:2a:0f:c7:6c:14:e7:4f:
        a5:1a:41:3b:f5:86:62:5f:77:07:30:ad:9f:13:40:36:49:de:
        e9:44:1e:c5:64:2a:be:ce:5f:c0:cc:e8:42:28:2a:11:3e:b3:
        0b:cc:38:35:b9:df:84:84:65:86:96:49:2b:6c:0e:9f:cb:ed:
        a7:f4:69:ce:d9:7a:02:2a:a5:17:a3:43:3b:80:b0:ba:58:92:
        4a:37:e0:1e:40:43:5e:5e:c4:c3:6b:6d:1d:be:5b:30:21:bc:
        1a:1c:8a:db:c8:d3:0d:43:46:2f:2f:1a:0b:e0:7f:22:62:bd:
        da:72:c4:b5:ac:ce:de:63:61:1b:41:1b:f7:bb:ae:da:7b:8a:
        b3:8b:5a:fc:25:71:b0:b1:49:a0:7c:7b:2d:03:2d:d7:9b:6f:
        e5:dd:e8:dc:92:cd:c9:de:b5:41:aa:79:2a:24:19:52:53:39:
        95:a0:d0:00:dc:ae:9c:10:89:67:e0:10:39:65:37:38:1e:e6:
        20:3d:b5:31:03:85:b2:53:a5:3d:4d:3d:ba:5b:0d:04:d6:72:
        0e:dc:4f:38:d3:42:b9:f8:6d:d3:8f:05:7c:f8:c6:26:de:ee:
        b0:a3:70:d9:b8:81:a4:77:a5:97:c0:26:89:ce:40:96:45:c1:
        0a:c5:45:4d:0a:8b:d3:41:ba:82:db:63:4f:b8:29:75:f6:b2:
        14:df:f2:15:08:8a:96:cb:3e:7f:1c:0f:4a:59:64:af:04:a4:
        3c:a8:d6:c3:33:a9:b2:16:eb:b2:4a:07:42:e9:20:e7:93:cd:
        74:ea:1d:33:84:81:e0:f5:4e:cc:6c:af:8f:81:61:fb:08:15:
        ed:b4:4e:78:20:7a:06:03:64:b7:cc:a5:e5:cd:87:55:7f:66:
        33:11:f8:ed:52:12:55:ed:10:ae:15:c9:6d:7f:cf:ac:c6:c3:
        49:51:44:72:a7:8e:b3:85:86:37:81:7e:21:02:b4:12:57:a3:
        16:c7:fa:27:69:45:86:ac:a1:49:bc:aa:05:5c:e5:fb:6b:7e:
        78:08:2a:4b:3f:7e:ea:46:fb:0b:16:ed:c5:72:f2:9d:b0:4d:
        da:ee:87:3f:e0:a6:34:76:e9:94:46:8e:eb:02:e0:e1:19:f2:
        9b:ef:c1:12:69:a7:64:28:bd:f9:e8:18:fa:07:03:2e:db:5d:
        d5:6b:13:88:26:cc:73:10:9c:ad:4f:3d:b3:f0:af:b3:39:29:
        e6:19:e0:f1:3c:32:03:c2:21:1e:e1:88:5f:07:ef:f5:4f:75:
        58:b4:f8:85:1d:13:08:6d:17:f4:cd:b4:0f:9d:91:22:ed:43:
        77:e1:72:44:8a:c0:f0:be:3a:c4:1d:1f:02:d6:fa:94:f1:5a:
        f7:2c:9b:f8:01:11:fa:70:de:6a:f2:50:65:bd:cd:26:f8:d9:
        0c:de:b1:5f:97:82:23:94:e2:2a:a8:c0:46:fc:c3:58:b3:d9:
        17:8b:41:e0:24:ca:22:2d:20:ba:00:ad:e0:73:e9:d3:c2:b7:
        2d:77:20:da:4c:c2:c0:81:4a:63:58:95:9d:8a:71:c9:23:a0:
        51:d6:f5:be:dd:c8:a0:74:06:1b:bc:33:10:24:c6:1a:69:52:
        81:ab:51:9a:8b:1a:5b:60:9b:87:a0:f8:fb:c5:33:a0:a6:14:
        a5:95:4a:38:3d:79:23:70:19:eb:3b:cd:63:46:da:a3:a2:8e:
        a1:69:b8:09:18:bc:54:9d:6d:e8:db:79:7a:e1:b3:e5:8e:90:
        53:fe:41:47:8e:a7:81:70:50:45:49:67:4b:f2:e8:9f:e4:63:
        02:c9:97:da:35:c7:13:83:e3:f4:81:99:5d:82:1d:25:3a:73:
        83:7e:cd:a6:ca:67:51:fa:d6:82:13:92:da:e6:f8:4e:e0:33:
        d4:69:b8:f1:eb:f4:74:09:e5:88:3f:5c:3a:ac:db:8b:f0:11:
        6d:9d:ca:79:55:99:a6:3a:99:b8:e9:ce:75:85:f4:9f:90:c2:
        d7:a3:e3:da:7b:9c:34:cf:a8:b6:e4:99:c3:ea:9f:f2:73:5d:
        c9:32:bf:8a:b1:8b:2e:9a:e6:90:a5:b1:77:20:4e:2c:9f:91:
        1b:db:6c:94:0f:ea:1c:32:36:d5:9a:08:ec:71:3a:cc:b5:bc:
        bf:9c:e7:da:97:cd:fc:4d:f8:f8:22:b5:12:38:9b:4f:13:a3:
        79:f6:33:c4:d1:9a:89:a5:56:8f:7f:04:16:b7:0b:21:62:f8:
        ef:94:83:cf:76:c0:9b:11:a7:9a:56:5a:ef:f6:b7:70:82:fc:
        a0:3e:63:52:ca:7f:00:52:43:bc:dd:33:b3:69:8b:75:7a:a0:
        0c:29:d3:b0:cf:e1:1c:ce:96:f1:1f:a9:b7:34:44:e1:03:96:
        0d:82:67:99:a2:97:81:f8:b1:f5:f6:7c:1a:3e:5e:1e:7e:05:
        7d:42:fb:37:8a:98:30:29:ae:16:c6:d9:76:74:2a:6a:16:74:
        a1:b2:dc:d2:7c:f7:09:40:c6:3d:d8:75:fa:ff:04:68:c6:8a:
        2f:28:21:9c:42:c5:3b:0d:77:d5:1f:7d:e3:7e:aa:72:93:01:
        4c:bd:61:23:7b:09:a8:56:2c:15:e8:9f:1b:90:73:d9:c0:53:
        a2:84:16:a0:6c:3a:40:71:05:b9:e1:5f:56:05:96:bf:ae:2d:
        26:3f:fb:a1:62:d1:4f:b1:64:9a:90:74:06:4b:bb:31:2f:e5:
        9b:67:19:fb:84:1b:96:6f:c1:b2:10:b7:3b:d8:07:c6:b4:a5:
        64:8f:5e:ed:6f:d5:d3:49:81:19:a9:4c:99:13:94:e8:c8:9a:
        98:3c:54:ac:5b:5a:1e:e1:d1:3c:37:67:35:32:cd:03:05:b9:
        ef:4c:5e:ab:12:c6:05:db:ba:bb:d6:21:a1:11:86:3c:a7:50:
        fa:5f:0f:b4:c6:99:49:6a:5c:a9:2f:f8:c5:d1:37:1f:3b:ab:
        c4:db:27:2c:d6:7d:da:01:fd:44:9f:67:74:0e:30:b7:1d:2e:
        63:65:d4:7a:84:86:39:1d:72:eb:2c:b5:bc:3d:5d:d6:98:fb:
        1d:83:81:0b:38:d8:9b:56:9b:b6:bd:6c:07:d5:aa:d2:ab:65:
        f6:c6:c9:85:74:2a:cd:ac:4a:01:55:21:a6:5d:23:20:19:40:
        20:ec:f6:6d:b1:64:92:06:ec:6b:4e:c8:a2:8d:65:c1:50:56:
        ff:e7:2b:60:8d:46:63:b7:7a:1e:a8:18:6a:1c:79:70:05:d4:
        2b:d0:94:13:5f:19:14:f6:b4:f4:28:57:11:a8:f4:f2:51:94:
        5a:a5:44:97:2e:fc:8d:80:00:33:d5:f9:bd:6b:a3:f4:9c:40:
        47:9e:41:56:5d:78:34:b4:74:81:e4:84:eb:57:ed:d5:14:70:
        45:f8:aa:d5:18:db:70:f2:2f:60:1d:c2:d1:a6:e3:ba:5e:7d:
        82:92:9c:b5:26:85:f9:61:c1:84:83:c1:6a:01:58:21:e7:03:
        cd:35:96:3b:4e:a8:ed:0e:0d:c9:dd:db:6b:82:66:7e:98:fd:
        86:36:f3:7f:3c:42:d4:78:b3:bc:a8:a4:79:eb:eb:e4:93:52:
        47:29:b7:2c:75:25:86:3b:04:ad:e8:2c:a7:39:f7:ca:6f:4e:
        7b:49:42:ef:ec:8f:ef:3d:a9:e1:0a:02:09:1e:20:24:29:40:
        4f:52:66:72:7d:a0:b6:d1:01:09:0f:1b:20:28:36:37:42:43:
        47:48:51:6a:72:77:7e:8e:93:9d:a0:a9:b1:be:c5:da:e2:03:
        0d:0e:11:12:1d:2d:45:4c:5c:76:85:ac:0d:1b:3c:5a:62:80:
        a3:b6:c0:d0:da:e6:f0:f5:00:00:00:00:00:00:00:00:00:00:
        00:0f:2a:37:45
```

## What to Compare

The ordinary ML-DSA certificate from `nginx-mldsa` has:

```text
Signature Algorithm: ML-DSA-44
Public Key Algorithm: ML-DSA-44
Issuer: CN=nginx-mldsa demo root
```

The standalone MTC from `nginx-mtc-acme` has:

```text
Signature Algorithm: 1.3.6.1.4.1.44363.47.0
Public Key Algorithm: ML-DSA-44
```

That signature algorithm OID is the Cactus MTC proof marker. The certificate is
still encoded as an X.509 certificate and is served by stock NGINX, but the
signature value carries the MTC proof data rather than a normal issuer signature.

[mtcs]: https://datatracker.ietf.org/doc/draft-ietf-plants-merkle-tree-certs/
[transparency]: https://certificate.transparency.dev/
[diginotar]: https://security.googleblog.com/2011/08/update-on-attempted-man-in-middle.html
