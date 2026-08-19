# Combined Mode

Combined mode runs both signer and edge in a single process. It uses the same code paths as separate signer and edge deployments — the signer loop produces ahu bundles, and the edge serving path loads and serves them — all within one binary.

## When to Use Combined Mode

Combined mode is appropriate for:

- **Small deployments** with a single CA and low request volume
- **Development and testing** where simplicity matters more than isolation
- **Proof of concept** before committing to a split architecture
- **Single-server environments** where running two processes is unnecessary

Combined mode is **not recommended** when:

- You need key isolation (signing keys live on the serving node)
- You require high availability (single point of failure)
- You need horizontal scaling of the edge tier
- Your security policy requires the signer to be network-isolated or air-gapped

## Configuration

Set `mode = "combined"` in the `[server]` section. The configuration must include both signing material (the `[[ca]]` sections with key references) and storage paths for bundles and state.

```toml
[server]
mode   = "combined"
listen = "0.0.0.0:2560"

[storage]
bundle_dir = "/var/lib/hoike/bundles"
state_db   = "/var/lib/hoike/state"

[[ca]]
label          = "internal-ca"
source         = { type = "crl", path = "/var/lib/hoike/crls/internal.crl" }
signing        = "ca-direct"
sig_alg        = "ecdsa-p256"
responder_id   = "by-key"
certid_compat  = "dual"
nonce_policy   = "ignore"
validity       = "24h"
batch_interval = "1h"
jitter         = "2h"
```

## Same Code Paths

Combined mode is not a separate implementation. It instantiates the same signer task and the same edge serving logic that run independently in split deployments. This makes combined mode useful for **validating your configuration** before splitting into a signer + edge topology — if it works in combined mode, it will work when split.

The signer task writes bundles to `bundle_dir` on its normal schedule. The edge path watches `bundle_dir` for new bundles and loads them, exactly as a standalone edge would.

## Gossip in Combined Mode

Gossip can be enabled in combined mode, but it is rarely useful. Since the signer and edge share a process, bundles are available immediately — there is no fleet to coordinate. If you plan to add standalone edge nodes later, you can enable gossip on the combined node so it acts as a seed for the edges.

```toml
[gossip]
enabled  = true
bind     = "0.0.0.0:7946"
seeds    = []
node_name = "combined-01"
```

## Limitations

| Concern | Impact |
|---|---|
| Key exposure | Signing keys are on the network-facing node |
| Single point of failure | One process crash stops both signing and serving |
| No horizontal scaling | Cannot add edge replicas without deploying separate edge nodes |
| No air-gap | The signer cannot be isolated from the network |

## Migrating to Signer + Edge

When you outgrow combined mode, the migration is straightforward:

1. **Deploy edge nodes.** Install hoike with `mode = "edge"` on one or more edge servers. Point their `bundle_dir` at a location where they can receive bundles (via gossip, scheduled copy, or shared storage).

2. **Enable gossip.** Configure the combined node and the new edges with matching gossip settings. The edges will pull bundles from the combined node.

3. **Verify edge serving.** Confirm that edge nodes are loading bundles and serving responses correctly.

4. **Switch the combined node to signer-only.** Change `mode = "combined"` to `mode = "signer"` on the original node. It will continue producing bundles but stop serving OCSP requests directly.

5. **Update DNS / load balancer.** Point OCSP traffic to the edge nodes instead of the former combined node.

The signer's bundle output format is identical regardless of mode — edges don't know or care whether their bundles came from a combined node or a dedicated signer.
