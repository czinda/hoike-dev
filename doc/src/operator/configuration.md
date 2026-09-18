# Configuration Reference

hoike is configured with a single TOML file, loaded once at startup. The default path is `/etc/hoike/hoike.toml`; override it with `--config`:

```sh
hoike serve --config /path/to/hoike.toml
```

Configuration is read from the file only — there is **no** environment-variable layering or `HOIKE_*` override mechanism. The only two values that may come from the environment are named *by* the config: the HSM PIN (`signing_key.pin_env`) and the directory bind password (`source.bind_password_env`). Each names an environment variable to read; no other key has an environment override.

Every table below is parsed with `deny_unknown_fields`: an unrecognized or misspelled key is a **hard startup error**, not a silently ignored value. Run `hoike check --config <file>` to validate a file before deploying it.

---

## `[server]`

Top-level server settings that control the process mode, listener, and request limits.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mode` | string | `"edge"` | Operating mode: `"signer"`, `"edge"`, or `"combined"`. See [Signer](signer.md), [Edge](edge.md), and [Combined](combined.md) mode pages. |
| `listen` | string | `"0.0.0.0:2560"` | Socket address for the plaintext OCSP HTTP listener. Port 2560 is the IANA-assigned port for OCSP over HTTP. The OCSP data plane is plaintext by design — every response is signed end to end. |
| `max_request` | integer | `8192` | Maximum OCSP request body size in bytes. Protects against oversized or malformed requests. |
| `admin_listen` | string | — | Dedicated listener for the admin API and web UI, e.g. `"127.0.0.1:2561"`. When unset the admin API rides `listen` for backward compatibility and `hoike check` warns. See [TLS and Mutual TLS](tls.md). |
| `admin_tls` | table | — | `{ cert, key, client_ca }` for the admin listener. Requires a build with `--features tls` **and** `admin_listen` set; startup fails otherwise. `client_ca` enables mutual TLS. |
| `metrics_listen` | string | — | Dedicated listener for Prometheus `/metrics`, e.g. `"127.0.0.1:9184"`. Requires `--features metrics` to expose data; otherwise returns 503. |
| `metrics_tls` | table | — | `{ cert, key, client_ca }` for the metrics listener. Requires `--features tls` and `metrics_listen`. |
| `admin` | table | — | Operator accounts and session settings; see [`[server.admin]`](#serveradmin). |
| `webui` | table | — | `{ static_dir }` to serve the web UI from a directory instead of the embedded build (`--features embed-webui`). Omit to disable the UI. |

```toml
[server]
mode           = "edge"
listen         = "0.0.0.0:2560"
max_request    = 8192
admin_listen   = "127.0.0.1:2561"
metrics_listen = "127.0.0.1:9184"

[server.admin_tls]
cert      = "/etc/hoike/tls/admin.crt"
key       = "/etc/hoike/tls/admin.key"
client_ca = "/etc/hoike/tls/mgmt-ca.pem"
```

### `[server.admin]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `session_ttl_secs` | integer | `3600` | Fixed lifetime of a login session, in seconds. There is no idle timeout. |
| `operators` | array of tables | `[]` | Named operator accounts. Each has `name`, `password_hash` (bcrypt), and `role` (`"viewer"`, `"operator"`, or `"administrator"`; default `"viewer"`). |

```toml
[server.admin]
session_ttl_secs = 900

[[server.admin.operators]]
name          = "alice"
password_hash = "$2b$12$…"
role          = "administrator"
```

There are no built-in accounts. See [Admin API and RBAC](../security/admin-api.md) for roles and login limits.

### Mode validation

`mode` determines which code paths are active:

- **`signer`** — reads revocation sources, produces ahu bundles, does **not** serve OCSP queries.
- **`edge`** — serves pre-signed responses from bundles, holds **no** private keys.
- **`combined`** — runs both signer and edge in one process.

