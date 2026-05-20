# Standalone MTC Demo

A standalone MTC, when consumed by a server, is very simple[^3]! Standalone
Merkle Tree Certificates (MTCs) look like ordinary X.509 certificates to the
software that serves them; the only difference is the `signatureAlorithm` OID.

Don't believe me? Well, let's define a couple requirements, and then go through
a few examples.

Certificates are relevant to _authenticating_ an HTTPS connection, meaning they
bind a public key to a name. For the public Web PKI, we also want an additional
property, _transparency_, meaning that there is cryptographic proof that every
certificate issued by a publicly trusted certification authority (CA) is
_publicly logged_. This means that the full set of publicly trusted certificates
at any time is known, and there are no "secret" certificates. Historically,
transparency has come from the [certificate transparency (CT)][transparency]
ecosystem. While not perfect, the existence of transparency is what prevents CAs
from being the highest-value target for attackers. For a maliciously-issued
certificate to be used to authenticate a website, it needs to be disclosed,
which ultimately reduces the efficacy of malicious issuance as an attack vector,
compared to [the before times][diginotar].

For HTTPS, there are effectively two options for post-quantum certificates:
- **Chonky X.509**, where we simply copy/paste key and signature algorithms from
  pre-quantum to post-quantum. Effectively, anywhere an RSA or ECDSA key or
  signature was used, we use an ML-DSA key or signature instead. Transparency
  would then be layered in via CT for the public PKI, but could be excluded for
  private PKIs where the issuer and authenticating party are the same. This is
  referred to as "chonky" because ML-DSA keys and signatures [are very
  big][dadrian-pqc-size], and the current approach to X.509 certificates with
  transparency involves transmitting five signatures and two public keys for
  every TLS connection.
- **Merkle Tree Certificates (MTCs)**, which are a mechanism for embedding
  [transparency information][transparency] directly into an X.509 certificate by making issuance be a signature over an inclusion proof in a merkle tree.

MTCs can technically be used with an key type, but for the purposes of this,
let's assume we're always talking about MTCs with ML-DSA, the post-quantum
signature algorithm. MTCs are still X.509 certificates, however the contents and
expectations around the signature algorithm used on the certificate change.

While an MTC CA needs to operate a merkle tree, which is outside the scope of
this demo, an MTC itself is just a certificate with a fancy signature algorithm.
MTCs come in two variants---the larger _standalone_ certificate, and smaller
_landmark-relative_ certificate. In both cases, the MTC part of the certificate
is entirely contained within the `signatureAlgorithm` field in the certificate.
The certificate is still X.509, and the key in the certificate of the end-entity
(i.e. the web server) is a normal ML-DSA key. For a server to use either form of
MTC to authenticate itself (assuming it has obtained one---more on that another
time), it just needs to be able to sign with the end-entity key. Servers don't
actually interact with the _signature_ from the CA!

Let's look at this from the clients perspective. First, back to chonky X.509.
What would the client need to verify a chonky X.509 ML-DSA certificate? Well,
the client would need some sort of representation of the trust anchor, probably
an X.509 root certificate in PEM format, to provide a root of trust. It also
needs to understand some new (relative to pre-quantum) algorithm identifier,
`id-ml-dsa-*`, and understand that identifier means "ML-DSA signature over the
certificate body", and its X.509 stack needs to be updated to know how to verify
a certificate using the indicated algorithm.

What about a standalone MTC? Well, once again, the client would need some sort
of representation on an MTC CA, likely an X.509 certificate in PEM format. It
also needs to understand some new (relative to pre-quantum) algorithm
identifier, `id-alg-mtcProof`, and understand that identifier means "signature
over an inclusion proof", and then its X.509 stack needs be updated to know how
to verify a certificate using the indicated algorithm.

You might notice that these are effectively the same requirements, the only
difference is _what_ algorithm is executed by the verifier in the X.509 stack.
For a Chonky X.509 certificate, the algorithm is "feed the bytes of the
certificate into ML-DSA Verify()". For a standalone MTC, the algorithm is "use
the inclusion proof and certificate body to construct a subtree hash, and then
feed bytes of the subtree hash into ML-DSA Verify()". For both Chonky X.509 and
Standalone MTCs, all of the information needed to verify the certificate is
contained in the value of the signature and indicated by the
`signatureAlgorithm`.  In both cases, the required update for the client is to a
speak a new signature algorithm, something that necessarily needs to happen
anyway to add support for PQC. And in both cases, the only data the client needs
to bootstrap the verification is an X.509 certificate to use as a trust anchor.

The situation is slightly more complicated for landmark-relative certificates or
cosigner-enforcing clients. We'll save that for another demo.

At this point, you might be lost, so let's look at two things:
1. Configuring a server and client to use a Chonk X.509 ML-DSA certificate and
  root
