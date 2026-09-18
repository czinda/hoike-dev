# Dual-Algorithm Bundles

hoike supports bundles that contain both ECDSA and ML-DSA responses for the same certificate set, enabling gradual post-quantum migration without a flag day.

## How it works

A dual-algorithm bundle contains two index entries for each certificate — one pointing to an ECDSA-signed response and one pointing to an ML-DSA-signed response. The entries share the same `entry_key` (SHA-256 of the CertID) but differ in the `discriminator` field:

| Discriminator | Algorithm |
|---------------|-----------|
| `0` | ECDSA P-256 (default) |
| `2` | ML-DSA-44 |
| `3` | ML-DSA-65 |
| `4` | ML-DSA-87 |

The index is sorted by `(entry_key, discriminator)`. The lookup function `binary_search_preferred` takes the client's algorithm preference list and returns the best available match.

## Producing dual bundles

```sh
hoike sign \
  --ca enterprise-ca \
  --crl ca.crl \
  --signing-key ecdsa.key \
  --sig-alg ecdsa-p256 \
  --dual-alg ml-dsa-87 \
  --pq-signing-key ml-dsa.key \
  -o dual.ahu
```

This produces a single bundle where each certificate has both an ECDSA and an ML-DSA response.

## Client negotiation

Clients indicate their preference via the RFC 6960 §4.4.7.1 `PreferredSignatureAlgorithms` extension in the OCSP request. hoike parses this extension and resolves the best match.

```sh
# Query with PQ preference — returns ML-DSA-87 response
hoike query --url http://localhost:2560 \
  --serial 0A1B2C \
  --issuer-name-b64 "..." \
  --issuer-key-b64 "..." \
  --prefer ml-dsa-87

# Query without preference — returns ECDSA response (default)
hoike query --url http://localhost:2560 \
  --serial 0A1B2C \
  --issuer-name-b64 "..." \
  --issuer-key-b64 "..."
```

## Migration strategy

1. **Phase 1:** Generate dual-algorithm bundles alongside your existing ECDSA-only bundles. Clients that don't send `PreferredSignatureAlgorithms` continue to receive ECDSA responses.

2. **Phase 2:** Update PQ-capable clients to send `--prefer ml-dsa-87` (or the appropriate level). They start receiving ML-DSA responses while classical clients are unaffected.

3. **Phase 3:** When all clients support ML-DSA, switch to ML-DSA-only bundles (`--sig-alg ml-dsa-87` without `--dual-alg`).

No flag day. One responder, one bundle, both algorithms.

## Size implications

Dual-algorithm bundles are roughly 2x the size of single-algorithm bundles, since each certificate has two responses. The ML-DSA responses are significantly larger than ECDSA:

| Configuration | Per-cert size | Bundle (1M certs) |
|---------------|--------------|---------------------|
| ECDSA only | ~500 B | ~520 MB |
| ML-DSA-87 only | ~5 KB | ~5.1 GB |
| Dual (ECDSA + ML-DSA-87) | ~5.5 KB | ~5.6 GB |

Delta distribution mitigates the size increase for steady-state operation.
