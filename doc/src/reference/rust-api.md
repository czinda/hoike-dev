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
| `Manifest` | CBOR-encoded bundle metadata (CA label, epoch, algorithm, timestamps) |
| `Entry` | A single CertID-to-response mapping in the bundle |
| `Seal` | Cryptographic seal binding the manifest and all entries |
| `verify()` | Verify a bundle's seal, digests, and sort order |
| `mmap` | Memory-mapped bundle access for zero-copy serving |

This crate is dual-licensed (Apache-2.0/MIT) so it can be used as a
dependency without GPL obligations.

### hoike-core

**License:** GPL-3.0-or-later

Shared types, configuration parsing, and protocol logic used by all other
hoike crates.

Key public types and modules:

| Item | Description |
|------|-------------|
| `Config` | Parsed `hoike.toml` configuration |
| `CaConfig` | Per-CA configuration (`[[ca]]` section) |
| `ServerConfig` | Server mode, listen address, limits |
| `StorageConfig` | Bundle directory, state DB path, chain limits |
| `GossipConfig` | SWIM gossip parameters (seeds, bind address, node name) |
| `NoncePolicy` | Nonce handling strategy (ignore, reject, echo) |
| `Completeness` | Completeness model for unknown certificates |

### hoike-sign

**License:** GPL-3.0-or-later

The signing engine. Parses CRLs, produces OCSP responses, and seals them
into ahu bundles.

Key public types and modules:

| Item | Description |
|------|-------------|
| `Signer` | Main signing orchestrator -- CRL + serials in, sealed bundle out |
| `ResponseBuilder` | Construct individual OCSP responses |
| `CrlParser` | Parse PEM or DER CRL files and extract revocation entries |
| `SigAlgorithm` | Enum of supported signature algorithms (ECDSA, ML-DSA variants) |
| `CertIdCompat` | CertID hash compatibility mode selection |
| `EpochManager` | Track and enforce monotonic epoch numbering |

### hoike-server

**License:** GPL-3.0-or-later

The axum-based HTTP server that handles OCSP requests and serves
pre-signed responses.

Key public types and modules:

| Item | Description |
|------|-------------|
| `Server` | Top-level server lifecycle (bind, serve, shutdown) |
| `OcspHandler` | Request parsing, CertID extraction, bundle lookup |
| `BundleStore` | Thread-safe bundle storage with hot-reload support |
| `Router` | axum router configuration with OCSP and health endpoints |

### hoike-gossip

**License:** GPL-3.0-or-later

SWIM gossip protocol integration via
[foca](https://crates.io/crates/foca) for edge fleet coordination.

Key public types and modules:

| Item | Description |
|------|-------------|
| `GossipRuntime` | Manages the foca SWIM protocol instance |
| `BundleAnnouncement` | Notification payload when a new bundle is available |
| `PeerState` | Tracked state for each peer in the gossip cluster |
| `Transport` | UDP transport layer for gossip messages |

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