hoike validates mode-specific constraints at startup. `signer` and `combined` require every `[[ca]]` to have both a `source` and a `signing_key`. `nonce_policy = "live"` is only meaningful where a signing key is present.

---

## `[storage]`

Paths and limits for bundle storage and persistent state.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `bundle_dir` | string | **required** | Directory where ahu bundles are stored. The signer writes here; the edge reads from here. |
| `state_db` | string | `"/var/lib/hoike/state"` | Path to the persistent state database. Stores epoch high-water marks for anti-rollback protection. **This path must survive restarts** — losing it resets rollback protection. See [Anti-Rollback Protection](anti-rollback.md). |
| `max_chain` | integer | `24` | Maximum number of delta bundles in a chain before the edge demands a full bundle. |
| `seal_trust_anchors` | array of strings | — | Paths to DER/PEM CA certificates. A bundle seal is accepted if its signer certificate was **directly issued** by one of these anchors. |
| `seal_signer_pins` | array of strings | — | Paths to exact seal-signer certificates (PEM or DER). A seal is accepted if its certificate matches one of these byte for byte. |
| `seal_authorizations` | array of tables | `[]` | `[[storage.seal_authorizations]]` entries with `producer_id`, `issuer_key_hash`, and `signer_sha256` restricting which trusted signer may seal which scope. When any entry exists, every scope needs a matching one. |

When neither `seal_trust_anchors` nor `seal_signer_pins` is set, seal enforcement is **disabled** and bundles load with a warning. Every edge that receives bundles from another machine must set one of them. See [Seal Trust Policy](seal-trust.md).

```toml
[storage]
bundle_dir = "/var/lib/hoike/bundles"
state_db   = "/var/lib/hoike/state"
max_chain  = 24
```

> **Operational note:** Back up `state_db` alongside your bundle directory. If `state_db` is lost, the node cannot detect rollback or fork attacks until it re-establishes its high-water marks from a trusted source.

---

## `[gossip]`

SWIM gossip protocol settings for edge fleet coordination. Gossip provides membership tracking, generation announcements (new bundles), and urgent revocation notices. See [Gossip Configuration](gossip.md) for a deep dive.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | boolean | `false` | Enable or disable gossip. Set to `false` for air-gap/enclave deployments. See [Air-Gap Deployments](air-gap.md). |
| `bind` | string | `"0.0.0.0:7946"` | UDP/TCP address for the SWIM protocol listener. |
| `seeds` | array of strings | `[]` | Initial seed nodes for cluster join. Format: `"hostname:port"`. |
| `identity_key` | string | — | Path to this node's Ed25519 PKCS#8 private key. When set, generation and urgent-revocation broadcasts from this node are signed. |
| `peer_identities` | table | `{}` | Map of peer `node_name` → path of that peer's Ed25519 public key. When **non-empty** (enforcing mode), unsigned, forged, or misattributed broadcasts are dropped before re-propagation. When empty (permissive mode), unsigned broadcasts are accepted. |
| `peer_keys` | array | — | **Rejected.** A non-empty value fails startup with an error directing you to `peer_identities`. |
| `node_name` | string | `$HOSTNAME` or `"hoike-node"` | Node identifier used in membership and as the key in peers' `peer_identities` maps. Must be unique in the fleet. |

```toml
[gossip]
enabled      = true
bind         = "0.0.0.0:7946"
seeds        = ["edge-a.pki.example:7946", "edge-b.pki.example:7946"]
identity_key = "/etc/hoike/gossip/edge-01.key"
node_name    = "edge-01"

[gossip.peer_identities]
"edge-02"  = "/etc/hoike/gossip/edge-02.pub"
"signer-1" = "/etc/hoike/gossip/signer-1.pub"
```

Signing authenticates broadcast **origin**; SWIM liveness traffic (pings/acks) is not authenticated and nothing on the gossip channel is encrypted. Gossip never carries certificate status data.

### Disabling gossip

For air-gap or single-node deployments, disable gossip entirely:

```toml
[gossip]
enabled = false
```

