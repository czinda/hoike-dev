# Gossip Configuration

hoike uses the [SWIM protocol](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf) (implemented via the `foca` crate) for lightweight, decentralized coordination across edge nodes. Gossip is a **notification channel** — it never carries OCSP response data and is never authoritative.

## What Gossip Provides

Gossip serves three purposes in a hoike deployment:

| Function | Description |
|----------|-------------|
| **Membership** | Automatic discovery and failure detection of edge nodes in the fleet |
| **Generation announcements** | Signer broadcasts when a new bundle generation is available; edges pull the bundle on receipt |
| **Urgent revocation notices** | Immediate notification when an off-cycle delta bundle is produced due to a revocation event |

```mermaid
sequenceDiagram
    participant S as Signer
    participant E1 as Edge-01
    participant E2 as Edge-02
    participant E3 as Edge-03

    S->>E1: Generation announcement (epoch 42)
    E1->>S: Pull bundle (epoch 42)
    E1-->>E2: Gossip: new generation 42
    E1-->>E3: Gossip: new generation 42
    E2->>S: Pull bundle (epoch 42)
    E3->>S: Pull bundle (epoch 42)
```

## Configuration

```toml
[gossip]
enabled      = true
bind         = "0.0.0.0:7946"
seeds        = ["edge-a.pki.example:7946", "edge-b.pki.example:7946"]
identity_key = "/etc/hoike/gossip.key"
node_name    = "edge-01"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `false` | Enable or disable gossip. Set to `false` for air-gap deployments. |
| `bind` | string | `"0.0.0.0:7946"` | Address and port to bind the gossip listener. |
| `seeds` | array of strings | `[]` | Initial contact points for joining the gossip mesh. |
| `auth_mode` | string | `"required"` | Broadcast authentication policy: `"required"` (default) or `"permissive"` (rollout). Any other value is a startup error. |
| `identity_key` | path | — | Path to this node's Ed25519 PKCS#8 private key, used to sign outbound broadcasts. Required when gossip is enabled with `auth_mode = "required"`. |
| `peer_identities` | table | `{}` | Map of node names to Ed25519 public key paths (named-origin authorization). |
| `node_name` | string | hostname | Human-readable, unique identifier for this node in the mesh. |

## Seed Configuration

Seeds are the initial contact points a node uses to join the gossip mesh. They are not special — any existing mesh member can serve as a seed.

**Recommendations:**

- Configure **at least two seeds** for redundancy. If the single seed is down when a new node starts, it cannot join the mesh.
- Seeds do not need to be dedicated infrastructure. Point new nodes at two or three stable, long-lived edge nodes.
- A node does not need to list every member — once it contacts one seed, SWIM propagates the full membership.

```toml
[gossip]
seeds = [
    "edge-a.pki.example:7946",
    "edge-b.pki.example:7946",
    "edge-c.pki.example:7946",
]
```

## Authentication

Gossip broadcasts are authenticated with Ed25519 signatures under an explicit policy, `auth_mode`:

- **`auth_mode = "required"` (default)** — unsigned, unknown, or forged broadcasts are dropped before re-propagation. Every enabled node must configure an `identity_key`, and each authorized origin must appear in `peer_identities`.
- **`auth_mode = "permissive"`** — the rollout mode. Unsigned legacy broadcasts are still accepted, while signed ones are verified and unknown or forged signatures are rejected.

Any other `auth_mode` value fails configuration. The legacy `peer_keys` array (an unbound key list) is **rejected**: a non-empty value fails startup with an error directing you to migrate to `peer_identities`.

### Identity key

Each node signs its generation and urgent-revocation broadcasts with an Ed25519 PKCS#8 private key configured as `identity_key`. Generate one per node:

```bash
hoike keygen --gossip -o /etc/hoike/gossip.key
chmod 600 /etc/hoike/gossip.key
```

The key file contains the Ed25519 private key. Protect it with appropriate file permissions.

### Peer identities

The `peer_identities` table maps each peer's `node_name` to the path of its Ed25519 public key file, authorizing that origin by name:

```toml
[gossip.peer_identities]
"edge-02"  = "/etc/hoike/gossip/edge-02.pub"
"signer-1" = "/etc/hoike/gossip/signer-1.pub"
```

The corresponding public keys must be distributed to all nodes that will verify broadcasts from that peer.

### Rolling out authentication

Move a mixed fleet to `auth_mode = "required"` in four steps:

1. **Provision identities** — generate a key pair per node and complete the `peer_identities` map fleet-wide (every node lists every other participant).
2. **Switch to permissive** — set `auth_mode = "permissive"` fleet-wide. Unsigned legacy broadcasts are accepted, signed ones verified, unknown or forged signatures rejected.
3. **Configure `identity_key` everywhere** — once every node signs its broadcasts, permissive mode verifies them all.
4. **Switch to required** — set `auth_mode = "required"` fleet-wide. Unsigned and unknown broadcasts are now dropped.

Mixed fleets stay interoperable at the frame level during the rollout (a one-byte signed-frame wire tag distinguishes the formats).

`hoike check` reports the effective gossip auth mode for the configured file.

### What authentication does not cover

- **SWIM liveness is not authenticated.** Pings, indirect probes, and membership updates travel unsigned; only generation and urgent-revocation broadcasts are signed.
- **Gossip carries broadcasts only** — no bundle bytes and no confidentiality. Nothing on the gossip channel is encrypted.
- **Announcements are hints, not data.** They now carry the bundle **manifest digest** (not just the index digest), so metadata-only generation changes are distinguishable. Every pulled bundle is still verified independently via its CMS seal and anti-rollback checks.

## Node Name

`node_name` is a human-readable identifier for the node, used in logs and diagnostics. It must be **unique** across the mesh.

If omitted, hoike defaults to the system hostname. In containerized environments where hostnames may collide, set `node_name` explicitly.

## Failure Detection

SWIM detects failed nodes through a three-phase protocol:

1. **Ping**: A random member is pinged each protocol period.
2. **Ping-req**: If the ping times out, `k` other members are asked to ping the suspect on behalf of the requester (indirect probe).
3. **Suspect → Confirm**: If indirect probes also fail, the node is marked suspect. After a timeout, it is declared failed and removed from the membership list.

Failed nodes stop receiving generation announcements and urgent revocation notices. When they recover, they rejoin via their configured seeds and pull the current bundle.

## Security Model

> **Gossip is never authoritative.** It is a hint channel that triggers bundle pulls. All trust decisions are made by verifying the bundle itself.

The security boundaries are:

- **Generation announcements and urgent-revocation broadcasts are signed** with the sender's `identity_key`. With `auth_mode = "required"` (the default), unsigned or incorrectly signed broadcasts are dropped before re-propagation. SWIM liveness traffic (pings/acks) is not authenticated.
- **Bundle validity is verified independently** via CMS seal and epoch chain — not via gossip trust. A gossip announcement only says "a new generation exists"; the edge independently verifies every bundle it loads.
- **A compromised gossip node cannot inject bad responses.** The worst it can do is trigger unnecessary pull attempts. The pulled bundle must still pass CMS seal verification and anti-rollback checks.
- **Gossip cannot suppress bundles.** Edges also poll on a schedule, so even if gossip is disrupted, bundles are eventually loaded.

## Network Requirements

Gossip uses **UDP** on the configured `bind` port (default 7946).

Firewall rules must allow:

- **Inbound UDP** on the gossip port from all mesh members
- **Outbound UDP** to all mesh members on their gossip port

In environments with strict firewall policies, you may need to allowlist the gossip port between all edge nodes and the signer. If UDP is blocked entirely, disable gossip and use [air-gap mode](./air-gap.md) or scheduled bundle fetching.

## Disabling Gossip

For air-gap deployments or environments where gossip is not feasible:

```toml
[gossip]
enabled = false
```

See [Air-Gap Deployments](./air-gap.md) for the full air-gap configuration guide.
