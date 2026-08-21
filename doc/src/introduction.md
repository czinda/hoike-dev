# Introduction

**hoike** is a high-performance OCSP responder built in Rust, designed for
pre-signed, replayable, multi-CA certificate status serving. The name comes
from Hawaiian: *hoike* means "to show, to exhibit, to testify."

## Why hoike exists

OCSP (Online Certificate Status Protocol) is alive and well in enterprise,
federal, DoD, and IoT PKI deployments, even as web browsers have largely
moved to CRLs and short-lived certificates. Organizations running their own
certificate authorities still need fast, reliable certificate status
infrastructure that can:

- Serve thousands of OCSP responses per second with minimal latency
- Support multiple CAs from a single deployment
- Operate in air-gapped and enclave environments
- Meet post-quantum cryptography requirements (ML-DSA)
- Scale horizontally without sharing private keys across nodes

hoike addresses all of these by splitting the problem into two distinct
roles: **signer** and **edge**.

## The signer/edge split

This is hoike's core architectural bet. Traditional OCSP responders combine
signing and serving into a single process, which means every node that
handles client requests must hold the OCSP signing key. hoike separates
these concerns:

**Signer** -- holds the OCSP signing keys (PKCS#11 HSM or PKCS#8 file),
reads revocation data from CRLs or Dogtag's 389 DS via RFC 4533 syncrepl,
and batch-produces pre-signed OCSP responses packaged into CMS-sealed
**ahu bundles**. Signers also handle nonce-bearing requests by signing
fresh responses on demand (`nonce_policy = "live"`). The signer can run in
a hardened enclave, an HSM-attached host, or an air-gapped machine.

**Edge** -- receives ahu bundles (via gossip, push, or manual import) and
serves the pre-signed responses to OCSP clients. Edge nodes are stateless
and keyless. They memory-map the bundle file and return the appropriate
pre-signed bytes with zero cryptographic work at request time.

This split means you can run dozens of edge nodes without ever exposing
signing keys to the network, and each edge node serves responses at
memory-read speed.

## The ahu bundle format

An **ahu** bundle is a self-describing container that packages pre-signed
OCSP responses for efficient serving. Each bundle contains:

- A **CBOR manifest** with metadata (CA label, epoch, signature algorithm,
  timestamps)
- A **sorted index** of certificate identifiers mapped to their pre-signed
  responses
- A cryptographic **seal** binding the manifest and all entries together

Bundles support zero-copy serving via `mmap`, meaning the edge process maps
the file into memory and serves response bytes directly without
deserialization. The `ahu` CLI tool lets you inspect, verify, diff, and
apply delta updates to bundles.

## Workspace overview

hoike is organized as a Rust workspace with six crates:

| Crate | Description | License |
|-------|-------------|---------|
| `ahu` | Bundle format: read, write, verify, CMS seal verification | Apache-2.0 / MIT |
| `hoike-core` | CertID routing, config, anti-rollback state store, seal verification on load | GPL-3.0-or-later |
| `hoike-sign` | CRL + syncrepl adapters, OCSP response + CMS seal creation, PKCS#11, ML-DSA bridge, live nonce signing, key rotation | GPL-3.0-or-later |
| `hoike-server` | axum HTTP handlers, nonce policy dispatch, live signing, forward proxy | GPL-3.0-or-later |
| `hoike-gossip` | SWIM protocol (via foca) for edge fleet coordination | GPL-3.0-or-later |
| `hoike-cli` | CLI entry points for `hoike` and `ahu` binaries | GPL-3.0-or-later |

The `ahu` crate is dual-licensed under Apache-2.0/MIT so that other
projects can use the bundle format without GPL obligations. All other
crates are GPL-3.0-or-later.

## Key standards

hoike implements or targets these RFCs:

- **RFC 6960** -- Online Certificate Status Protocol (OCSP)
- **RFC 9919** -- Lightweight OCSP Profile for High-Volume Environments
- **RFC 9654** -- OCSP Nonce Extension
- **RFC 5280** -- Authority Information Access (AIA) for OCSP responder
  discovery

## Technology stack

- **Language**: Rust 1.85+
- **HTTP server**: axum 0.8 on tokio
- **Cryptography**: RustCrypto (`der`, `x509-cert`, `x509-ocsp`, `cms`)
- **HSM**: PKCS#11 via `cryptoki` (Luna, Entrust, Utimaco, FutureX, Kryoptic)
- **Post-quantum**: ML-DSA-44/65/87 via `ml-dsa`
- **Serialization**: ciborium (CBOR)
- **Memory mapping**: memmap2
- **Compression**: zstd
- **Gossip**: foca (SWIM protocol)

## What's next

Head to the [Quick Start](./quickstart/install.md) to build hoike from
source and create your first OCSP responder, or jump to the
[Architecture Overview](./architecture/overview.md) for a deeper look at
how the pieces fit together.
