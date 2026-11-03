# Seal Trust Policy

Every ahu bundle carries a CMS `SignedData` seal over its manifest and index. The seal is what lets an edge node prove that a bundle came from an authorized signer and was not truncated, reordered, or replayed. Seal **verification** is cryptographic; deciding **which signers to trust** is configuration, and that policy lives under `[storage]`.

Bundle admission is **fail-closed**. Normal admission requires configured trust — `seal_signer_pins`, `seal_trust_anchors`, or `seal_authorizations` (which restrict already-trusted signers). Missing trust is an admission error, not a warning: a node with no trust configured refuses bundles rather than loading them unauthenticated. The single exception is an explicit opt-out for local demos:

- `storage.allow_unauthenticated_bundles = true` (default `false`), set **with no other trust configured**, permits structure-only demo admission of bundles whose seals are not authenticated. hoike reports this mode as unauthenticated.
- **Configured trust never downgrades.** When any trust mechanism is configured, a bundle that fails verification under it is rejected — it never falls back to demo admission.
- **Decoded manifests are bound to the authenticated bytes.** Manifest data is only trusted after the seal over the exact bundle bytes verifies, so manifest content can never be substituted after the fact.

One authenticated admission path serves every entry point — startup, hot reload, committed-snapshot recovery, `hoike check`, and `hoike import`. A bundle accepted by one is accepted by all; a bundle rejected anywhere is rejected everywhere.

## Three mechanisms

| Key | What it trusts | When to use |
|-----|----------------|-------------|
| `seal_signer_pins` | Exact certificates (byte-for-byte DER equivalence, supplied as PEM or DER) | Small fleets, air-gapped enclaves, or when you want zero PKI dependency on the edge |
| `seal_trust_anchors` | A CA, and any seal certificate **directly issued** by it | Fleets where seal certificates are renewed under a stable, dedicated CA |
| `seal_authorizations` | Restricts an already-trusted signer to specific producers and CA scopes | Multi-tenant signers, or any deployment where one signer must not be able to seal another CA's bundle |

The mechanisms compose: a seal is accepted if it verifies under a pin **or** an anchor, **and** (when any authorizations are configured) matches an authorization entry for its scope.

```toml
[storage]
bundle_dir = "/var/lib/hoike/bundles"
state_db   = "/var/lib/hoike/state"

# Option A: explicit pins
seal_signer_pins = [
  "/etc/hoike/trust/seal-signer-2026.crt",
  "/etc/hoike/trust/seal-signer-2027.crt",   # staged for renewal
]

# Option B: CA anchor
seal_trust_anchors = ["/etc/hoike/trust/seal-ca.pem"]

# Local-demo escape hatch — structure-only admission, permitted ONLY when
# no pins, anchors, or authorizations are configured. Never for a fleet.
# allow_unauthenticated_bundles = true

# Optional restriction, applied on top of A or B
[[storage.seal_authorizations]]
producer_id     = "signer-east-1"
issuer_key_hash = "9f3a…"     # hex of the manifest scope hash
signer_sha256   = "b71c…"     # SHA-256 of the DER seal certificate, hex

[[storage.seal_authorizations]]
producer_id     = "signer-east-1"
issuer_key_hash = "e02d…"     # dual SHA-1/SHA-256 scopes need one entry each
signer_sha256   = "b71c…"
```

## Supported profile

The seal verifier implements a **bounded** certificate profile, not general PKIX path building:

- Signature algorithms: ECDSA P-256 with SHA-256, ML-DSA-44/65/87.
- Anchors must carry CA basic constraints and a key usage permitting certificate signing.
- Seal certificates must be within their validity period and carry an applicable key usage.
- Only the directly-issued relationship is checked; intermediate chains, policy processing, and unknown critical extensions cause rejection.

Provision dedicated seal certificates that fit this profile. Do not relabel an arbitrary server or code-signing certificate as a seal anchor.

## Renewal choreography

Pins are exact, so renewing a seal certificate is a three-step rollout:

1. Add the **new** certificate to `seal_signer_pins` (or ensure it is issued under the existing anchor) on every edge and reload.
2. Switch the signer to the new key and certificate (`seal_key`, `seal_cert`).
3. After the fleet has loaded at least one generation sealed by the new certificate, remove the old pin.

Reversing steps 1 and 2 will reject every new bundle at the edge until the pin lands.

## Signer side

The signer seals with `seal_key` and `seal_cert`. Keep the seal key **separate** from the OCSP signing key; a compromised seal key can forge bundle containers but not OCSP responses, and the reverse.

A complete `seal_key` + `seal_cert` pair is **required per CA for production signing keys** (`signing_key.type = "file"` or `"pkcs11"`). A missing pair, or exactly one of the two, is a configuration error — the previous implicit fallbacks (reusing the OCSP signing key as the seal key, generating an ephemeral seal key for non-demo configurations) are removed. Only `signing_key.type = "demo"` may omit both, in which case hoike generates a **distinct ephemeral seal pair** for that signing pass — testing only, never pinned across generations.

```toml
[[ca]]
label     = "enterprise-ca"
seal_key  = "/etc/hoike/keys/seal.p8"
seal_cert = "/etc/hoike/keys/seal.crt"   # PEM or DER
```

### Key separation (enforced)

Separation is proven, not assumed. ECDSA signers sign the domain-separated message `hoike:seal-ocsp-key-separation:v1`, verified under the seal public key, before any signing pass produces output. The same key material reached via different file paths or a symlink is rejected — the proof is over the key, not the name it was configured under. A failed proof fails the signing pass before anything is produced or published. An ML-DSA OCSP signer is algorithm-distinct from the configured P-256 seal key.

### Seal certificate normalization and preflight

Seal certificates are accepted in **PEM or DER**; both are normalized on load, so a PEM `seal_cert` seals and verifies identically to DER. The key/certificate pair is proven with a **real CMS preflight seal on every load and signing pass** — a mismatched or expired replacement fails closed before publication, not at the next edge.

## Serving profile: full, uncompressed bundles only

Only **full, uncompressed bundles** are admitted. Delta bundles, delta chains, tombstones, and compression are ahu format features that the serving profile rejects at admission, before any durable state changes — an orphan delta never becomes state. To serve the result of a delta, materialize it into a full bundle first (see [Delta bundles](#delta-bundles) below).

## What `ahu verify` proves

`ahu verify` requires an explicit mode. `ahu verify bundle.ahu --config hoike.toml` authenticates the seal under the trust and scope-authorization policy in that configuration — the same admission policy an edge node applies. `ahu verify bundle.ahu --structure-only` checks structure and digests only and prints `Structure valid; authenticity not checked.` A bare invocation fails rather than reporting unverified success. To test a node's effective policy, run `hoike check --config` (read-only — it never installs state) or watch the `bundle_load_failed` audit event on the node itself.

## Delta bundles

`ahu apply` produces an **unsigned** intermediate by default. To install a delta on a trusting edge, seal it with an authorized signer:

```sh
ahu apply base.ahu delta.ahu -o merged.ahu \
  --seal-key /etc/hoike/keys/seal.p8 \
  --seal-cert /etc/hoike/keys/seal.crt \
  --input-signer-pin /etc/hoike/trust/seal-signer-2026.crt
```

Inputs must themselves verify under the supplied pins; the output is sealed by the given key. Keyless edge nodes cannot perform this step — it belongs on the signer tier or an operator workstation with access to the seal key.
