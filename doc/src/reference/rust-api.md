# Rust API Reference

Full rustdoc-generated API documentation is available at
[/api/](/api/).

This page provides a high-level map of the six crates and their public
API surface to help you find what you need.

## Crate overview

### ahu

**License:** Apache-2.0 / MIT

The bundle format library. Use this crate if you need to read, write, or
verify ahu containers from your own Rust code.

Key public types and modules:

| Item | Description |
|------|-------------|
| `Bundle` | Top-level type for reading and inspecting an ahu bundle |
| `BundleBuilder` | Construct a new bundle with manifest, entries, and seal |
| `FileHeader` | Fixed 64-byte file header (magic, format version, region offsets) |
| `Manifest` / `CaScope` | CBOR manifest metadata and per-CA scopes (epoch, completeness, window) |
| `IndexRecord` / `IndexFlags` | Sorted 48-byte index records and their flag bits |
| `MmapBundle` | Memory-mapped bundle access for zero-copy serving |
| `verify_structure` / `check_epochs` | Structural verification and anti-rollback epoch checks |
| `verify_seal` / `verify_seal_with_anchors` / `verify_seal_with_pins` | CMS seal verification, standalone or against configured trust |
| `apply` / `diff` | Materialize delta bundles and compare generations |

This crate is dual-licensed (Apache-2.0/MIT) so it can be used as a
dependency without GPL obligations.

### hoike-core

**License:** GPL-3.0-or-later

Shared types, configuration parsing, and protocol logic used by all other
hoike crates.

Key public types and modules:

| Item | Description |
|------|-------------|
| `Config` | Parsed `hoike.toml` configuration (the `config` module exposes the section types) |
| `CaConfig` | Per-CA configuration (`[[ca]]` section) |
| `ServerConfig` | Server mode, listen address, `max_request` limit |
| `StorageConfig` | Bundle directory, state DB path, seal trust |
| `ResponderState` | The loaded working set: scope routing, lookup, hot reload |
| `LookupResult` / `ScopeDetail` | Serve-time lookup results and per-bundle scope diagnostics |
| `StateStore` / `StateDirectoryLock` | Durable anti-rollback state and the exclusive writer lock |
| `ParsedRequest` / `ParsedCertId` / `NonceAction` | Strict request parsing, CertID extraction, RFC 9654 nonce classification |
| `install_bundle` / `InstallResult` | Authenticated offline bundle installation |

### hoike-sign

**License:** GPL-3.0-or-later

The signing engine. Parses CRLs, produces OCSP responses, and seals them
into ahu bundles.

Key public types and modules:

| Item | Description |
|------|-------------|
| `produce_bundle` / `produce_dual_bundle` | Batch production of single- and dual-algorithm bundles |
| `GenerationConfig` / `CertIdCompat` | Production parameters (epoch, CertID compatibility mode) |
| `sign_live_response` / `LiveCertStatus` | Live nonce signing, including the signed-unknown path |
| `CrlSource` / `DogtagSyncSource` | Authenticated CRL and 389 DS syncrepl revocation sources |
| `RevocationSource` / `StatusSnapshot` / `CertificateStatus` | The revocation source trait and its snapshots |
| `CaIdentity` | CA label plus issuer name and key bytes for CertID computation |
| `EcdsaP256Signer` / `MlDsaSignerVariant` | Classical and post-quantum signer bridges |
| `Pkcs11Signer` / `Pkcs11MlDsaSigner` | PKCS#11 HSM signers (`pkcs11` feature) |
| `create_cms_seal` / `load_or_generate_seal_material` | CMS seal creation and the seal/OCSP key-separation policy |

### hoike-server

**License:** GPL-3.0-or-later

The axum-based HTTP server that handles OCSP requests and serves
pre-signed responses.

Key public types and modules:

| Item | Description |
|------|-------------|
| `AppState` | Shared server state (responder, live signers, gossip handle, admin config) |
| `SignerContext` / `LiveSignerState` | Per-CA live signing material for nonce responses |
| `build_router` / `build_admin_router_standalone` | The public OCSP router and the dedicated admin listener router |
| `build_metrics_router` / `install_metrics` | Prometheus metrics endpoint (`metrics` feature) |
| `build_forward_clients` | Per-CA forwarding clients with pinned per-CA trust roots |
| `announce_bundle_scopes` | Broadcast a new bundle's scopes to the gossip mesh |

### hoike-gossip

**License:** GPL-3.0-or-later

SWIM gossip protocol integration via
[foca](https://crates.io/crates/foca) for edge fleet coordination.

Key public types and modules:

| Item | Description |
|------|-------------|
| `GossipNode` | Manages the foca SWIM instance and broadcast handling |
| `GossipMessage` | Broadcast payloads: `GenerationAnnouncement` and `UrgentRevocation` |
| `GossipConfig` / `AuthMode` | Gossip parameters and the broadcast authentication policy (`required` / `permissive`) |
| `GossipSigner` / `GossipVerifier` / `load_authentication` | Ed25519 broadcast signing and verification |

### hoike-cli

**License:** GPL-3.0-or-later

CLI entry points and argument parsing for the `hoike` and `ahu` binaries.
This crate wires together all other crates behind the command-line
interface.

You generally do not depend on this crate as a library. Its public API is
the CLI itself, documented in the [hoike CLI](./hoike-cli.md) and
[ahu CLI](./ahu-cli.md) reference pages.

## Building the docs locally

Generate the full API documentation with:

```sh
cargo doc --workspace --no-deps --open
```

This builds rustdoc for all six crates and opens the result in your
browser. The `--no-deps` flag skips documentation for third-party
dependencies.

To build docs for a single crate:

```sh
cargo doc -p ahu --no-deps --open
```
