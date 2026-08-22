# Local TLS Certificates

The repository no longer stores local development TLS keys or certificates.

If you need the widget/local web launch configuration that references
`widgets/localhost.crt` and `widgets/localhost.key`, generate them locally and
keep them untracked.

Example with OpenSSL:

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout widgets/localhost.key \
  -out widgets/localhost.crt \
  -days 365 \
  -subj "/CN=localhost"
```
