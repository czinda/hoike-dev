# CMS Seals

Each ahu bundle is cryptographically sealed with a CMS `SignedData` structure (RFC 5652) that binds the manifest, index, and data regions together.

## Purpose

The seal provides:

- **Integrity:** Any modification to the bundle contents invalidates the seal
- **Authenticity:** The seal identifies the signer via the embedded certificate
- **Trust anchoring:** When `seal_trust_anchors` is configured, only bundles sealed by trusted signers are loaded

## Seal structure

The CMS `SignedData` covers the SHA-256 digest of the manifest bytes. The `SignerInfo` contains:

- A `MessageDigest` signed attribute with the manifest hash
- The signature (ECDSA P-256 or ML-DSA)
- The signer's certificate embedded in the `certificates` field

## Supported seal algorithms

| Algorithm | Key type | Signing mode |
|-----------|----------|--------------|
| ECDSA P-256 | PKCS#8 PEM/DER | Prehash (SHA-256 then sign) |
| ML-DSA-44 | PKCS#8 PEM/DER | Full-message (sign raw attrs DER) |
| ML-DSA-65 | PKCS#8 PEM/DER | Full-message |
| ML-DSA-87 | PKCS#8 PEM/DER | Full-message |

The seal key type is auto-detected from the PKCS#8 file's algorithm OID.

## Configuration

The seal key must be **separate** from the OCSP signing key (different key lifetimes).

```toml
[[ca]]
label     = "enterprise-ca"
seal_key  = "/etc/hoike/seal-key.p8"
seal_cert = "/etc/hoike/seal-cert.pem"
```

To require seal verification on bundle load:

```toml
[storage]
seal_trust_anchors = ["/etc/hoike/seal-ca.pem"]
```

When `seal_trust_anchors` is set, bundles without a valid CMS seal are rejected. When omitted, seal verification is skipped with a warning.

## Verification

```sh
# Verify seal integrity
ahu verify bundle.ahu

# Verify seal + individual entry signatures
ahu verify bundle.ahu --entries
```

The `ahu verify` command checks:

1. CMS signature is valid against the embedded signer certificate
2. The signed `MessageDigest` attribute matches the manifest hash
3. Index and data digests match the manifest's integrity fields
4. Index entries are in sorted order

## Current limitations

- **Self-referential verification only.** The seal is verified against the certificate embedded in the CMS structure. Full PKIX path building against `seal_trust_anchors` is not yet implemented — the trust anchor check verifies the seal signature but does not build a complete chain.