When gossip is disabled, bundles must be delivered out-of-band (removable media, admin API upload, or a scheduled file copy). See [Air-Gap Deployments](air-gap.md).

---

## `[[ca]]`

Each `[[ca]]` section configures one CA whose certificates this responder handles. hoike supports multiple `[[ca]]` sections for multi-CA deployments. Requests are routed to the correct CA by `issuerKeyHash` (and `issuerNameHash`) lookup. See [Multi-CA Routing](multi-ca.md).

### Identity and routing

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `label` | string | **required** | Unique, non-empty label for this CA. Used in logs, metrics, and bundle filenames, so it may not be `.`, `..`, or contain `/` or `\`. |
| `bundle_file` | string | — | Explicit path to this CA's ahu bundle. When omitted, the edge locates the bundle within `bundle_dir` by `label`. |
| `issuer_name_hash` | string (hex) | — | Hex-encoded `issuerNameHash` for explicit routing. When absent it is extracted from the loaded bundle manifest. |
| `issuer_key_hash` | string (hex) | — | Hex-encoded `issuerKeyHash` for explicit routing. When absent it is extracted from the loaded bundle manifest. |
| `source` | table | required for signer/combined | Revocation data source. See [Source types](#source-types). |

### Signer identity inputs

Signer and combined nodes need the issuer DN and public key to compute each response's `CertID`. Supply them base64-encoded; they are decoded on load.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `issuer_name_der_b64` | string (base64) | — | DER of the issuer Distinguished Name. |
| `issuer_key_bytes_b64` | string (base64) | — | Raw issuer public-key bytes. |

### Signing key

The `[ca.signing_key]` table configures how OCSP responses are signed. Required for `signer` and `combined` modes. Three types:

**File-based (PKCS#8):**
```toml
[ca.signing_key]
type = "file"
path = "/etc/hoike/ocsp-signing.key"  # PKCS#8 PEM or DER
```

**PKCS#11 HSM** (requires `--features pkcs11`):
```toml
[ca.signing_key]
type        = "pkcs11"
module      = "/usr/lib/libCryptoki2_64.so"   # Vendor PKCS#11 library
token_label = "hoike-partition"                # Token/partition name
key_label   = "ocsp-signing"                   # CKA_LABEL of the signing key
pin_env     = "HOIKE_HSM_PIN"                  # Read PIN from env var
# Omit pin/pin_env and hoike prompts interactively at startup
```

**Demo key** (testing only — refuses to run in production intent):
```toml
[ca.signing_key]
type = "demo"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `sig_alg` | string | `"ecdsa-p256"` | Signature algorithm: `"ecdsa-p256"`, `"ml-dsa-44"`, `"ml-dsa-65"`, or `"ml-dsa-87"`. Any other value is a startup error. `nonce_policy = "live"` is not yet supported with ML-DSA. |
| `responder_cert` | string | — | Path to the delegated OCSP signing certificate (DER or PEM). Embedded in each `BasicOCSPResponse.certs` per RFC 9919 §3.2.2. When set, `ResponderID` uses the cert's SPKI key hash. |
| `seal_key` | string | — | Path to a PKCS#8 key for CMS bundle seal signing. SHOULD differ from the OCSP signing key. Falls back to the signing key (with a warning) when absent. See [Seal Trust Policy](seal-trust.md). |
| `seal_cert` | string | — | Path to the seal signer's certificate. |

### CertID compatibility

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `certid_compat` | string | `"dual"` | CertID hash coverage baked into produced bundles. `"dual"` indexes each response by **both** SHA-256 and SHA-1 `issuerKeyHash` (for clients that still send SHA-1) — this doubles the manifest entry count. `"sha256"` indexes by SHA-256 only; `"sha1"` by SHA-1 only (not recommended). Any other value is a startup error. |

