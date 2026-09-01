# Revocation Sources

hoike supports two revocation source adapters for the signer tier. Each `[[ca]]` section declares its source via the `[ca.source]` table.

## CRL Ingest

The simplest adapter. Reads a DER- or PEM-encoded CRL from a local file path:

```toml
[[ca]]
label  = "enterprise-ca"
source = { type = "crl", path = "/var/lib/hoike/crls/enterprise.crl" }
completeness = "partial"
```

The signer re-reads the CRL file on every batch cycle. An external process (cron, certmonger, or a webhook) is responsible for keeping the CRL file up to date.

**Limitation:** A CRL tells you who is revoked but not who was ever issued. CRL-sourced scopes cannot be `authoritative-complete` and cannot safely return `good` for an arbitrary serial. They must be `partial` — unknown serials return `unauthorized`. Pair with `--good-serials` to produce `good` responses for known certificates.

## 389 DS Syncrepl (RFC 4533)

The syncrepl adapter connects to a Dogtag 389 DS instance and synchronizes the full certificate repository via RFC 4533 Content Synchronization. This is the **positive issuance source** — it enumerates every issued certificate, enabling `authoritative-complete` bundles.

```toml
[[ca]]
label        = "dogtag-ca"
completeness = "authoritative-complete"

[ca.source]
type              = "dogtag-sync"
ldap_url          = "ldap://ds.pki.example:3389"
base_dn           = "ou=certificateRepository,ou=ca,o=pki-ca-CA"
bind_dn           = "cn=Directory Manager"
bind_password_env = "HOIKE_LDAP_PASSWORD"
filter            = "(objectClass=certificateRecord)"
cookie_path       = "/var/lib/hoike/syncrepl-cookie"
```

### Configuration fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | string | — | Must be `"dogtag-sync"` |
| `ldap_url` | string | **required** | LDAP URL for the 389 DS instance |
| `base_dn` | string | **required** | Search base for the certificate repository |
| `bind_dn` | string | `"cn=Directory Manager"` | Bind DN for authentication |
| `bind_password` | string | — | Bind password (prefer `bind_password_env`) |
| `bind_password_env` | string | — | Environment variable containing the bind password |
| `filter` | string | `"(objectClass=certificateRecord)"` | LDAP search filter |
| `cookie_path` | string | — | Path for the sync cookie checkpoint file |

### How it works

1. **Initial sync:** The adapter performs a full refresh, enumerating all certificate records. Certificate statuses are mapped: `VALID`→Good, `REVOKED`→Revoked (with reason and time), `REVOKED_EXPIRED`→Revoked, `EXPIRED`/`INVALID`→skipped.

2. **Incremental sync:** On subsequent batch cycles, the adapter uses the sync cookie for incremental updates. Only changed records are processed. The cookie is persisted to `cookie_path` across signer restarts.

3. **Positive issuance:** Because the adapter sees every issued certificate (not just revoked ones), it can confirm that a serial was never issued. This enables `authoritative-complete` bundles.

### Choosing between CRL and syncrepl

| Factor | CRL | Syncrepl |
|--------|-----|----------|
| Completeness | Partial only | Authoritative-complete |
| Setup complexity | Simple (file on disk) | Requires LDAP connectivity |
| CA compatibility | Any CA that produces CRLs | Dogtag / Red Hat Certificate System |
| Positive issuance | No | Yes |
| Incremental updates | Re-reads entire CRL | RFC 4533 cookie-based deltas |
