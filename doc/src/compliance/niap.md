# NIAP Common Criteria Status

**hoike has not been evaluated under the Common Criteria and holds no NIAP certificate.** The project maintains draft Security Targets against three NIAP documents so that the gap between the code and a certifiable posture is explicit and tracked. This page summarizes that status for deployers; the engineering detail lives in the repository under `docs/compliance/`.

## How hoike fits the profiles

| NIAP document | hoike's role | Status |
|---------------|--------------|--------|
| Protection Profile for Certification Authorities (PP 420) | The **OCSP component** of a composite Target of Evaluation whose issuing CA is Red Hat Certificate System. hoike is not a CA and cannot be evaluated against this profile alone. | Architecture aligned; crypto boundary and audit attribution open |
| Protection Profile for Application Software | The hoike binaries as an application on a Red Hat Enterprise Linux platform | Six functional requirements open |
| Functional Package for TLS | The admin, metrics, forward-proxy, and LDAPS channels | Server side largely aligned; ciphersuite selection and client-side activities open |

The draft Security Targets were written against PP for Certification Authorities v2.1, PP for Application Software v1.4, and TLS Functional Package v1.1. NIAP has since published newer TLS package versions; the STs will be rebased on whatever versions NIAP accepts when an evaluation is scheduled.

## What is aligned today

- **Proof of origin.** Every OCSP response is signed; the delegated responder certificate is embedded per RFC 9919 so relying parties can validate without pre-caching.
- **Status freshness and anti-replay.** Response windows are bounded by the source; epochs are monotonic with persisted high-water marks; forks are detected.
- **Keyless serving tier.** Edge nodes cannot produce a false `good` by construction.
- **Trusted path for administration.** Dedicated TLS listener with optional mutual TLS; TLS 1.2 and 1.3 only.
- **Trusted channels between components.** HTTPS-only nonce forwarding without redirects; LDAPS or StartTLS-before-bind for directory synchronization; Ed25519-signed gossip broadcasts with named-origin authorization.
- **Roles and management functions.** Administrator, Operator, and Viewer roles enforced per route.
- **Third-party library inventory.** Locked dependency set, `cargo audit` in CI, zero known advisories at the 0.2.0 lockfile.
- **No default credentials, no PII collection, bounded inputs.**

## What is open

| Requirement area | Gap | Planned resolution |
|------------------|-----|--------------------|
| Cryptographic support (FCS_COP, FCS_CKM, FCS_RBG) | Operations run in unvalidated Rust crates | Host OpenSSL FIPS provider plus HSM; see [FIPS 140-3 Status](fips.md) |
| Key protection (FPT_SKP, FCS_STO) | No zeroization; secrets may be inline in TOML | `zeroize`; file or environment indirection only |
| Audit (FAU_GEN.2) | Events do not carry the operator identity; logins not audited | Next release |
| Identification and authentication (FIA) | No lockout, no complexity policy, no re-authentication for privileged actions | Next release |
| Trusted update (FPT_TUD) | Releases and images are checksummed, not signed | Signed releases with published verification steps |
| Version identification (FPT_IDV) | `hoike --version` not implemented | Next release |
| Self-test (FPT_TST) | No cryptographic self-test at startup | Inherited from the host module's power-on self-test plus a `hoike check --fips` known-answer run |
| TLS ciphersuite selection | Provider defaults, not an explicit approved list | Explicit allow-list under the host crypto policy; `hoike check --tls` conformance test |
| Certificate validation for TLS peers (FIA_X509) | No revocation checking for forward-proxy or LDAPS peers | Reuse the signer's CRL configuration |

## Environmental objectives

A Security Target will place these on the operational environment, and deployers should be ready to evidence them:

- Reliable time (chrony) on every node.
- Disk encryption or equivalent for the state directory and bundle storage.
- Audit forwarding and retention (journald or a SIEM) with integrity protection.
- A validated HSM holding every production signing key.
- Host operating system in FIPS mode with the `FIPS` crypto policy.

## Related pages

- [Hardening Guide](../security/hardening.md)
- [Audit Logging](../security/audit-logging.md)
- [DISA STIG Guidance](stig.md)