### Nonce handling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `nonce_policy` | string | `"ignore"` | `"ignore"` omits the nonce from responses (appropriate for pre-signed). `"forward"` proxies nonce-bearing requests to a signer. `"live"` signs a fresh response with the client's nonce on every request (needs a signing key). See [Nonce Policies](nonce-policies.md). |
| `forward_to` | string | — | URL of the signer to forward nonce-bearing requests to. **Required** when `nonce_policy = "forward"`. Must be `https://` unless `forward_insecure` is set; redirects are not followed. |
| `forward_insecure` | boolean | `false` | Permit an `http://` `forward_to` target. Lab use only; logged at startup. |
| `forward_ca` | string | — | Accepted but **not yet applied** to the outbound client: the forward target is validated against the system trust store. Install a private CA system-wide instead. `hoike check` prints this caveat. |

### Timing and batch production

All timing keys are **integer seconds**, matching `session_ttl_secs`.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `validity_secs` | integer | `86400` | Response validity window (`nextUpdate − thisUpdate`), in seconds. Determines how long a cached response remains valid. |
| `batch_interval` | integer | `3600` | How often (seconds) the signer produces a new batch. The **signer outage budget** is roughly `validity_secs − batch_interval`: if the signer is down longer, edges begin serving expired responses. |
| `jitter_secs` | integer | `7200` | Upper bound of randomized jitter added to `nextUpdate` so a fleet's responses do not all expire simultaneously (thundering-herd avoidance). Bounded by the source's own `nextUpdate`. |
| `max_age_fraction` | float | `0.5` | Fraction of a response's validity window advertised as the edge's HTTP `Cache-Control: max-age`. Must be in the range `(0, 1]`; any other value is a startup error. |
| `urgent_revocation` | boolean | `true` | When `true`, the signer produces an off-cycle bundle **immediately** on detecting a newly revoked certificate, instead of waiting for the next `batch_interval`. The off-cycle run emits a `signer_generation` audit event with `trigger = "urgent"`. |
| `archive_cutoff_secs` | integer | `0` (disabled) | Drop entries for certificates that expired more than this many seconds ago, bounding bundle size. **Requires per-certificate `notAfter`, which only the 389 DS syncrepl source supplies — it is a no-op for CRL sources**, and `hoike check` warns if you set it on a CRL-backed CA. Entries with unknown expiry are never dropped, so a revoked certificate can never silently degrade to "unknown". |

### Completeness

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `completeness` | string | `"partial"` | Declares whether the producer asserts a complete directory enumeration for this CA. `"partial"` (default) means the bundle covers only the certificates it lists. `"authoritative-complete"` may only be produced from a proven full directory snapshot (389 DS syncrepl after a complete refresh); it is metadata on the bundle, not a serve-time switch. |

> **Serve-time semantics.** Regardless of `completeness`, a serial with **no entry** in the loaded bundle is answered `unauthorized` — the edge never fabricates a `good` for an unknown serial. `completeness` governs which bundles the *signer* is permitted to stamp as authoritative-complete, not whether the *edge* invents statuses.

### Source types

The `[ca.source]` table specifies where revocation data comes from.

**CRL source** (implemented):

