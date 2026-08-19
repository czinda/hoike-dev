# ahu CLI Reference

The `ahu` binary is a standalone tool for working with ahu bundle files.
It does not require a running hoike server or any configuration. All
operations are read-only except `apply`.

## Global options

```
ahu [OPTIONS] <COMMAND>
```

| Option | Description |
|--------|-------------|
| `--version` | Print version information |
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

Verify the seal, digests, and sort order of a bundle.

```
ahu verify <FILE> [OPTIONS]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<FILE>` | Path to the ahu bundle file |

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--entries` | No | false | Also verify each individual entry's OCSP response signature |

### Description

Performs integrity verification of the bundle:

1. **Seal verification** -- checks the cryptographic seal over the entire
   bundle, confirming it has not been modified since signing
2. **Digest verification** -- recomputes content digests and compares
   against the manifest
3. **Sort order** -- confirms the index entries are in sorted order
   (required for binary search at serving time)

With `--entries`, additionally verifies that each individual OCSP response
is properly signed and well-formed. This is more thorough but takes longer
on large bundles.

Exit code 0 on success, non-zero on any verification failure.

### Example

```sh
# Quick verification (seal + digests + sort order)
ahu verify enterprise.ahu

# Full verification including individual entries
ahu verify enterprise.ahu --entries
```

---

## ahu extract

Extract a single pre-signed OCSP response by its CertID entry key.

```
ahu extract <FILE> --certid <HEX>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<FILE>` | Path to the ahu bundle file |

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--certid <HEX>` | Yes | -- | Hex-encoded CertID to look up |

### Description

Performs a binary search of the bundle's sorted index for the given CertID
and writes the matching pre-signed OCSP response to stdout as DER-encoded
bytes.

The CertID is the concatenation of the issuer name hash, issuer key hash,
and serial number that uniquely identifies a certificate in an OCSP
request. Use `ahu inspect` to see available entries.

Returns exit code 0 if found, non-zero if the CertID is not present in the
bundle.

### Example

```sh
# Extract a response and save to file
ahu extract enterprise.ahu \
  --certid 3a7f2b... > response.der

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
ahu apply <BASE> <DELTAS>... -o <OUT>
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

### Description

Applies delta bundles to a base bundle to produce a new full bundle. This
is the incremental update mechanism: instead of transferring a complete
bundle each time, the signer can produce small deltas containing only the
changed entries.

Deltas are applied in the order specified on the command line. The
resulting bundle is a complete, self-contained ahu file that can be served
directly.

The output bundle:

- Contains all entries from the base, with additions and modifications
  from the deltas applied
- Has a new seal computed over the merged content
- Carries the epoch from the last delta applied

### Example

```sh
# Apply a single delta
ahu apply base.ahu delta-42.ahu -o merged.ahu

# Apply multiple deltas in sequence
ahu apply base.ahu delta-42.ahu delta-43.ahu -o merged.ahu

# Verify the result
ahu verify merged.ahu --entries
```
