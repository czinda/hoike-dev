# Configuration Reference

hoike is configured with a single TOML file, loaded once at startup. The default path is `/etc/hoike/hoike.toml`; override it with `--config`:

```sh
hoike serve --config /path/to/hoike.toml
```

Every key can also be set via environment variable using the `HOIKE_` prefix, double-underscore section separators, and uppercase names. For example, `server.listen` becomes `HOIKE_SERVER__LISTEN`. Environment variables take precedence over the config file.

---

## `[server]`

Top-level server settings that control the process mode, listener, and request limits.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mode` | string | **required** | Operating mode: `"signer"`, `"edge"`, or `"combined"`. See [Signer](signer.md), [Edge](edge.md), and [Combined](combined.md) mode pages. |
| `listen` | string | `"0.0.0.0:2560"` | Socket address for the HTTP listener. Port 2560 is the IANA-assigned port for OCSP over HTTP. |
| `max_request` | integer | `8192` | Maximum OCSP request body size in bytes. RFC 6960 POST bodies are typically small; RFC 9919 GET requests encode the request in the URL path and are capped at 255 bytes by the URI length constraint. This limit protects against oversized or malformed requests. |

```toml
[server]
mode   = "edge"
listen = "0.0.0.0:2560"
max_request = 8192
```

### Mode validation

`mode` is the single most important setting. It determines which code paths are active:

- **`signer`** — reads revocation sources, produces ahu bundles, does **not** serve OCSP queries.
- **`edge`** — serves pre-signed responses from bundles, holds **no** private keys.
- **`combined`** — runs both signer and edge in one process.

hoike validates mode-specific constraints at startup. For example, `nonce_policy = "live"` on an `edge` node is a fatal error (edge nodes have no signing keys).

---

## `[storage]`

Paths and limits for bundle storage and persistent state.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `bundle_dir` | string | `"/var/lib/hoike/bundles"` | Directory where ahu bundles are stored. The signer writes here; the edge reads from here. Must be readable (edge) or read-write (signer/combined). |
| `state_db` | string | `"/var/lib/hoike/state"` | Path to the persistent state database. Stores epoch high-water marks for anti-rollback protection. **This path must survive restarts** — losing it resets rollback protection. See [Anti-Rollback Protection](anti-rollback.md). |
| `max_chain` | integer | `24` | Maximum number of delta bundles in a chain before the edge demands a full bundle. Lower values increase bandwidth (more full bundles); higher values save bandwidth but increase recovery time after a missed delta. |

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
| `enabled` | boolean | `true` | Enable or disable gossip. Set to `false` for air-gap/enclave deployments. See [Air-Gap Deployments](air-gap.md). |
| `bind` | string | `"0.0.0.0:7946"` | UDP/TCP address for the SWIM protocol listener. |
| `seeds` | array of strings | `[]` | Initial seed nodes for cluster join. At least one seed must be reachable for a new node to join the fleet. Format: `"hostname:port"`. |
| `identity_key` | string | — | Path to the node's gossip identity key. All gossip messages are signed with this key. |
| `node_name` | string | hostname | Human-readable node identifier. Must be unique within the gossip cluster. Defaults to the system hostname if omitted. |

```toml
[gossip]
enabled      = true
bind         = "0.0.0.0:7946"
seeds        = ["edge-a.pki.example:7946", "edge-b.pki.example:7946"]
identity_key = "/etc/hoike/gossip.key"
node_name    = "edge-01"
```

### Disabling gossip

For air-gap or single-node deployments, disable gossip entirely:

```toml
[gossip]
enabled = false
```

When gossip is disabled, bundles must be delivered out-of-band (removable media, `hoike import`, or a scheduled file copy). See [Air-Gap Deployments](air-gap.md).

---

## `[[ca]]`

Each `[[ca]]` section configures one CA whose certificates this responder handles. hoike supports multiple `[[ca]]` sections for multi-CA deployments. Requests are routed to the correct CA by `issuerKeyHash` lookup. See [Multi-CA Routing](multi-ca.md).

### Identity and source

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `label` | string | **required** | Human-readable label for this CA. Used in logs, metrics, and bundle filenames. Must be unique across all `[[ca]]` sections. |
| `source` | inline table | **required** | Revocation data source. See [Source types](#source-types) below. |

### Signing

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `signing` | string | `"ca-direct"` | Signing mode. `"ca-direct"` signs with the CA's own key. `"delegated"` uses a separate OCSP responder certificate and key (requires `responder_cert` and `responder_key`). |
| `sig_alg` | string | `"ecdsa-p256"` | Signature algorithm. Supported values: `"ecdsa-p256"`, `"ecdsa-p384"`, `"ed25519"`, `"rsa-sha256"`, `"ml-dsa-44"`, `"ml-dsa-65"`, `"ml-dsa-87"`. |
| `responder_cert` | string | — | Path to the OCSP responder certificate. Required when `signing = "delegated"`. |
| `responder_key` | string | — | Path to the OCSP responder private key. Required when `signing = "delegated"`. |
| `responder_id` | string | `"by-key"` | ResponderID format in OCSP responses: `"by-key"` (SubjectPublicKeyInfo hash) or `"by-name"` (Distinguished Name). `"by-key"` is recommended — it survives certificate renewal. |

### CertID and compatibility

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `certid_compat` | string | `"dual"` | CertID hash algorithm compatibility. `"dual"` indexes responses by both SHA-256 and SHA-1 `issuerKeyHash` (for clients that still send SHA-1). `"sha256"` accepts only SHA-256. `"sha1"` accepts only SHA-1 (not recommended). |

### Nonce handling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `nonce_policy` | string | `"ignore"` | How to handle nonces in OCSP requests. `"ignore"` omits the nonce from responses (appropriate for pre-signed). `"forward"` proxies the request to the signer for a live-signed response with nonce. `"live"` signs a fresh response with nonce on every request (signer mode only). See [Nonce Policies](nonce-policies.md). |
| `forward_to` | string | — | URL of the signer to forward nonce-bearing requests to. **Required** when `nonce_policy = "forward"`. |

### Timing and batch production

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `validity` | duration string | `"24h"` | Response validity window (`nextUpdate − thisUpdate`). Determines how long a cached response remains valid. |
| `batch_interval` | duration string | `"1h"` | How often the signer produces a new batch of responses. The **signer outage budget** is `validity − batch_interval` — if the signer is down longer than this, edge nodes will begin serving expired responses. |
| `jitter` | duration string | `"2h"` | Random jitter added to `thisUpdate` to prevent response expiration thundering herds. Each response's `thisUpdate` is shifted by a random offset within `[0, jitter]`. |
| `max_age_fraction` | float | `0.5` | Fraction of remaining validity used for `Cache-Control: max-age`. A value of `0.5` means the `max-age` header is set to half the time remaining until `nextUpdate`. |
| `urgent_revocation` | boolean | `true` | When `true`, the signer produces an off-cycle delta bundle immediately upon detecting a new revocation, rather than waiting for the next `batch_interval`. |
| `archive_cutoff` | duration string | `"1y"` | How far back to keep responses for expired certificates. Certificates that expired more than this duration ago are dropped from bundles. |

### Completeness

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `completeness` | string | `"authoritative-complete"` | Declares whether this responder has complete revocation data for the CA. `"authoritative-complete"` means the responder is the authoritative source for this CA's revocation status — any certificate not found in the bundle is reported as `good`. `"partial"` means the responder only knows about certificates listed in a CRL — unlisted certificates return `unauthorized` (unknown). |

### Source types

The `source` field is an inline table that specifies where revocation data comes from.

**CRL source** (implemented):

```toml
source = { type = "crl", path = "/var/lib/hoike/crls/enterprise.crl" }
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Must be `"crl"`. |
| `path` | string | Path to the CRL file. hoike watches this path for changes and reloads automatically. |