```toml
[ca.source]
type        = "crl"
path        = "/var/lib/hoike/crls/enterprise.crl"
issuer_cert = "/etc/hoike/trust/enterprise-ca.crt"
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Must be `"crl"`. |
| `path` | string | Path to the CRL file (DER or PEM). Re-read at each batch interval and on an admin-triggered signing run; there is no file watcher. |
| `issuer_cert` | string | Certificate of the CRL issuer, used to verify the CRL signature and issuer binding. Independently provisioned trusted configuration, not discovered from the CRL. |

Only complete, direct CRLs signed with ECDSA P-256, RSA PKCS#1 v1.5 (SHA-256/384/512), or ML-DSA are accepted. CRL sources carry no per-certificate expiry, so `archive_cutoff_secs` has no effect on them. See [Revocation Sources](revocation-sources.md).

**Dogtag syncrepl source** (requires `--features dogtag-sync`):

```toml
[ca.source]
type              = "dogtag-sync"
ldap_url          = "ldaps://ds.pki.example:636"
base_dn           = "ou=certificateRepository,ou=ca,o=pki-iot-ca-CA"
bind_dn           = "uid=hoike-reader,ou=people,o=pki-iot-ca-CA"
bind_password_env = "HOIKE_LDAP_PASSWORD"
tls               = "ldaps"
ca_cert           = "/etc/hoike/tls/ds-ca.pem"
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Must be `"dogtag-sync"`. |
| `ldap_url` | string | LDAP URL for the Dogtag 389 DS instance. |
| `base_dn` | string | Search base for the certificate repository. |
| `bind_dn` | string | Bind DN (default `cn=Directory Manager`). |
| `bind_password` | string | Bind password (prefer `bind_password_env`). |
| `bind_password_env` | string | Env var containing the bind password. |
| `cookie_path` | string | Path to checkpoint the sync cookie (default: `state_db`-relative). Population and cookie are checkpointed together. |
| `filter` | string | LDAP filter (default `(objectClass=certificateRecord)`). |
| `tls` | string | `"ldaps"`, `"starttls"`, or `"none"` (default, for backward compatibility). Use `ldaps` or `starttls` in production; StartTLS upgrades before the bind. |
| `ca_cert` | string | PEM CA bundle used to validate the directory server's certificate instead of the system roots. |

This source uses RFC 4533 Content Synchronization (syncrepl). It enumerates all issued certificates, supplies each certificate's `notAfter` (enabling `archive_cutoff_secs`), and — after a proven complete refresh — enables `authoritative-complete` bundles.

### Key rotation

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `key_rotation.renew_before_days` | integer | `7` | Days before cert expiry to trigger a rotation warning. |
| `key_rotation.check_interval_hours` | integer | `1` | Hours between rotation checks. |
| `key_rotation.rotation_command` | string | — | Shell command to execute when rotation is needed. Receives the CA label and cert path as arguments. |

```toml
[ca.key_rotation]
renew_before_days    = 7
check_interval_hours = 1
rotation_command     = "/usr/local/bin/renew-ocsp-cert.sh"
```

### Full example (signer with HSM)

```toml
[[ca]]
label                = "enterprise-issuing-01"
nonce_policy         = "live"
completeness         = "authoritative-complete"
issuer_name_der_b64  = "MEUx…"   # DER of the issuer DN, base64
issuer_key_bytes_b64 = "A0IA…"   # issuer public-key bytes, base64

[ca.source]
type              = "dogtag-sync"
ldap_url          = "ldaps://ds.pki.example:636"
base_dn           = "ou=certificateRepository,ou=ca,o=pki-ca-CA"
bind_password_env = "HOIKE_LDAP_PASSWORD"
tls               = "ldaps"

[ca.signing_key]
type           = "pkcs11"
module         = "/usr/lib/libCryptoki2_64.so"
token_label    = "hoike-partition"
key_label      = "ocsp-signing"
pin_env        = "HOIKE_HSM_PIN"
sig_alg        = "ecdsa-p256"
responder_cert = "/etc/hoike/ocsp-signing.pem"

[ca.key_rotation]
renew_before_days = 7
rotation_command  = "/usr/local/bin/renew-ocsp-cert.sh"
```

---

## Validation rules

hoike validates the configuration at startup (and under `hoike check`) and exits with a descriptive error if any rule is violated. Beyond `deny_unknown_fields` (any unknown key fails), the enforced rules are:

