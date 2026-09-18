# Audit Logging

hoike emits a structured audit log on a dedicated `tracing` target named `audit`. Every event is a single structured record at `INFO` level with an `event` field and a small set of typed fields; there is no free-text message to parse.

> **Filter caveat.** Audit events pass through the same `RUST_LOG` filter as everything else. The default filter is `info,tower_http=debug`, which includes them. If you tighten logging (for example `RUST_LOG=warn`), add an explicit directive so audit is never silenced: `RUST_LOG=warn,audit=info`.

## Event catalog

| `event` | Emitted by | Fields | Meaning |
|---------|-----------|--------|---------|
| `request_rejected` | edge, OCSP handler | `reason`, `serial` | An OCSP request was refused. Today the only reason is `unauthorized` (request for a CertID under a scope the node is not authorized to serve). |
| `bundle_load_failed` | edge, signer, CLI | `trigger`, `reason`, `ca` (when known) | A bundle was rejected at load. `trigger` is one of `initial_load`, `scheduled_reload`, `admin_reload`, `on_demand_reload`, `on_demand_all_reload`. |
| `signer_generation` | signer | `ca`, `trigger`, `epoch` | A new generation was produced and published. `trigger` is `scheduled`, `on_demand`, or `on_demand_all`. |
| `signer_generation_failed` | signer | `ca` (when known), `trigger`, `error` | Production failed; the previous generation stays in service. |

### `bundle_load_failed` reasons

| `reason` | Cause |
|----------|-------|
| `rollback` | Epoch lower than the persisted high-water mark, or a jump larger than `max_chain` |
| `fork` | Two bundles claim the same epoch with different content — duplicate or compromised signer |
| `bundle` | Malformed container, seal verification failure, or a seal from an unauthorized signer |
| `state` | The anti-rollback state store could not be read or persisted |
| `io` | Filesystem error |
| `other` | Anything else; the accompanying `error` field carries detail |

`rollback` and `fork` are the events a SOC should alert on: both indicate that something other than the authorized signer is trying to influence what the edge serves.

## Output and forwarding

Audit events go to the same subscriber as operational logs, on stdout in the default `tracing` text format:

```
2026-09-17T14:02:11.318Z  INFO audit: event="bundle_load_failed" trigger="scheduled_reload" reason="rollback" ca="enterprise-ca"
```

Fields are `key="value"` pairs after the `audit:` target marker. A JSON formatter and a journald sink are planned; until then, collectors should key on the literal `audit:` marker and parse the `key="value"` pairs.

Under systemd, stdout lands in journald; filter with `journalctl -u hoike -o json | jq 'select(.target=="audit")'`. In containers, the platform's log collector picks up stdout. hoike does not rotate, sign, or persist audit records itself — durability and tamper protection are provided by journald permissions, the collector, and the SIEM. Document those controls as part of the deployment; evaluators and STIG reviewers will ask for them.

## Coverage and planned additions

The current catalog covers the integrity-critical paths (what was loaded, what was signed, what was refused). It does not yet record:

- login success, failure, and logout with operator name and source address;
- the operator behind an admin-triggered reload, sign, or rotate;
- configuration reload;
- role-denied requests (`403`);
- TLS handshake failures on the admin listener.

These are required by the NIAP audit SFRs (FAU_GEN.1/2) and the Application Security and Development STIG and are scheduled for the next release. Fields will be added, not renamed, so existing parsers keep working.

## Metrics are not audit

The Prometheus endpoint (`metrics_listen`, `--features metrics`) exposes counters and gauges for capacity and freshness monitoring. It is aggregate and unauthenticated by design and should not be used as an audit source.