**Dogtag source** (planned):

```toml
source = { type = "dogtag", url = "https://ca01.pki.example:8443", auth = "mtls", cert = "/etc/hoike/ra.pem" }
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Must be `"dogtag"`. |
| `url` | string | Dogtag CA REST API endpoint. |
| `auth` | string | Authentication method: `"mtls"`. |
| `cert` | string | Path to the client certificate for mTLS authentication. |

```toml
[[ca]]
label          = "enterprise-issuing-01"
source         = { type = "crl", path = "/var/lib/hoike/crls/enterprise.crl" }
signing        = "ca-direct"
sig_alg        = "ecdsa-p256"
responder_id   = "by-key"
certid_compat  = "dual"
nonce_policy   = "ignore"
validity       = "24h"
batch_interval = "1h"
jitter         = "2h"
archive_cutoff = "1y"
completeness   = "authoritative-complete"
```

---

## Duration strings

Duration values use a human-readable format: a number followed by a unit suffix.

| Suffix | Meaning | Example |
|--------|---------|---------|
| `s` | seconds | `"30s"` |
| `m` | minutes | `"15m"` |
| `h` | hours | `"24h"` |
| `d` | days | `"7d"` |
| `y` | years (365 days) | `"1y"` |

---

## Validation rules

hoike validates the configuration at startup and exits with a descriptive error if any rule is violated:

| Rule | Error |
|------|-------|
| `mode` is missing or not one of `signer`, `edge`, `combined` | `invalid server mode` |
| `nonce_policy = "live"` with `mode = "edge"` | `live nonce signing requires signer mode` |
| `nonce_policy = "forward"` without `forward_to` | `forward_to is required when nonce_policy = "forward"` |
| `signing = "delegated"` without `responder_cert` or `responder_key` | `delegated signing requires responder_cert and responder_key` |
| `batch_interval >= validity` | `batch_interval must be less than validity` |
| `max_chain < 1` | `max_chain must be at least 1` |
| Duplicate `label` across `[[ca]]` sections | `duplicate CA label` |
| `bundle_dir` does not exist or is not writable (signer/combined) | `bundle_dir is not writable` |
| `state_db` parent directory does not exist | `state_db path is invalid` |
| `gossip.enabled = true` without `identity_key` | `gossip identity_key is required when gossip is enabled` |

---

## Complete annotated example

```toml
# /etc/hoike/hoike.toml — Edge node serving two CAs with gossip

