# Hardening Guide

This page is the checklist a security reviewer should be handed with a hoike deployment. Each control names the configuration key or platform setting that implements it, and says plainly where hoike relies on the host rather than on itself.

## Threat model in one paragraph

An edge node holds no signing keys, so compromising one cannot produce a false `good`; it can only deny service or replay a still-valid generation until `nextUpdate`. The signer holds keys and is the asset to protect. The bundle seal, the anti-rollback chain, and signed gossip broadcasts exist to make sure that only an authorized signer can change what edges serve. Everything below either protects the signer, protects the management plane, or makes tampering with bundles detectable.

## Build

| Control | Setting |
|---------|---------|
| Enable TLS support | `cargo build --release --features tls` — a binary built without it cannot terminate TLS on any listener |
| Enable HSM signing | `--features pkcs11`; production signing keys must not be files |
| Reproducible dependency set | `--locked`; `Cargo.lock` is committed and audited with `cargo audit` in CI |
| Do not ship demo paths | `hoike sign --demo-key` and `signing_key.type = "demo"` exist for tutorials; refuse configurations that use them in production review |

## Signer tier

| Control | Setting |
|---------|---------|
| Keys in an HSM | `signing_key = { type = "pkcs11", module = "...", token_label = "...", key_label = "...", pin_env = "HOIKE_HSM_PIN" }`. A forthcoming release refuses file and demo keys in signer and combined modes unless `allow_software_keys = true` is set and audited; treat any file-key configuration as non-production now |
| PIN never in the config file | Use `pin_env`, or omit both `pin` and `pin_env` to be prompted interactively at startup |
| Separate seal key | `seal_key` and `seal_cert` distinct from the OCSP signing key |
| Authenticated sources | CRL: `issuer_cert` required. Directory: `tls = "ldaps"` or `"starttls"`, `ca_cert`, `bind_password_env` |
| Delegated responder certificate | `responder_cert` with the `id-kp-OCSPSigning` EKU, short lifetime, and `key_rotation` configured so expiry is caught early |
| No inbound OCSP on the signer | `mode = "signer"`; edges serve, the signer only produces |
| State directory | Local filesystem with tested `fsync`/`rename` semantics; not NFS. One signer process per directory. Backed up as a unit |

## Edge tier

| Control | Setting |
|---------|---------|
| Seal trust policy configured | `storage.seal_signer_pins` or `storage.seal_trust_anchors`, plus `seal_authorizations` where one signer must not seal another CA's bundle. See [Seal Trust Policy](../operator/seal-trust.md) |
| Anti-rollback state persisted | `storage.state_db` on durable local storage; never delete high-water marks to "fix" a load failure |
| Read-only bundle mount | Mount `bundle_dir` read-only into the container; the edge never writes there |
| Gossip authenticated | `gossip.identity_key` on every node, `gossip.peer_identities` listing every peer by name; an empty map is permissive mode and is not equivalent to authenticated operation |
| Gossip bound to the fleet network | `gossip.bind` on an internal interface; gossip carries no status data but does carry generation announcements |
| Live signing impossible | `nonce_policy = "live"` on an edge is a startup error; keep it that way |

## Management plane

| Control | Setting |
|---------|---------|
| Dedicated admin listener | `server.admin_listen` on a management address; never the public OCSP address |
| TLS on the admin listener | `server.admin_tls = { cert, key }` |
| Mutual TLS | `server.admin_tls.client_ca` |
| Metrics private | `server.metrics_listen = "127.0.0.1:9184"` or behind `metrics_tls`; the endpoint is unauthenticated |
| Operators | Named accounts in `server.admin.operators`, one per person, least role that does the job; `viewer` for dashboards |
| Session lifetime | `session_ttl_secs` at 900 or less for administrator-heavy nodes (default 3600) |
| Web UI | Omit `server.webui` on nodes where no one will use it; the API still works |

Known gaps in this release, tracked for the next: per-account lockout, password complexity, idle timeout, consent banner, HTTP security headers, and operator identity in audit events. Compensate with mutual TLS and network segmentation until they land.

## Process and host

| Control | Setting |
|---------|---------|
| Non-root | The container image runs as `nonroot`; on a host, a dedicated `hoike` system user |
| File permissions | `hoike.toml` 0640 (it contains password hashes); keys 0600; `bundle_dir` read-only for the edge user |
| Secrets | Environment variables (`pin_env`, `bind_password_env`) injected by the platform's secret mechanism, never on the command line |
| Time | chrony or the platform equivalent; response validity windows and anti-rollback continuity depend on host time |
| Logging | Forward stdout to journald or the platform collector; add `audit=info` to any custom `RUST_LOG`. See [Audit Logging](audit-logging.md) |
| FIPS mode | Determined by the host kernel (`/proc/sys/crypto/fips_enabled`); hoike's own crypto does not yet run inside the operating system's validated module — see [FIPS 140-3 Status](../compliance/fips.md) |
| Firewall | Edge: OCSP port (2560) public, gossip port fleet-only, admin and metrics management-only. Signer: no public inbound at all |

## OpenShift and Kubernetes

- Run under the `restricted-v2` SCC; hoike needs no capabilities, no host paths, and no privilege escalation.
- Mount `hoike.toml` and TLS material from Secrets; bundles from a ConfigMap, PVC, or an init container that fetches from the signer, mounted `readOnly: true`.
- Give the state directory a PVC with `ReadWriteOnce`; never share it between replicas.
- Expose only the OCSP port through the Route or Service; keep the admin port ClusterIP-only and reach it through `oc port-forward` or a management ingress with mTLS.

## Air-gapped enclaves

The same binary and configuration apply. Disable gossip (`gossip.enabled = false`), import bundles on media into `bundle_dir`, and rely on the seal trust policy to verify what was imported. The anti-rollback chain still enforces monotonic epochs across imports. See [Air-Gap Deployments](../operator/air-gap.md).

## Review checklist

- [ ] Binary built with `tls` (and `pkcs11` on signers)
- [ ] Every signer key in an HSM; no `type = "file"` or `"demo"` keys
- [ ] `issuer_cert` set for every CRL source; LDAPS or StartTLS for every directory source
- [ ] Seal trust policy configured on every edge; `ahu verify` is not a substitute
- [ ] `identity_key` and a complete `peer_identities` map on every gossiping node
- [ ] `admin_listen` set, `admin_tls` set, `client_ca` set
- [ ] `metrics_listen` bound to loopback or behind TLS
- [ ] One named operator per person; roles reviewed
- [ ] `hoike check --config` clean, with warnings explained in writing
- [ ] Logs forwarded; `rollback` and `fork` audit events alerting
