# Multi-CA Routing

A single hoike responder can serve OCSP responses for many CAs simultaneously. Routing is based on the `issuerKeyHash` field inside each OCSP request's CertID structure, so no URL-path conventions or virtual hosts are needed — one listen address serves all CAs.

## How Routing Works

Every OCSP request contains a **CertID** with three fields:

- `hashAlgorithm` — the hash used (SHA-1, SHA-256, etc.)
- `issuerKeyHash` — hash of the issuing CA's public key
- `serialNumber` — the certificate's serial number

At startup, hoike builds an **issuerKeyHash multimap** from all configured `[[ca]]` sections. Each CA's public key is hashed (using the algorithms specified by `certid_compat`) and inserted into the map.

When a request arrives:

1. Extract the `issuerKeyHash` from the CertID.
2. Look up matching CA(s) in the multimap.
3. Within the matched CA's ahu bundle, binary-search the sorted index for the `serialNumber`.
4. Return the pre-signed response, or `unauthorized` if no match is found.

```text
Request CertID
  issuerKeyHash ──► multimap lookup ──► CA's ahu bundle
  serialNumber  ──────────────────────► binary search ──► response
```

## Configuring Multiple CAs

Add one `[[ca]]` section per CA. Each section is independent — it has its own revocation source, signing configuration, batch schedule, and nonce policy.

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

[[ca]]
label          = "device-ca"
source         = { type = "crl", path = "/var/lib/hoike/crls/device.crl" }
signing        = "delegated"
responder_cert = "/etc/hoike/device-responder.pem"
responder_key  = "/etc/hoike/device-responder.key"
sig_alg        = "ecdsa-p384"
responder_id   = "by-key"
certid_compat  = "sha256"
nonce_policy   = "ignore"
validity        = "12h"
batch_interval  = "30m"

[[ca]]
label          = "legacy-root"
source         = { type = "crl", path = "/var/lib/hoike/crls/legacy-root.crl" }
signing        = "ca-direct"
sig_alg        = "ecdsa-p256"
responder_id   = "by-key"
certid_compat  = "sha1"
nonce_policy   = "ignore"
validity       = "48h"
batch_interval = "4h"
```

The `label` field is a human-readable identifier used in logs and metrics. It must be unique across all `[[ca]]` sections.

## Re-keyed CAs

When a CA is re-keyed — new key pair, same subject name — the old and new keys produce **different `issuerKeyHash` values**. Certificates issued under the old key will have requests with the old hash; certificates under the new key will use the new hash.

Configure both as separate `[[ca]]` entries:

```toml
[[ca]]
label  = "enterprise-issuing-01-2023"
source = { type = "crl", path = "/var/lib/hoike/crls/enterprise-2023.crl" }
# ... old key's signing config

[[ca]]
label  = "enterprise-issuing-01-2025"
source = { type = "crl", path = "/var/lib/hoike/crls/enterprise-2025.crl" }
# ... new key's signing config
```

Both entries are active simultaneously. As old certificates expire and are no longer queried, you can remove the old entry.

## Cross-signed CAs

Cross-signing creates multiple issuer paths to the same CA subject. Each cross-signed variant has a different issuer key, producing a different `issuerKeyHash`. Clients may send requests using any of the cross-signed paths.

Handle this the same way as re-keyed CAs: one `[[ca]]` entry per cross-signed variant, each with its own signing configuration.

## Collision Resolution

The multimap is keyed by `issuerKeyHash`. In the astronomically unlikely case that two different CAs produce the same hash (effectively impossible with SHA-256, but theoretically possible with SHA-1 truncation), the multimap holds both entries. Resolution proceeds by `serialNumber` — the correct response is found by matching **both** `issuerKeyHash` and `serialNumber` against the bundle index.

In practice, hash collisions between CA keys do not occur. The multimap's multi-value design exists to handle the `certid_compat = "dual"` case cleanly, where the same CA appears under both its SHA-1 and SHA-256 hashes.

## The `certid_compat` Setting

This setting controls which hash algorithms are used to index CertIDs in the ahu bundle:

| Value | Behavior | Use case |
|---|---|---|
| `"dual"` | Compute both SHA-1 and SHA-256 hashes; index and serve under both | Maximum compatibility (default) |
| `"sha256"` | SHA-256 only | Modern clients; smaller index |
| `"sha1"` | SHA-1 only | Legacy environments; **not recommended** for new deployments |

Most deployments should use `"dual"` to handle both legacy clients (which send SHA-1 CertIDs per RFC 6960) and modern clients (which use SHA-256 per RFC 9654). Use `"sha256"` only when you control all clients and can guarantee they use SHA-256 CertIDs.