2. Configuring a server and client to use an MTC certificate and MTC CA

For both examples, we'll use NGINX as our web server with an out-of-the box
OpenSSL 3.5.

## Requirements

All the examples here are orchestrated with Docker Compose, so you'll need that
if you want to follow along in your terminal. The Docker network name (so the
containers can all talk to each other) is `mtc-demo`.

### Chonky X.509

Let's start out with Chonky X.509 without transparency. ML-DSA isn't defined
publicly trusted certificates, so we'll use our own [ML-DSA root
certificate](./nginx-mldsa/certs/root.key) as a trust anchor.

This is the baseline: an ordinary X.509 certificate, directly issued by a demo
root, where the leaf public key and certificate signatures are ML-DSA-44. This
is standard, but Chonky X.509 using ML-DSA signatures, without an intermediate
certificate.

#### 1. Start `nginx-mldsa`

```sh
docker compose -f nginx-mldsa/docker-compose.yml up -d
```

On first execution, the container creates a new ML-DSA-44 leaf at startup and
signs it with the committed ML-DSA-44 demo root, storing it in
`nginx-mldsa/certs`. Normally, this certificate would come from ACME or some
other mechanism for communicating with a CA. The scripting for issuing the
certificate isn't important---what's important is "how do we configure NGINX to
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
correct trust anchor. We know we verified the connection because the command
completed.

## Standalone MTC

Now let's do the same thing, but with a standalone MTC. OpenSSL doesn't have
built-in support to issue ML-DSA MTCs like it does for Chonky X.509 ML-DSA
certificates, so we'll additionally run a test MTC CA from Let's Encrypt called
Cactus[^1]. Since we're running the CA, we'll also show that we can use a
normal, out-of-the-box ACME client to request issuance of the standalone MTC.

```sh
docker compose -f mtc-ca/docker-compose.yml up -d
```

This starts Cactus with an [ML-DSA key as the root of
trust](./mtc-ca/keys/ca-cosigner.seed). The Cactus CA signs the MTC log state
with its committed ML-DSA-44 cosigner seed and exposes an ACME directory over
(non-PQC) HTTPS for local demo clients using the [ECDSA
root](./ecdsa-ca/root.crt)[^2].

\TODO: Update this to use the X.509 representation of an MTC CA

Successful output looks like:

```text
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

Now that the CA is running, let's start up an NGINX server that serves an MTC
issued by our MTC CA.

The `nginx-mtc-acme` container creates an ML-DSA-44 leaf key, builds a CSR, asks
Cactus for a standalone MTC over ACME using unmodified lego, writes the returned
PEM to its mounted state directory, and starts NGINX with that PEM.

Once again, this is effectively _the exact same flow_ you'd use with NGINX to
get a pre-quantum HTTPS certificate today.

We have a little bit of extra plumbing to provide the _local_ ACME server for
the purposes of the demo, but that's it.

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

Note that this time, we're passing `--insecure` to curl, because curl doesn't
yet support verifying a standalone MTC. But if it did, we'd remove `--insecure`
and pass `--cacert /path/to/mtc/root.pem`. Again, this would be the _exact same
setup_ we used for Chonky X.509, just with a different trust anchor.

\TODO: dadrian this would be more compelling if we could show it working with BoringSSL

### A side note about OpenSSL

I lied a little---we had to do a slight bit of [extra configuration for
OpenSSL](./nginx-mtc-acme/openssl-mtc.cnf). This is because OpenSSL currently
rejects unknown signature algorithms as "too weak" when operating as a server.
This doesn't make any sense because servers do not need to process or otherwise
interpret the signature algorithm from the CA. We have [filed a
bug](https://github.com/openssl/openssl/issues/31195) and expect it to be fixed
in OpenSSLs going forward, and backported to all stable branches.

## Certificate Comparison

Ok, so the server configuration looks like configuring any other server, and
configuring the client looks like configuring any other client. But isn't the
MTC itself super complicated?

Not really! Let's compare the Chonky X.509 certificate and the MTC. I've
commited two examples that'll I'll reference here, but if you're following
along, the byte sequences will be slightly different since the containers
generate new certificates at creation time.

### Chonky X.509

Let's get the PEM for server using Chonky X.509.

```sh
docker run --rm --network mtc-demo \
  -v "$PWD/nginx-mldsa/certs/root.crt:/root.crt:ro" \
  nginx:stable \
  sh -lc 'curl --silent --show-error --fail --cacert /root.crt \
    --write-out "%{certs}" --output /dev/null \
    https://nginx-mldsa.mtc-demo.test/ | \
    sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" | \
    tee demo-chonky.pem | \
    openssl x509 -text -noout
