# Seal Trust Policy

Every ahu bundle carries a CMS `SignedData` seal over its manifest and index. The seal is what lets an edge node prove that a bundle came from an authorized signer and was not truncated, reordered, or replayed. Seal **verification** is cryptographic; deciding **which signers to trust** is configuration, and that policy lives under `[storage]`.

Without any of the keys below, seal enforcement is **disabled**: bundles load with a warning and the anti-rollback checks operate on unauthenticated manifest data. That mode is acceptable only when `bundle_dir` is already trusted end to end (a combined-mode node writing and reading its own bundles). Every edge node that receives bundles from elsewhere must configure a trust policy.

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

The signer seals with `seal_key` and `seal_cert`. Keep the seal key **separate** from the OCSP signing key; a compromised seal key can forge bundle containers but not OCSP responses, and the reverse. If `seal_key` is omitted, hoike falls back to the OCSP signing key with a warning. If `seal_cert` is omitted, hoike generates a self-signed certificate — acceptable for `hoike sign --demo-key` experiments, never for a fleet.

```toml
[[ca]]
label     = "enterprise-ca"
seal_key  = "/etc/hoike/keys/seal.p8"
seal_cert = "/etc/hoike/keys/seal.crt"
```

## What `ahu verify` proves

`ahu verify bundle.ahu --anchor seal-ca.pem` checks that the seal is cryptographically valid under the anchor you pass on the command line. It does **not** consult `hoike.toml`, so a passing `ahu verify` says nothing about whether a given edge node will accept the bundle. To test a node's policy, load the bundle through `hoike check --config` or watch the `bundle_load` audit event.

## Delta bundles

`ahu apply` produces an **unsigned** intermediate by default. To install a delta on a trusting edge, seal it with an authorized signer:

```sh
ahu apply base.ahu delta.ahu -o merged.ahu \
  --seal-key /etc/hoike/keys/seal.p8 \
  --seal-cert /etc/hoike/keys/seal.crt \
  --input-signer-pin /etc/hoike/trust/seal-signer-2026.crt
```

Inputs must themselves verify under the supplied pins; the output is sealed by the given key. Keyless edge nodes cannot perform this step — it belongs on the signer tier or an operator workstation with access to the seal key.
