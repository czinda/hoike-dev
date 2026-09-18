# DISA STIG Guidance

hoike is designed to be deployed on a host that is itself STIG-compliant — Red Hat Enterprise Linux under the Red Hat Enterprise Linux STIG, or OpenShift under the Container Platform SRG. Most controls are therefore inherited. This page maps the Application Security and Development STIG requirement families to what hoike provides, what is configuration, and what is still open, so that a checklist can be completed without re-deriving the answers. Exact rule IDs should be taken from the current benchmark release.

## Inherited from the platform

| Requirement family | Provided by |
|--------------------|-------------|
| Operating system FIPS mode and crypto policy | Host kernel and `crypto-policies`; hoike does not override them |
| Audit storage, protection, retention, and forwarding | journald or the platform collector; see [Audit Logging](../security/audit-logging.md) |
| Time synchronization | chrony |
| Account management for the service user | Host or platform identity |
| Network segmentation and firewalling | Host firewall, OpenShift NetworkPolicy |
| Disk encryption | LUKS or the platform's storage encryption |
| Malware and vulnerability scanning of the host | Platform tooling |

## Met by hoike as shipped

| Requirement family | How |
|--------------------|-----|
| Input validation and bounded requests | OCSP body limit (`max_request`, 8,192 bytes default); admin login body 4,096 bytes with a 5-second read timeout; checked DER parsing; no unbounded upstream reads |
| Error messages do not reveal internals | Static OCSP error responses; short admin error strings; no stack traces |
| No default or shared accounts | Operators must be configured explicitly |
| Least privilege | Container runs as a non-root user; no capabilities required |
| Separation of management and data interfaces | `admin_listen` and `metrics_listen` are distinct from the OCSP listener |
| Session termination on logout | `DELETE /session` invalidates the token |
| Role-based access | Administrator, Operator, Viewer enforced on every admin route |
| Certificate expiry notification | Key-rotation monitor warns before `responder_cert` expiry |
| Third-party component tracking | Locked dependency set with `cargo audit` in CI |

## Met by configuration

| Requirement family | Setting |
|--------------------|---------|
| Management traffic encrypted | `server.admin_tls`, `server.metrics_tls`; build with `--features tls` |
| Mutual authentication of administrative connections | `server.admin_tls.client_ca` |
| Use of an approved PKI for management TLS | Point `client_ca` and the server certificate at the organization's or DoD's issuing CA |
| Credentials not stored in clear text | `pin_env` and `bind_password_env` instead of `pin` and `bind_password`; password hashes only in `operators` |
| Encrypted channels to backing services | `forward_to` must be `https://`; directory `tls = "ldaps"` or `"starttls"` |
| Session lifetime | `session_ttl_secs` (set 900 or less for privileged nodes) |
| Non-production features disabled | Do not use `--demo-key`, `signing_key.type = "demo"`, or `forward_insecure` |

## Open in this release

| Requirement family | Status | Compensating control until resolved |
|--------------------|--------|-------------------------------------|
| FIPS-validated cryptographic module for all security functions | Open — see [FIPS 140-3 Status](fips.md) | HSM-held signing keys; host FIPS mode for everything else on the box |
| Account lockout after consecutive failed logins | Open (process-wide rate limit only) | Mutual TLS on the admin listener; management-network-only access |
| Password complexity, minimum length, history, maximum age | Open (hashes are operator-supplied) | Enforce organizational policy when generating hashes; rotate on a schedule |
| DoD Notice and Consent Banner | Open | Present the banner on the management ingress or bastion in front of the admin listener |
| Session inactivity timeout | Open (fixed lifetime only) | Short `session_ttl_secs` |
| Concurrent session limit per user | Open | Procedural |
| Re-authentication for privileged functions | Open | Restrict `administrator` role to a minimum set of accounts; mTLS |
| HTTP security headers on the web UI | Open | Serve the UI only over the mTLS admin listener; or omit `server.webui` |
| Audit of login success/failure and operator identity on privileged actions | Open | Correlate admin-listener access logs at the ingress with hoike audit events |
| Signed release artifacts and images | Open (SHA-256 checksums only) | Build from source in the organization's pipeline and sign there |
| Application reports its version | Open | Record the deployed image digest in the CMDB |

All items in this table are scheduled; see the roadmap in the repository's `docs/compliance/` directory.

## Evidence to collect for a checklist

- `hoike check --config /etc/hoike/hoike.toml` output with no unexplained warnings
- The effective configuration from `GET /api/admin/config` (secrets are redacted)
- `cargo audit` report for the deployed lockfile
- Container image digest and base image (Red Hat Universal Base Image once the rebase lands)
- Host STIG scan results (OpenSCAP) for the node
- Audit forwarding configuration and a sample `rollback` or `fork` event reaching the SIEM

## Related pages

- [Hardening Guide](../security/hardening.md)
- [Admin API and RBAC](../security/admin-api.md)
- [NIAP Common Criteria Status](niap.md)
