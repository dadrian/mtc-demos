# OpenSSL unknown leaf signature issue

Tracked upstream as [openssl/openssl#31195](https://github.com/openssl/openssl/issues/31195).

This affects the `nginx-mtc-acme` demo because its ACME-issued standalone MTC
leaf certificate uses an MTC proof signature OID that OpenSSL does not recognize
as a built-in certificate signature algorithm. Stock NGINX, through OpenSSL, can
therefore reject the configured server certificate at load time with:

```text
SSL_CTX_use_certificate(...) failed (...:SSL routines::ca md too weak)
```

The demo currently works around this by starting NGINX with an OpenSSL
configuration file selected through `OPENSSL_CONF` that lowers the OpenSSL
security level:

```text
CipherString = DEFAULT:@SECLEVEL=0
```

The NGINX `ssl_conf_command CipherString DEFAULT:@SECLEVEL=0;` directive alone
is not sufficient for this certificate-loading path; the OpenSSL configuration
has to be active when the OpenSSL library initializes.
