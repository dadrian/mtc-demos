# Server-side OpenSSL rejects leaf certificates with unknown signature algorithms

## Summary

OpenSSL appears to reject a configured server leaf certificate when the
certificate's `signatureAlgorithm` is unknown to OpenSSL, even though a TLS
server does not need to verify or otherwise process the signature on its own leaf
certificate in order to present it to clients.

This prevents server deployments from experimenting with or deploying new X.509
certificate signature algorithm identifiers before OpenSSL has native
recognition for those identifiers.

## Expected behavior

When OpenSSL is used by a TLS server to load and present a configured leaf
certificate and matching private key, OpenSSL should not reject that leaf
certificate solely because the certificate's outer `signatureAlgorithm` OID is
unknown or not mapped to a built-in digest/signature implementation.

The server-side requirements should be limited to checks such as:

- the certificate is syntactically valid DER/PEM
- the configured private key corresponds to the certificate's subject public key
- the key type is usable for TLS server authentication
- configured policy checks that are explicitly relevant to local server operation

The certificate signature itself is validated by the client as part of path
validation. If the client does not understand or accept the certificate's
signature algorithm, the client can reject the connection.

## Actual behavior

When loading a server leaf certificate whose `signatureAlgorithm` uses an
unrecognized OID, OpenSSL can reject the certificate during server configuration
loading with an error such as:

```text
SSL_CTX_use_certificate(...) failed (...:SSL routines::ca md too weak)
```

Lowering the OpenSSL security level can allow the server to load the
certificate, but that is a broad workaround. The issue is not that the
certificate uses a weak known digest; it is that the signature algorithm is not
understood locally by the server, even though the server does not need to verify
that signature.

## Why this matters

New certificate formats and signature algorithms often need to be tested in
staged deployments before every TLS library has first-class support for every
new algorithm identifier. A server should be able to present a certificate that
contains an experimental or newly assigned certificate signature algorithm, as
long as the server's own TLS signing key is supported.

Rejecting such a certificate at server load time couples server deployment to
client-side certificate path validation support. That makes incremental
experimentation and rollout harder than necessary.

## Suggested behavior

For server leaf certificates, OpenSSL should distinguish between:

- algorithms needed by the local endpoint to perform TLS operations, such as the
  subject public key algorithm and private key signing capability
- algorithms only needed by the peer for certificate validation, such as the
  leaf certificate's issuer signature algorithm

Unknown or unsupported algorithms in the second category should not by
themselves prevent `SSL_CTX_use_certificate` from loading the certificate for
server use.