| Rule | Error (abridged) |
|------|------------------|
| `admin_tls` or `metrics_tls` set on a binary built without `--features tls` | *TLS configured but this binary was built without the tls feature* |
| `admin_tls` set without `admin_listen` | *admin_tls requires admin_listen; refusing plaintext management fallback* |
| `metrics_tls` set without `metrics_listen` | *metrics_tls requires metrics_listen* |
| `gossip.enabled` with a non-empty `peer_keys` | *replace gossip.peer_keys with peer_identities …* |
| Empty, reserved, path-bearing, or duplicate `label` | *CA labels must be unique nonempty file names* |
| `forward_to` not `https://` (and not `forward_insecure` + `http://`) | *forward_to requires https:// (or explicit forward_insecure for http://)* |
| Invalid `sig_alg` | *invalid sig_alg … expected one of: ecdsa-p256, ml-dsa-44, ml-dsa-65, ml-dsa-87* |
| ML-DSA `sig_alg` with `nonce_policy = "live"` | *nonce_policy=live is not yet supported with … signing* |
| Invalid `certid_compat` | *invalid certid_compat … expected one of: dual, sha256, sha1* |
| `max_age_fraction` outside `(0, 1]` | *invalid max_age_fraction … must be in the range (0, 1]* |
| signer/combined `[[ca]]` missing `source` | *has no source configured, required for … mode* |
| signer/combined `[[ca]]` missing `signing_key` | *has no signing_key configured, required for … mode* |
| signer/combined with no `[[ca]]` | *… mode requires at least one [[ca]] with a source* |

---

## Complete annotated example

```toml
# /etc/hoike/hoike.toml — Edge node serving two CAs with gossip

[server]
mode        = "edge"           # Keyless serving from pre-signed bundles
listen      = "0.0.0.0:2560"   # IANA-assigned OCSP port, plaintext by design
max_request = 8192

[storage]
bundle_dir = "/var/lib/hoike/bundles"   # Where ahu bundles are read from
state_db   = "/var/lib/hoike/state"     # Epoch high-water marks — MUST persist across restarts
max_chain  = 24
seal_trust_anchors = ["/etc/hoike/trust/producer-ca.pem"]  # Admit only sealed bundles from this CA

[gossip]
enabled      = true
bind         = "0.0.0.0:7946"
seeds        = ["edge-a.pki.example:7946", "edge-b.pki.example:7946"]
identity_key = "/etc/hoike/gossip/edge-01.key"
node_name    = "edge-01"

[gossip.peer_identities]
"edge-02"  = "/etc/hoike/gossip/edge-02.pub"
"signer-1" = "/etc/hoike/gossip/signer-1.pub"

# Enterprise issuing CA — CRL-based, pre-signed responses
[[ca]]
label          = "enterprise-issuing-01"
nonce_policy   = "ignore"        # Pre-signed — nonce omitted from responses
certid_compat  = "dual"          # Index by both SHA-256 and SHA-1 CertID hashes
validity_secs  = 86400           # 24h window; outage budget ≈ 86400 − 3600
batch_interval = 3600            # New batch hourly
jitter_secs    = 7200            # Up to 2h of expiry spread
completeness   = "partial"       # CRL may not list every certificate

[ca.source]
type        = "crl"
path        = "/var/lib/hoike/crls/enterprise.crl"
issuer_cert = "/etc/hoike/trust/enterprise-ca.crt"

# Partner issuing CA — nonces forwarded to a signer
[[ca]]
label            = "partner-issuing-01"
nonce_policy     = "forward"     # Proxy nonce-bearing requests to the signer
forward_to       = "https://signer.pki.example:2560"
certid_compat    = "sha256"      # Partner clients all support SHA-256
validity_secs    = 43200         # 12h
batch_interval   = 1800          # 30m
max_age_fraction = 0.5
completeness     = "partial"

[ca.source]
type        = "crl"
path        = "/var/lib/hoike/crls/partner.crl"
issuer_cert = "/etc/hoike/trust/partner-ca.crt"
```

---

## Environment variables

hoike reads exactly two values from the environment, both secrets that should not be written to the config file:

| Config key | Environment variable |
|------------|---------------------|
| `signing_key.pin_env` | the variable it names, holding the HSM PIN |
| `source.bind_password_env` | the variable it names, holding the directory bind password |

No other configuration key can be set or overridden from the environment. For per-instance settings in containers, template the config file or mount an instance-specific `hoike.toml`.
