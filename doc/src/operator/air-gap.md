# Air-Gap Deployments

hoike supports air-gapped (enclave) deployments where there is no network connectivity between the signer and edge nodes. Bundles are transferred via removable media, and the edge serves responses using byte-identical code — there is no special air-gap binary.

## When to Use Air-Gap Mode

Air-gap deployments are appropriate for:

- **Classified networks** where no data path exists between the signing environment and the serving environment
- **High-security enclaves** with strict network segmentation requirements
- **Compliance regimes** that mandate physical separation of key material from internet-facing infrastructure
- **Disaster recovery** environments where gossip infrastructure is unavailable

## Configuration

Air-gap mode is simply an edge with gossip disabled:

```toml
[server]
mode   = "edge"
listen = "0.0.0.0:2560"

[storage]
bundle_dir = "/var/lib/hoike/bundles"
state_db   = "/var/lib/hoike/state"

[gossip]
enabled = false

[[ca]]
label          = "enterprise-issuing-01"
certid_compat  = "dual"
nonce_policy   = "ignore"
```

Everything else is standard edge configuration — the same `[[ca]]` sections, the same `[storage]` layout, the same serving behavior.

## Bundle Import Workflow

```mermaid
flowchart LR
    A[Signer produces bundle] --> B[Copy to removable media]
    B --> C[Physical transfer]
    C --> D["Verify: ahu verify bundle.ahu"]
    D --> E["Import: hoike import *.ahu"]
    E --> F[Edge serves responses]
```

### Step by Step

1. **Signer produces bundles** on the signing network as usual (via `batch_interval` scheduling).

2. **Copy bundles to removable media.** USB drives, optical discs, or any physically transferable storage.

3. **Physically transfer the media** to the air-gapped network following your site's security procedures.

4. **Verify bundles before importing.** On the air-gapped edge (or a verification workstation on the air-gapped network):

   ```bash
   ahu verify /media/usb/bundles/*.ahu
   ```

5. **Import the verified bundles:**

   ```bash
   hoike import /media/usb/bundles/*.ahu
   ```

   The import command copies the bundle files into `bundle_dir` and triggers a reload.

## Verification with `ahu verify`

Always verify bundles before importing. `ahu verify` checks three things:

| Check | What it validates |
|-------|-------------------|
| **CMS seal** | Cryptographic signature over the bundle is valid |
| **Epoch chain** | Epoch number is consistent — no rollback, no fork |
| **Manifest integrity** | CBOR manifest is well-formed and content matches the digest |

```bash
$ ahu verify bundle-epoch-42.ahu
✓ CMS seal valid (signer: CN=OCSP Signer, O=Example Corp)
✓ Epoch 42 — chain consistent
✓ Manifest integrity OK (sha-256)
```

If verification fails, do **not** import the bundle. Investigate the cause — possible media corruption, tampering, or a stale bundle from the wrong signer.

## Byte-Identical Serving Code

The edge binary is exactly the same regardless of how bundles arrive:

- Via gossip pull from the signer
- Via manual file copy (e.g., `scp`)
- Via `hoike import` from removable media

There is no compile-time flag, no special air-gap mode in the binary, and no runtime code-path divergence. The only difference is configuration: `gossip.enabled = false`.

This means security auditors can verify a single binary for all deployment models.

## Operational Considerations

### Plan Import Frequency Around Validity Windows

Bundles have a `validity` window (default 24h). You must import fresh bundles **before the current bundle expires**, or the edge will start returning stale responses that relying parties may reject.

The **signer outage budget** — the maximum time you can go without producing a new bundle — is:

```
outage_budget = validity - batch_interval
```

With defaults (24h validity, 1h batch interval), you have a 23-hour window. For air-gap, plan your physical transfer cadence well within this window. A common approach: transfer bundles daily with a 24h validity, giving you a full day of margin.

### state_db Must Persist

The `state_db` directory stores epoch high-water marks. It **must persist** across restarts, even in air-gap mode. If `state_db` is lost:

- The node loses its anti-rollback protection
- It becomes vulnerable to rollback attacks until it loads a current-epoch bundle
- See [Anti-Rollback Protection](./anti-rollback.md) for details

### Prefer Full Bundles

In gossip-connected deployments, hoike uses delta bundles for efficient incremental updates. In air-gap mode:

- Delta bundles require the base bundle to already be present
- Tracking the delta chain across physical transfers adds operational complexity
- **Recommendation:** Transfer full bundles only. The size overhead is acceptable for the operational simplicity.

### No Automatic Urgent Revocation

In gossip-connected deployments, urgent revocations trigger immediate delta production and gossip notification. In air-gap mode, there is no notification channel. If an urgent revocation occurs:

1. The signer produces the off-cycle delta bundle as usual
2. You must physically transfer it to the air-gapped network
3. The edge cannot serve the updated revocation status until the import completes

Plan your incident response procedures to account for the physical transfer latency.