[server]
mode        = "edge"           # Keyless serving from pre-signed bundles
listen      = "0.0.0.0:2560"   # IANA-assigned OCSP port
max_request = 8192             # Max POST body; GET is path-limited to ~255 bytes

[storage]
bundle_dir = "/var/lib/hoike/bundles"   # Where ahu bundles are read from
state_db   = "/var/lib/hoike/state"     # Epoch high-water marks — MUST persist across restarts
max_chain  = 24                         # Accept up to 24 delta bundles before requiring a full

[gossip]
enabled      = true
bind         = "0.0.0.0:7946"
seeds        = ["edge-a.pki.example:7946", "edge-b.pki.example:7946"]
identity_key = "/etc/hoike/gossip.key"
node_name    = "edge-01"

# Enterprise issuing CA — CRL-based, pre-signed responses
[[ca]]
label          = "enterprise-issuing-01"
source         = { type = "crl", path = "/var/lib/hoike/crls/enterprise.crl" }
signing        = "ca-direct"
sig_alg        = "ecdsa-p256"
responder_id   = "by-key"
certid_compat  = "dual"          # Accept both SHA-256 and SHA-1 CertID hashes
nonce_policy   = "ignore"        # Pre-signed — nonce omitted from responses
validity       = "24h"           # Signer outage budget: 24h − 1h = 23h
batch_interval = "1h"
jitter         = "2h"
archive_cutoff = "1y"
completeness   = "authoritative-complete"

# Partner issuing CA — delegated responder, nonces forwarded to signer
[[ca]]
label          = "partner-issuing-01"
source         = { type = "crl", path = "/var/lib/hoike/crls/partner.crl" }
signing        = "delegated"
responder_cert = "/etc/hoike/partner-ocsp.pem"
responder_key  = "/etc/hoike/partner-ocsp.key"
sig_alg        = "ecdsa-p384"
responder_id   = "by-key"
certid_compat  = "sha256"        # Partner clients all support SHA-256
nonce_policy   = "forward"       # Proxy nonce-bearing requests to signer
forward_to     = "https://signer.pki.example:2560"
validity       = "12h"
batch_interval = "30m"
jitter         = "1h"
archive_cutoff = "6m"            # Partner certs are short-lived
completeness   = "partial"       # CRL may not list every certificate
```

---

## Environment variable overrides

Any configuration key can be overridden with an environment variable. The naming convention is:

```
HOIKE_<SECTION>__<KEY>
```

Double underscores separate section from key; single underscores within a key name are preserved.

| Config key | Environment variable |
|------------|---------------------|
| `server.mode` | `HOIKE_SERVER__MODE` |
| `server.listen` | `HOIKE_SERVER__LISTEN` |
| `storage.bundle_dir` | `HOIKE_STORAGE__BUNDLE_DIR` |
| `gossip.enabled` | `HOIKE_GOSSIP__ENABLED` |

Environment variables are useful for container deployments where the base config file is baked into the image and per-instance settings (like `node_name` or `listen`) vary.

> **Note:** `[[ca]]` array sections cannot be fully configured via environment variables due to TOML array-of-tables semantics. Use the config file for CA definitions.
