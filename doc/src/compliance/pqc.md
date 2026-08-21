# Post-Quantum Readiness

hoike treats post-quantum cryptography as a first-class configuration, not
an experimental add-on. ML-DSA (Module-Lattice-Based Digital Signature
Algorithm, FIPS 204) is supported at all three security levels alongside
traditional ECDSA.

## Supported algorithms

| Algorithm | Standard | Security level | Signature size | Public key size |
|-----------|----------|----------------|---------------|-----------------|
| ECDSA P-256 | FIPS 186-5 | ~128-bit classical | 72 B | 65 B |
| ECDSA P-384 | FIPS 186-5 | ~192-bit classical | 104 B | 97 B |
| ML-DSA-44 | FIPS 204 | NIST Level 2 (~128-bit PQ) | 2,420 B | 1,312 B |
| ML-DSA-65 | FIPS 204 | NIST Level 3 (~192-bit PQ) | 3,309 B | 1,952 B |
| ML-DSA-87 | FIPS 204 | NIST Level 5 (~256-bit PQ) | 4,627 B | 2,592 B |

hoike uses the `ml-dsa` crate from RustCrypto, which implements FIPS 204.

## Response size impact

Post-quantum signatures are 30-65x larger than ECDSA signatures. This
affects individual response size, bundle size, network bandwidth, and
storage requirements.

### Per-response size comparison

The response size depends on whether a delegated responder certificate
is included in the `certs` field of the `BasicOCSPResponse`.

| Algorithm | Signature | Response (CA-direct, no cert) | Response (delegated, with cert) |
|-----------|-----------|-------------------------------|--------------------------------|
| ECDSA P-256 | 72 B | ~500 B | ~1.2 KB |
| ECDSA P-384 | 104 B | ~530 B | ~1.3 KB |
| ML-DSA-44 | 2,420 B | ~2.8 KB | ~5.5 KB |
| ML-DSA-65 | 3,309 B | ~3.7 KB | ~7.0 KB |
| ML-DSA-87 | 4,627 B | ~5.0 KB | ~9.5 KB |

The delegated certificate adds roughly one public key plus certificate
overhead. For ML-DSA-87, the certificate alone adds ~4 KB.

### Storage at scale

Bundle sizes for varying certificate populations with ML-DSA-87 (worst case):

| Certificates | CA-direct | With delegated cert |
|--------------|-----------|---------------------|
| 10,000 | ~48 MB | ~91 MB |
| 100,000 | ~477 MB | ~906 MB |
| 1,000,000 | ~4.8 GB | ~9.1 GB |
| 10,000,000 | ~47.7 GB | ~90.6 GB |
| 10,000,000 (full chain) | ~47.7 GB | **~160 GB** |

The ~160 GB figure includes a full certificate chain (responder cert +
issuer cert) in every response, which is the worst case for ML-DSA-87.

## Three mitigations

### 1. CA-direct signing

The single most effective size reduction. When the CA signs OCSP responses
directly using its own key (rather than delegating to a separate OCSP
responder key), the responder certificate can be omitted from the
`BasicOCSPResponse.certs` field.

**Size reduction:** roughly 2/3 for ML-DSA algorithms.

**Trade-off:** The CA signing key must be available to the signer process.
This may conflict with key management policies that restrict CA key usage
to certificate issuance. However, for organizations with HSM-attached CA
keys, this is often viable.

**Configuration:**

```sh
hoike sign \
  --ca my-ca \
  --issuer-cert ca.crt \
  --signer-cert ca.crt \        # Same as issuer
  --signer-key ca.key \          # CA's own key
  --sig-alg ml-dsa-65 \
  --ca-direct \                  # Omit responder cert from responses
  ...
```

### 2. Batching

Batch signing amortizes the computational cost of ML-DSA signatures. While
this does not reduce per-response *size*, it is critical for operating
within HSM throughput constraints.

ML-DSA signing performance (approximate, software):

| Algorithm | Signs/sec (software) | Time per 10M batch |
|-----------|---------------------|---------------------|
| ECDSA P-256 | ~50,000 | ~3.3 minutes |
| ML-DSA-44 | ~10,000 | ~16.7 minutes |
| ML-DSA-65 | ~6,000 | ~27.8 minutes |
| ML-DSA-87 | ~3,000 | ~55.6 minutes |

The batch model is inherent to hoike's architecture. The `batch_interval`
should be set to accommodate the signing time for the full certificate
population.

### 3. Delta distribution

For a stable certificate population, most entries do not change between
generations. Delta bundles contain only the additions, modifications, and
removals since the base epoch.

**Example:** A 10M-certificate deployment with 0.1% daily churn
(10,000 changes):

| Distribution | ML-DSA-87 (CA-direct) | ML-DSA-87 (delegated) |
|-------------|----------------------|------------------------|
| Full bundle | ~47.7 GB | ~90.6 GB |
| Delta (0.1% churn) | ~48 MB | ~91 MB |

Delta distribution reduces bandwidth by 1000x for stable populations.
See [ahu Bundle Format -- Delta Bundles](../architecture/ahu-format.md#delta-bundles)
for the delta format specification.

## FIPS 204 compliance notes

hoike's ML-DSA implementation targets FIPS 204 compliance:

| Requirement | Status |
|-------------|--------|
| FIPS 204 parameter sets (ML-DSA-44, 65, 87) | Implemented via `ml-dsa` crate |
| Deterministic signing (hedged, per FIPS 204) | Default mode |
| Key generation per FIPS 204 Section 5 | Delegated to `ml-dsa` crate |
| Signature verification per FIPS 204 Section 6 | Implemented in ahu verify path |

**FIPS 140-3 validation:** The `ml-dsa` crate is not currently FIPS 140-3
validated. For deployments requiring FIPS 140-3 validated cryptography,
use an HSM with ML-DSA support via PKCS#11. hoike's signer supports
PKCS#11 backends for key operations.

## End-to-end PQC testing

The [cert-revocation-lab](https://github.com/czinda/cert-revocation-lab) includes
an ML-DSA-87 PKI hierarchy (Dogtag PKI + Kryoptic PKCS#11 HSM) with a hoike
deployment that signs OCSP responses with ML-DSA-87. This demonstrates the full
PQC chain: Dogtag issues ML-DSA certs → hoike signs ML-DSA OCSP responses →
NSS-based clients (Firefox, certmonger) validate them.

CIQ achieved CAVP certification for ML-DSA in NSS 3.112 (February 2026), with
FIPS 140-3 validation targeted for Q2 2027.

## Algorithm selection guidance

| Scenario | Recommended | Rationale |
|----------|-------------|-----------|
| Current production, no PQ requirement | ECDSA P-256 | Smallest responses, widest compatibility |
| CNSA 2.0 compliance | ML-DSA-65 or ML-DSA-87 | NSA CNSA 2.0 requires NIST Level 3+ |
| Hybrid transition | ECDSA P-256 + ML-DSA-65 (future) | Not yet supported; planned |
| PQ-only, size-constrained | ML-DSA-44 with CA-direct | Smallest PQ option |
| Maximum security | ML-DSA-87 with CA-direct + deltas | Full PQ security with size mitigation |

## Test coverage

ML-DSA bundle tests are in `crates/hoike-sign/tests/`:

```sh
cargo test -p hoike-sign -- ml_dsa
```

These tests cover:

- ML-DSA-44/65/87 key generation and signing
- Response production with ML-DSA signatures
- Bundle creation with ML-DSA-signed responses
- Verification of ML-DSA-signed bundles
- Round-trip: sign, bundle, load, verify, serve
