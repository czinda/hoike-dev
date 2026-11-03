# ahu CLI Reference

The `ahu` binary is a standalone tool for working with ahu bundle files.
It does not require a running hoike server. All operations are read-only
except `apply`.

## Global options

```
ahu [OPTIONS] <COMMAND>
```

| Option | Description |
|--------|-------------|
| `--help` | Print help |

---

## ahu inspect

Display the manifest, scopes, epochs, and entry counts of a bundle.

```
ahu inspect <FILE>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<FILE>` | Path to the ahu bundle file |

### Description

Reads the bundle's CBOR manifest and prints a human-readable summary
including:

- **CA label** and scope identifier
- **Epoch** number
- **Signature algorithm** used for OCSP responses
- **Entry count** (total number of pre-signed responses)
- **CertID compatibility** mode (dual, sha256, sha1)
- **Timestamps** (production time, thisUpdate, nextUpdate)
- **Bundle size** on disk

This command does not verify the bundle's integrity -- use `ahu verify`
for that.

### Example

```sh
ahu inspect /var/lib/hoike/bundles/enterprise.ahu
```

---

## ahu verify

Authenticate a bundle against explicit trust, or check its structure only.

```
ahu verify <FILE> (--config <PATH> | --structure-only) [OPTIONS]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<FILE>` | Path to the ahu bundle file |

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--config <PATH>` | One of the two modes | -- | Config file with the seal trust and scope authorizations to authenticate against |
| `--structure-only` | One of the two modes | false | Check structure and digests only; authenticity is not checked |
| `--entries` | No | false | Also check each entry's OCSP signature with the keys embedded in the responses (requires `--config`) |

### Description

Exactly one verification mode is required -- a bare `ahu verify FILE`
fails rather than defaulting. (An earlier version reported success
without verifying the seal at all, which is why the mode is now explicit.)

- **`--config <PATH>`** (authenticated): the CMS seal must verify and the
  signer certificate must chain to the locally configured trust -- a
  chain carried inside the bundle is never sufficient on its own.
  Structure, digests, and index sort order are checked as well.
- **`--structure-only`**: structural integrity only -- header, manifest
  digests against the index and data sections, and sort order.
  Authenticity is not checked.
- **`--entries`**: additionally verifies each individual OCSP response
  signature using the responder keys embedded in the responses (not
  responder-chain trust). More thorough but takes longer on large
  bundles.

Exit code 0 on success, non-zero on any verification failure.

### Example

```sh
# Authenticated verification
ahu verify enterprise.ahu --config /etc/hoike/hoike.toml

# Structure and digests only (no trust)
ahu verify enterprise.ahu --structure-only

# Full verification including individual entries
ahu verify enterprise.ahu --config /etc/hoike/hoike.toml --entries
```

---

## ahu extract

Extract a single pre-signed OCSP response by its CertID entry key.

```
ahu extract <FILE> --certid <HEX> [-o <FILE>]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<FILE>` | Path to the ahu bundle file |

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--certid <HEX>` | Yes | -- | Hex-encoded entry key (SHA-256 of the DER CertID, 64 hex chars) |
| `-o <FILE>` | No | stdout (hex) | Output file for the raw DER response |

### Description

Performs a binary search of the bundle's sorted index for the given entry
key and writes the matching pre-signed OCSP response to stdout as hex, or
to a file as raw DER bytes with `-o`.

The entry key is the SHA-256 of the DER-encoded CertID (see
[ahu Bundle Format](../architecture/ahu-format.md)). Use `ahu inspect` to
see available entries.

Returns exit code 0 if found, non-zero if the entry key is not present in
the bundle.

### Example

```sh
# Extract a response and save it as DER
ahu extract enterprise.ahu \
  --certid 3a7f2b... -o response.der

# Decode the extracted response with OpenSSL
openssl ocsp -respin response.der -resp_text
```

---

## ahu diff

Show differences between two bundle generations.

```
ahu diff <A> <B>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<A>` | Path to the older (base) bundle |
| `<B>` | Path to the newer bundle |

### Description

Compares two ahu bundles and reports:

- **Added entries** -- CertIDs present in B but not in A
- **Removed entries** -- CertIDs present in A but not in B
- **Changed entries** -- CertIDs present in both but with different
  response content (e.g., status changed from good to revoked)
- **Manifest differences** -- changes in epoch, timestamps, signature
  algorithm, or entry counts

This is useful for auditing what changed between bundle generations before
deploying an update.

### Example

```sh
ahu diff enterprise-epoch41.ahu enterprise-epoch42.ahu
```

---

## ahu apply

Apply one or more delta bundles to a base bundle, producing a new combined
bundle.

```
ahu apply <BASE> <DELTAS>... -o <OUT> [OPTIONS]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<BASE>` | Path to the base bundle |
| `<DELTAS>...` | One or more delta bundle files to apply, in order |

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-o <OUT>` | Yes | -- | Output path for the resulting bundle |
| `--seal-key <FILE>` | No | -- | P-256 PKCS#8 seal key; omit to produce an unsigned intermediate |
| `--seal-cert <FILE>` | No | -- | PEM or DER certificate matching `--seal-key` |
| `--input-signer-pin <FILE>` | No | -- | Trusted input signer certificate (repeat for multiple signers) |

### Description

Applies delta bundles to a base bundle to produce a new full bundle. This
is the incremental update mechanism: instead of transferring a complete
bundle each time, the signer can produce small deltas containing only the
changed entries.

Deltas are applied in the order specified on the command line. The
resulting bundle is a complete, self-contained ahu file.

By default the output is an **unsigned intermediate bundle** -- fine for
inspection, but not installable on a serving node. Passing `--seal-key`
together with `--seal-cert` and at least one `--input-signer-pin` (the
three are required as a set) produces an authenticated, sealed result
suitable for installation.

The output bundle:

- Contains all entries from the base, with additions and modifications
  from the deltas applied
- Is sealed over the merged content when seal material is provided;
  otherwise unsigned
- Carries the epoch from the last delta applied

### Example

```sh
# Apply a single delta (unsigned intermediate)
ahu apply base.ahu delta-42.ahu -o merged.ahu

# Apply multiple deltas in sequence, then seal the result for installation
ahu apply base.ahu delta-42.ahu delta-43.ahu \
  --seal-key seal.key --seal-cert seal.crt \
  --input-signer-pin signer.crt \
  -o merged.ahu

# Verify the result
ahu verify merged.ahu --config /etc/hoike/hoike.toml
```
