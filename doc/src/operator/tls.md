# TLS and Mutual TLS

hoike applies TLS to its **management surfaces** and **inter-component channels**, not to the OCSP data plane. The OCSP listener (`server.listen`) serves plaintext HTTP by design: every response is signed end to end, RFC 6960 clients speak plaintext DER, and a transport wrapper there adds cost without adding a security property.

| Channel | Direction | TLS | Configured by |
|---------|-----------|-----|---------------|
| OCSP responses | inbound, `server.listen` | never | — |
| Admin API and web UI | inbound, `server.admin_listen` | server or mutual | `server.admin_tls` |
| Prometheus metrics | inbound, `server.metrics_listen` | server or mutual | `server.metrics_tls` |
| Nonce forwarding to an upstream responder | outbound | required (`https://`) | `[[ca]].forward_to` |
| 389 DS syncrepl | outbound | LDAPS or StartTLS | `[[ca]].source.tls` |

TLS support is a **build-time feature**. Build with `--features tls` (and `dogtag-sync` for LDAPS). A binary without the feature refuses to start if any TLS setting is present; it never silently falls back to plaintext.

## Admin listener

Bind the admin API and web UI to their own listener and give it a certificate. This is required for a trusted administrative path; without `admin_listen`, the admin API rides the plaintext OCSP port for backward compatibility and `hoike check` warns.

```toml
[server]
mode         = "edge"
listen       = "0.0.0.0:2560"        # OCSP, plaintext by design
admin_listen = "127.0.0.1:2561"      # or a management-network address

[server.admin_tls]
cert = "/etc/hoike/tls/admin.crt"    # PEM chain, leaf first
key  = "/etc/hoike/tls/admin.key"    # PKCS#8 or SEC1 PEM, mode 0600
```

### Mutual TLS

Set `client_ca` to require a client certificate. Clients must present a certificate that chains to one of the CAs in the bundle; connections without one are rejected at the handshake.

```toml
[server.admin_tls]
cert      = "/etc/hoike/tls/admin.crt"
key       = "/etc/hoike/tls/admin.key"
client_ca = "/etc/hoike/tls/mgmt-ca.pem"   # PEM bundle of client-issuing CAs
```

Mutual TLS authenticates the **connection**, not the operator. Operators still log in with `POST /session`; the client certificate is not yet mapped to an operator identity. Use both: mTLS keeps unauthenticated clients off the listener entirely, and the session login attributes actions to a named operator in the audit log.

### Metrics listener

The metrics listener follows the same shape. Leave it bound to a private address or terminate TLS on it:

```toml
[server]
metrics_listen = "127.0.0.1:9184"

[server.metrics_tls]
cert = "/etc/hoike/tls/metrics.crt"
key  = "/etc/hoike/tls/metrics.key"
```

## Protocol versions and ciphersuites

The listeners negotiate **TLS 1.3 and TLS 1.2 only**. TLS 1.0 and 1.1 are never offered. TLS 1.2 requires the Extended Master Secret extension.

Ciphersuites are supplied by the underlying crypto provider (currently `aws-lc-rs` via rustls). There is no configuration key to narrow them. See [FIPS 140-3 Status](../compliance/fips.md) for the planned move to the operating system's OpenSSL provider, which will place suite selection under the host crypto policy.

## Forward proxy

When a CA's `nonce_policy = "forward"`, nonce-bearing requests are proxied to `forward_to`. The target must be `https://`; `hoike check` refuses a cleartext URL. Redirects are not followed and upstream response bodies are read with an incremental bound.

```toml
[[ca]]
label        = "partner-ca"
nonce_policy = "forward"
forward_to   = "https://ocsp-signer.example.com:2560"
```

`forward_insecure = true` permits an `http://` target for lab use. It is logged at startup and must never be set in production.

> **`forward_ca` caveat.** The `forward_ca` key is accepted but not yet wired into the outbound client. The forward target is validated against the **system trust store**, so a private CA must be installed system-wide (for example under `/etc/pki/ca-trust/source/anchors/` followed by `update-ca-trust`). `hoike check` prints the same caveat.

## LDAPS and StartTLS for syncrepl

The `dogtag-sync` source supports three transport modes. The default is `"none"` for backward compatibility; production deployments should set `"ldaps"` or `"starttls"`.

```toml
[ca.source]
type              = "dogtag-sync"
ldap_url          = "ldaps://ds.pki.example.com:636"
base_dn           = "ou=certificateRepository,ou=ca,o=pki-ca-CA"
bind_dn           = "cn=hoike-reader,ou=people,o=pki-ca-CA"
bind_password_env = "HOIKE_LDAP_PASSWORD"
tls               = "ldaps"                      # "ldaps" | "starttls" | "none"
ca_cert           = "/etc/hoike/tls/ds-ca.pem"   # validate the directory's certificate
```

With `starttls`, the upgrade completes **before** the bind, so the bind password never crosses the wire in cleartext.

## What `hoike check` enforces

| Condition | Result |
|-----------|--------|
| `admin_tls` or `metrics_tls` set on a binary built without `tls` | startup error |
| `admin_listen` unset while `server.admin` is configured | warning: admin API on the plaintext OCSP port |
| `forward_to` is `http://` without `forward_insecure` | error |
| `forward_insecure = true` | warning, logged on every start |
| `forward_ca` set | warning: not applied; install the CA system-wide |
| `dogtag-sync` with `tls = "none"` | warning: bind credentials cross in cleartext |

## Certificate requirements

- Server certificates need `serverAuth` EKU and a SAN matching the address operators and scrapers connect to.
- Private keys must be readable only by the hoike user (`chmod 0600`).
- Client certificates for mTLS need `clientAuth` EKU and must chain to a CA in `client_ca`.
- hoike does not perform revocation checking on TLS peer certificates. Keep management-CA lifetimes short or rotate `client_ca` to revoke.
