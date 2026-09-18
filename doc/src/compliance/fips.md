# FIPS 140-3 Status

**hoike 0.2.0 does not run inside a validated cryptographic module.** Products are not themselves FIPS validated — cryptographic modules are — so the accurate claim for any release of hoike is whether it *uses* validated modules for every approved operation. Today it does not, except where signing is delegated to a validated HSM. This page states exactly where each cryptographic operation executes today, what the target architecture is, and what a deployment can and cannot claim in the meantime.

## Current status

| Operation | Implementation | Inside a validated module? |
|-----------|----------------|----------------------------|
| OCSP response signing, ECDSA P-256 | RustCrypto `p256` / `ecdsa` | No |
| OCSP response signing, ML-DSA | RustCrypto `ml-dsa` | No |
| Signing through an HSM | PKCS#11 via `cryptoki` (`--features pkcs11`) | Yes, when the HSM is validated and the algorithm is in its validated boundary |
| SHA-256 (CertID, bundle index, seal) | RustCrypto `sha2` | No |
| ahu CMS seal | RustCrypto `cms` + `p256` / `ml-dsa` | No |
| CRL signature verification | RustCrypto `p256`, `ml-dsa`; `aws-lc-rs` for RSA (non-FIPS build) | No |
| Gossip broadcast signatures | `ed25519-dalek` | No |
| Admin password hashing | `bcrypt` | No — bcrypt is not an approved algorithm |
| Session tokens | `rand` | No |
| TLS on management listeners and outbound channels | rustls with `aws-lc-rs` provider (non-FIPS build) | No |

Enabling `aws-lc-rs`'s FIPS feature would move only the TLS and RSA-verification rows. It is not the fix.

## What a deployment can claim today

- **Signing keys held in a validated HSM, signatures produced by the HSM.** With `signing_key.type = "pkcs11"` the OCSP signature itself is generated inside the HSM's validated boundary. The digest over the response (`SHA-256`) is still computed in software before the mechanism call, so this is a partial claim; state it that way.
- **No claim** for software keys, the seal, gossip, admin authentication, or TLS.

## Target architecture

hoike is intended to ship alongside Red Hat Certificate System on Red Hat Enterprise Linux, and Red Hat products obtain FIPS 140-3 coverage by consuming the operating system's validated module — the OpenSSL FIPS provider — rather than by validating their own. The planned change introduces a single crypto abstraction and backs it with:

1. **OpenSSL on the host**, dynamically linked, in FIPS mode when the host is: hashing, software ECDSA, PBKDF2 password hashing (replacing bcrypt), the DRBG for tokens and jitter, and TLS through OpenSSL-backed `axum-server`, `reqwest`, and `ldap3`. TLS parameters then follow the host's system-wide crypto policy.
2. **PKCS#11 into an HSM** for all production signing keys, as today.
3. **Red Hat Universal Base Image** for the container, so the image inherits FIPS mode, crypto policies, and errata from the host and Red Hat's build pipeline.

Gossip signatures move to ECDSA P-256 through the same abstraction. Ed25519 remains available where the module supports it.

### ML-DSA and FIPS

ML-DSA (FIPS 204) OCSP signing is supported in two configurations:

- **For deployments that require validated cryptography**, ML-DSA keys must reside in a FIPS 140-3 validated HSM whose certificate lists `CKM_ML_DSA` in the approved mode; hoike accesses the key through PKCS#11 and the signature is produced inside the HSM's validated boundary.
- **Software ML-DSA** (via the RustCrypto implementation today, via OpenSSL 3.5 on Red Hat Enterprise Linux 10.1 after the crypto-boundary change) is provided for interoperability and testing. It is not within any validated cryptographic module boundary, and the Red Hat Enterprise Linux system OpenSSL FIPS provider does not implement ML-DSA.

These statements are deliberate. hoike does not describe the software path as "FIPS approved" or as running in "FIPS mode", and it does not claim that a validation is pending. When the validated provider on Red Hat Enterprise Linux gains FIPS 204 algorithms, this page will be updated to say so with the certificate reference.

## Timeline and tracking

The crypto-abstraction work is the second phase of the security roadmap and precedes any Common Criteria evaluation, because the evaluated crypto boundary must not change mid-evaluation. Progress is tracked in the repository's `docs/compliance/` directory; this page will be updated when a release ships that runs entirely on the host module, and a `hoike check --fips` preflight will report the module name, version, and mode at runtime.

## Related pages

- [Hardening Guide](../security/hardening.md)
- [NIAP Common Criteria Status](niap.md)
- [DISA STIG Guidance](stig.md)
- [Post-Quantum Readiness](pqc.md)
