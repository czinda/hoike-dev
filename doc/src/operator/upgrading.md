# Upgrading

hoike's crate version is still 0.2.0, but the current build carries the October 2026 security-audit remediation (findings F01–F12), and several fixes change behavior that earlier 0.2.0 builds accepted. A configuration, state directory, or procedure that worked before can now fail at load or at startup rather than being silently accepted. This page covers what changes when you move a deployment to the hardened build, and what operators coming from 0.1.x should expect.

The authoritative upstream reference is the [migration contract in the hoike repository](https://github.com/czinda/hoike/blob/main/docs/review-remediation.md).

Start by running the new binary against your existing configuration:

```sh
hoike check --config /etc/hoike/hoike.toml
```

`hoike check` is read-only; it never creates or changes state. Every change below is visible to it.

## Configuration changes

Every configuration table parses with `deny_unknown_fields`. Unknown keys — typos, stale keys, keys removed in this build — fail at load instead of being silently ignored. See [Configuration Reference](configuration.md).

| Change | Action |
|--------|--------|
| `storage.max_chain` is removed | Delete the key from `[storage]`; a config that sets it fails to parse. Only full, uncompressed bundles are admitted now, so there is no delta-chain depth left to bound. |
| `seal_key` + `seal_cert` pair required for production signing | Every signer/combined CA with `signing_key.type = "file"` or `"pkcs11"` must configure both keys. Exactly one of the two is an error, and so is reusing the OCSP signing key as the seal key. See [Signer Mode](signer.md). |
| `forward_to` must be HTTPS | An `http://` target fails startup and `hoike check` unless `forward_insecure = true` is set explicitly (lab use only). |
| CRL sources require `issuer_cert` | See [CRL sources](#crl-sources) below. |

## State changes

State directories are operator-acknowledged state now, not a cache.

- **`hoike init-state --config PATH` before the first serve.** A fresh state directory must be bootstrapped explicitly; `serve` never creates state implicitly. Existing valid state continues to work unchanged — run this only for new deployments and new state directories.
- **One writer per state directory.** `serve`, `init-state`, and `import` hold an OS-level exclusive `flock` on `.writer.lock` for their full process lifetime; a second writer is rejected immediately. Stop the previous writer before starting a new one.
- **Missing or corrupt state is a recovery error**, never a silent fresh timeline that forgets recorded high-water marks. Recovery means restoring from backup.
- **Back up and restore the state directory as one unit** — marks, snapshots, and lock file together. See [Anti-Rollback Protection](anti-rollback.md).
- **Old binaries are not qualified to read the new snapshot state.** Once the new build has written state, do not point an older binary at the same directory.

## Bundle admission

Admission is fail-closed. Before upgrading edge nodes:

- **Provision seal trust on every node that receives bundles from elsewhere** — `seal_signer_pins`, `seal_trust_anchors`, or `seal_authorizations` under `[storage]`. A node with no trust configured refuses bundles at startup instead of loading them with a warning. See [Seal Trust Policy](seal-trust.md).
- **Only full, uncompressed bundles are admitted.** Delta bundles, delta chains, tombstones, and compression are rejected before any durable state change. Materialize deltas into a full bundle with `ahu apply` first.
- `storage.allow_unauthenticated_bundles = true` (default `false`) is the escape hatch for local demos: it permits structure-only admission, and only when no other trust is configured. Configured trust never downgrades to it.

## Gossip authentication

`gossip.auth_mode` defaults to `"required"`: unsigned, unknown, and forged broadcasts are dropped, and `identity_key` is mandatory. A non-empty legacy `peer_keys` fails configuration with migration instructions — replace it with `peer_identities` before anything else.

Fleets upgrading from builds without broadcast authentication should follow the four-step rollout in [Gossip Configuration](gossip.md):

1. Provision per-node identities and complete `peer_identities` fleet-wide.
2. Set `auth_mode = "permissive"` — unsigned legacy broadcasts are accepted, signed ones verified, unknown or forged ones rejected.
3. Configure `identity_key` on every node.
4. Set `auth_mode = "required"` fleet-wide.

Mixed fleets stay interoperable at the frame level while you roll this out.

## Import

`hoike import` is an offline, authenticated, recoverable installation:

```sh
hoike import --bundle /media/usb/enterprise.ahu \
              --ca enterprise-issuing-01 \
              --config /etc/hoike/hoike.toml
```

- `--force` is removed. Import refuses an active writer by design, so stop `hoike serve` first.
- The bundle is authenticated under the configured seal trust and scope authorizations, even when `allow_unauthenticated_bundles` permits unauthenticated demo serving.
- State must already have been initialized with `hoike init-state`.
- The source is read exactly once, the generation snapshot is immutable, and the state descriptor commits atomically before the bundle path is published. A failure before the commit leaves the previous generation byte-for-byte intact.

See [Air-Gap Deployments](air-gap.md) for the full media-transfer workflow.

## ahu verify and ahu apply

`ahu verify` no longer reports success without verifying the seal. A bare invocation fails; choose a mode:

```sh
ahu verify bundle.ahu --config /etc/hoike/hoike.toml   # authenticated under configured trust
ahu verify bundle.ahu --structure-only                 # structure and digests only
```

`--entries` adds per-response OCSP signature checks via the embedded responder keys, and requires `--config`.

`ahu apply` produces an unsigned intermediate by default; a checksum is not a CMS seal. A sealed, installable result requires authenticated inputs plus the seal pair:

```sh
ahu apply base.ahu delta.ahu -o merged.ahu \
  --seal-key seal.p8 --seal-cert seal.crt \
  --input-signer-pin seal-signer.crt
```

## CRL sources

`issuer_cert` is required for every CRL source and is enforced at startup and by `hoike check`. It is trusted configuration: its subject and public key must match the CA identity the bundle is scoped to. A config that omits it fails to start. See [Revocation Sources](revocation-sources.md).

## 0.1.x and supported versions

hoike's security policy supports 0.2.x only; 0.1.x is unsupported. 0.2 still reads material produced by 0.1:

- 0.1 bundles load under the same admission rules — the ahu 0.1 wire profile is unchanged.
- Legacy cookie-only sync state is ignored; the dogtag-sync source runs one full directory refresh after the upgrade.
- Valid legacy state JSON remains readable; existing state continues to work unchanged.

## Upgrade sequence

1. Validate the configuration with the new binary: `hoike check --config /etc/hoike/hoike.toml` (read-only).
2. Fix the configuration: remove `max_chain`, add `seal_key`/`seal_cert` pairs, add CRL `issuer_cert`, migrate `peer_keys` to `peer_identities`.
3. Provision seal trust on every edge that receives bundles from another machine.
4. Stop the old writer, then start the new binary. New state directories need `hoike init-state` first.
5. In gossip fleets, run the [four-step authentication rollout](gossip.md) once the binary upgrade is done.