```
This writes the certificate to `demo-chonky.pem` and shows you the parsed
output. I've elided some of it here, but you can look at [the full
contents](./demos/chonky.pem).

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
# ... elided ...
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
# ... elided ...
        88:89:8e:9d:b5:d7:fc:00:00:00:00:00:00:00:00:00:00:00:
        00:00:00:00:17:1e:30:41
```

If you're not familiar with reading `openssl x509 -text` output, know that this
is a normal looking certificate, just with an (obnoxiously large) ML-DSA-44
signature, that I've elided so this page isn't absurdly long.

### Standalone MTC

What does the standalone MTC look like?

```sh
docker run --rm --network mtc-demo nginx:stable \
  sh -lc 'curl --insecure --silent --show-error --fail \
    --write-out "%{certs}" --output /dev/null \
    https://nginx-mtc-acme.mtc-demo.test/ | \
    sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" | \
    tee demo-standalone.pem | \
    openssl x509 -text -noout
```

This saves it to `demo-standalone.pem` and prints the text representation. Once again, I've included an elided version of it here:

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
# ... elided ...
                    0f:f6:04:16:94:1e:6f
        X509v3 extensions:
            X509v3 Subject Alternative Name:
                DNS:nginx-mtc-acme.mtc-demo.test, DNS:localhost
    Signature Algorithm: 1.3.6.1.4.1.44363.47.0
    Signature Value:
        00:00:00:00:00:00:00:09:00:00:00:00:00:00:00:0a:00:00:
        09:93:1c:31:2e:33:2e:36:2e:31:2e:34:2e:31:2e:34:34:33:
# ... elided ...
        a3:b6:c0:d0:da:e6:f0:f5:00:00:00:00:00:00:00:00:00:00:
        00:0f:2a:37:45
```

What's different from the Chonky X.509 certificate? Well, the issuer name is now also just an identifier, and the signature algorithm uses a different identifier than the Chonky certificate. Other than that, everything is the same. To be explicit, the Chonky X.509 ML-DSA certificate from `nginx-mldsa` has:

```text
Signature Algorithm: ML-DSA-44
Public Key Algorithm: ML-DSA-44
Issuer: CN=nginx-mldsa demo root
```

And the standalone MTC has:

```text
Signature Algorithm: 1.3.6.1.4.1.44363.47.0
Public Key Algorithm: ML-DSA-44
Issuer: 1.3.6.1.4.1.44363.47.1=1.3.6.1.4.1.44363.47.42.1
```

The difference is that the `Signature` field now carries an MTC proof, rather than "just" an ML-DSA signature over the bytes of the certificate. Here's the actual schema for the `Signature` fields

Chonky X.509:

```text
```

Standalone MTC:
```text
```

For a standalone MTC, everything needed to verify the MTC proof structure is contained in the X.509 representation of the MTC CA. So an MTC aware client effectively loops over the \TK structure in the MTC proof (i.e. the value of the `Signature` field in an MTC) to calculate a \TK, and then verifies the ML-DSA signature in \TK is over that hash, whereas in Chonky X.509 the client just verifies the ML-DSA signature is over the bytes of the certificate.

But in both cases, verification remains an algorithm who's inputs are a set of trust anchors, and the bytes of the certificate, and the output is a Yes/No.

Neat!

## But what about consigners!?!?!?!

Future demos to come! But you're right that we don't verify any of the
cosignatures here (and in fact, there aren't any!). That's because cosigners
only provide transparency, and the current state of the world is that clients
without log list or landmark distribution mechanisms don't really enforce
transparency. So neither does this demo. We expect the default behavior of
non-transparency enforcing verifiers to ignore cosignatures and just trust the
CA signature to mean that the CA did the right thing.

The point of this demo is to show that a standalone MTC is effectively as
achievable as Chonky X.509 for basic clients, with the exact same communication
paths from CA to server to client, and root store to client.

What we get from a standalone MTC is actually a greater commitment tha a normal
X.509 certificate with unverified SCTs---the CA operator would still need to
create a split view _just to issue the certificate_, whereas dummy (or no SCTs)
could be provided to non-transparency-enforcing clients currently in conjunction
with "just" a signature from a trusted CA.

[mtcs]: https://datatracker.ietf.org/doc/draft-ietf-plants-merkle-tree-certs/
[transparency]: https://certificate.transparency.dev/
[diginotar]: https://security.googleblog.com/2011/08/update-on-attempted-man-in-middle.html
[dadrian-pqc-size]: https://dadrian.io/blog/posts/pqc-signatures-2024/

[^1]: Technnically we're running my fork of Cactus to make it play nice for this demo, but the point stands.
[^2]: We're using a local root here so the ACME clients can still have an HTTPS
  URL. We're using ECDSA because ML-DSA support (and MTC support) is obviously not
  yet widely available in clients.
[^3]: The Paxos algorithm, when presented in plain English, is very simple.
