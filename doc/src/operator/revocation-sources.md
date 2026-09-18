# Revocation Sources

A signer produces bundles from one revocation source per CA. Since 0.2.0 every source is **authenticated**: a CRL must carry a signature that verifies under an independently configured issuer certificate, and a directory population is bound to the identity of the directory it came from. A source that cannot be authenticated never becomes a bundle.

| Source | `type` | Provides | Bundle completeness it can support |
|--------|--------|----------|------------------------------------|
| CRL file | `crl` | revoked serials | `partial` only |
| 389 DS syncrepl | `dogtag-sync` | every issued certificate with status | `partial` or `authoritative-complete` |

## CRL sources

```toml
[[ca]]
label = "enterprise-ca"

[ca.source]
type        = "crl"
path        = "/var/lib/hoike/crl/enterprise-ca.crl"   # DER or PEM
issuer_cert = "/etc/hoike/trust/enterprise-ca.crt"      # required
```

`issuer_cert` is **trusted configuration**, not a certificate discovered alongside the CRL. Its subject and public key must match the CA identity the bundle is scoped to; a mismatch is a configuration error. The standalone `hoike sign` command takes the same certificate through `--issuer`.

### Verification profile

| Check | Behaviour |
|-------|-----------|
| Signature | Must verify under `issuer_cert`. Supported: ECDSA P-256 with SHA-256; RSA PKCS#1 v1.5 with SHA-256/384/512 and 2048–8192-bit keys; ML-DSA-44/65/87. RSA-PSS and P-384 are rejected explicitly. |
| Issuer binding | CRL issuer name must equal the certificate subject; the authority key identifier, when present, must match. |
| Validity window | `thisUpdate` must be in the past and `nextUpdate` in the future, with a small clock-skew allowance. An expired or future-dated CRL is rejected; the previous bundle stays in service. |
| Delta and indirect CRLs | Rejected. hoike only consumes complete, direct CRLs. |
| Critical extensions | Unknown critical extensions cause rejection rather than being ignored. |

### Freshness and response validity

The signed response window is derived from the source, never the other way round. `validity_secs` and batch jitter can shorten a response's `nextUpdate` but cannot extend it past the CRL's own `nextUpdate`. If a CA publishes short-lived CRLs, `batch_interval` must be shorter still; `hoike check` warns when the configured interval cannot keep responses fresh.

### Why a CRL is always `partial`

A CRL enumerates revocations; it says nothing about which serials were ever issued. hoike therefore cannot distinguish "issued and good" from "never issued" and marks CRL-derived bundles `completeness = "partial"`. Unknown serials receive an `unknown` response, never `good`. Do not set `authoritative-complete` on a CRL source; the signer refuses it.

## 389 DS syncrepl sources

The `dogtag-sync` source (build with `--features dogtag-sync`) performs RFC 4533 content synchronization against a Dogtag or Red Hat Certificate System certificate repository in 389 Directory Server. The initial refresh loads the full population; later refreshes send a sync cookie and receive only changes.

```toml
[ca.source]
type              = "dogtag-sync"
ldap_url          = "ldaps://ds.pki.example.com:636"
base_dn           = "ou=certificateRepository,ou=ca,o=pki-ca-CA"
bind_dn           = "uid=hoike-reader,ou=people,o=pki-ca-CA"
bind_password_env = "HOIKE_LDAP_PASSWORD"          # prefer over bind_password
filter            = "(objectClass=certificateRecord)"
tls               = "ldaps"                        # see TLS and Mutual TLS
ca_cert           = "/etc/hoike/tls/ds-ca.pem"
cookie_path       = "/var/lib/hoike/state/enterprise-ca.sync"
```

Grant the bind identity **read-only** access to the repository subtree. hoike requests only `cn`, `serialno`, `certStatus`, `revokedOn`, `revReason`, and `notAfter`; it does not need the certificate blobs. `notAfter` supplies each certificate's expiry, which is what makes `archive_cutoff_secs` effective on this source.

### Status mapping

| Directory `certStatus` | Bundle entry |
|------------------------|--------------|
| `VALID` | `good` |
| `REVOKED`, `REVOKED_EXPIRED` | `revoked`, with `revokedOn` as the revocation time and `revReason` as the reason; a missing or unparsable time or reason fails the refresh |
| `INVALID`, `EXPIRED` | excluded from positive issuance (responders answer `unknown`) |
| missing or unrecognised | error — the refresh fails and no bundle is published |

A missing or unknown status is never treated as `good`.

### Checkpoints

The population and the sync cookie are checkpointed **together**, atomically, in a file whose name is derived from `cookie_path` plus the source identity (endpoint, base, filter, bind identity, transport, CA identity — never the password). On restart the checkpoint restores the population and resumes incremental sync. A cookie that belongs to a different source identity, or a legacy cookie-only file from 0.1.x, is ignored and a full refresh runs. Only the directory's `syncRefreshRequired` result triggers a full refresh otherwise.

Operational consequences:

- Size the signer's storage and refresh window for a **full** repository load; it will happen after migration and after any source-identity change.
- Back up and restore the state directory as one unit; the checkpoint and the anti-rollback marks must stay consistent.
- Run one signer process per state directory and one active signer per CA. hoike serializes within a process but does not fence competing processes.

### Pruning expired entries (`archive_cutoff_secs`)

Because syncrepl delivers each certificate's `notAfter`, a directory-backed CA can bound bundle size by dropping long-expired certificates:

```toml
[[ca]]
label               = "enterprise-ca"
archive_cutoff_secs = 2592000   # drop entries expired more than 30 days ago
```

An entry is pruned only when its `notAfter` is known **and** `notAfter + archive_cutoff_secs` is already in the past. Entries with unknown expiry are never dropped, so a revoked certificate can never silently degrade to `unknown`. This is why the feature is a **no-op for CRL sources** (a CRL carries no per-certificate expiry) — `hoike check` warns if you set `archive_cutoff_secs > 0` on a CRL-backed CA. The default `0` disables pruning.

### `authoritative-complete`

Because syncrepl delivers positive issuance data, a directory-backed CA may set:

```toml
[[ca]]
label        = "enterprise-ca"
completeness = "authoritative-complete"
```

With this setting a serial that is absent from the population is answered `good`-less — the responder returns `unknown` — but the bundle's manifest asserts that the population is complete, which downstream tooling can use to treat `unknown` as "not issued". The assertion is only made when a refresh **succeeds**; a failed or partial refresh keeps the previous generation and its completeness claim. Set it only when the bind identity's scope, base DN, and filter demonstrably cover every certificate the CA issues.

## Migration from 0.1.x

| Change | Action |
|--------|--------|
| `issuer_cert` is mandatory for CRL sources | Add it, or the signer refuses to start |
| Cookie-only sync files are ignored | Expect one full directory refresh after upgrade |
| `partial` is now the default completeness | Explicitly set `authoritative-complete` where it was previously implied |
| Delta and indirect CRLs no longer accepted | Point `path` at the complete CRL |
