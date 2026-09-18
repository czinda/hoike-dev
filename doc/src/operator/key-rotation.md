# Key Rotation

hoike monitors OCSP signing certificate expiry and can automatically execute a renewal command when the certificate approaches its expiration date.

## Configuration

```toml
[[ca]]
label          = "enterprise-ca"
responder_cert = "/etc/hoike/ocsp-responder.pem"

[ca.key_rotation]
renew_before_days    = 7
check_interval_hours = 1
rotation_command     = "/usr/local/bin/renew-ocsp-cert.sh"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `renew_before_days` | integer | `7` | Days before cert expiry to trigger the renewal warning and rotation command |
| `check_interval_hours` | integer | `1` | Hours between rotation status checks |
| `rotation_command` | string | — | Shell command to execute when renewal is needed |

## How it works

At each signer batch interval, hoike:

1. Parses the `responder_cert` to extract `notBefore` and `notAfter`
2. Computes `expires_in_secs = notAfter - now`
3. Evaluates the rotation status:

| Status | Condition | Action |
|--------|-----------|--------|
| **Ok** | `expires_in_secs > renew_before_days * 86400` | Log info: "OCSP signing certificate valid" |
| **RenewSoon** | `0 < expires_in_secs <= renew_before_days * 86400` | Log warning + execute `rotation_command` |
| **Expired** | `expires_in_secs <= 0` | Log error: "OCSP signing certificate has EXPIRED" |

## Rotation command

The `rotation_command` is executed via `sh -c` when the certificate enters the `RenewSoon` window. It receives the CA label as context in the log. Typical implementations:

- Request a new certificate from the CA via EST or CMP
- Trigger a certmonger renewal
- Call an internal API to issue a new OCSP signing certificate
- Send an alert to the operations team

## Admin API

The rotation status for each CA is available via the admin API:

```
GET /api/admin/rotation
```

Returns a list of per-CA rotation statuses with `expires_in_secs` for dashboard display. The admin API also exposes `POST /api/admin/rotate/{label}` to manually trigger the rotation command.

## Certificate requirements

The OCSP signing certificate must:

- Have the `id-kp-OCSPSigning` Extended Key Usage
- Be issued by the CA it serves
- Include `id-pkix-ocsp-nocheck` extension (recommended)

hoike validates these properties and logs warnings when they are missing. Use `hoike check` to verify certificate configuration before deployment.
