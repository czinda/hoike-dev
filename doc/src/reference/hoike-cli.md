# hoike CLI Reference

The `hoike` binary is the main entry point for the OCSP responder. It
provides four subcommands: `serve`, `check`, `sign`, and `import`.

## Global options

```
hoike [OPTIONS] <COMMAND>
```

| Option | Description |
|--------|-------------|
| `--version` | Print version information |
| `--help` | Print help |

---

## hoike serve

Start the OCSP responder server.

```
hoike serve --config <PATH>
```

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--config <PATH>` | Yes | -- | Path to the `hoike.toml` configuration file |

### Description

Starts the axum-based HTTP server that serves pre-signed OCSP responses
from loaded ahu bundles. The server operates in the mode specified in the
configuration file (`edge`, `signer`, or `combined`).

In **edge mode**, the server memory-maps bundle files and serves responses
at memory-read speed with no cryptographic work at request time.

If gossip is enabled in the configuration, the server also starts a SWIM
protocol listener for fleet coordination and bundle distribution.

### Example

```sh
hoike serve --config /etc/hoike/hoike.toml
```

---

## hoike check

Validate configuration, bundles, and connectivity without starting the
server.

```
hoike check --config <PATH>
```

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--config <PATH>` | Yes | -- | Path to the `hoike.toml` configuration file |

### Description

Performs a comprehensive pre-flight check:

1. **Config parsing** -- validates the TOML configuration syntax and
   structure
2. **Bundle verification** -- for each configured `[[ca]]` entry, verifies
   the referenced bundle file exists and passes seal verification
3. **Storage access** -- confirms `bundle_dir` and `state_db` directories
   exist and are writable
4. **Gossip connectivity** -- if gossip is enabled, attempts to resolve
   and connect to seed nodes

Reports issues with clear error messages. Exit code 0 on success, non-zero
on failure.

### Example

```sh
hoike check --config /etc/hoike/hoike.toml
```

---

## hoike sign

Produce a signed ahu bundle from a CRL and optional good-serials list.

```
hoike sign --ca <LABEL> --crl <FILE> [OPTIONS]
```

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--ca <LABEL>` | Yes | -- | CA scope label for the bundle |
| `--crl <FILE>` | Yes | -- | Path to the CRL file (PEM or DER) |
| `--issuer-cert <FILE>` | Yes | -- | CA certificate (issuer) |
| `--signer-cert <FILE>` | Yes | -- | OCSP signing certificate |
| `--signer-key <FILE>` | Yes | -- | OCSP signing private key |
| `--output <FILE>` | No | `<label>.ahu` | Output bundle file path |
| `--sig-alg <ALG>` | No | `ecdsa-p256` | Signature algorithm (see below) |
| `--certid-compat <MODE>` | No | `dual` | CertID hash compatibility mode (see below) |
| `--epoch <N>` | No | auto | Epoch number for anti-rollback |
| `--good-serials <FILE>` | No | -- | File of hex serial numbers to mark as good |

### Signature algorithms (`--sig-alg`)

| Value | Algorithm | Key type |
|-------|-----------|----------|
| `ecdsa-p256` | ECDSA with P-256/SHA-256 | EC P-256 |
| `ml-dsa-44` | ML-DSA-44 (FIPS 204) | ML-DSA-44 |
| `ml-dsa-65` | ML-DSA-65 (FIPS 204) | ML-DSA-65 |
| `ml-dsa-87` | ML-DSA-87 (FIPS 204) | ML-DSA-87 |

The ML-DSA algorithms provide post-quantum signing. Use these when your
PKI deployment requires quantum-resistant certificate status.

### CertID compatibility (`--certid-compat`)

| Value | Behavior |
|-------|----------|
| `dual` | Produce both SHA-256 and SHA-1 CertID entries for each certificate. Maximizes client compatibility. |
| `sha256` | SHA-256 CertID entries only. Standards-compliant but may not work with older clients. |
| `sha1` | SHA-1 CertID entries only. Legacy compatibility mode. |

### Good-serials file format

A plain text file with one hex-encoded serial number per line:

```
01A3F2
01A3F3
01B7C0
```

Certificates listed here are marked as **good** in the OCSP responses.
Certificates found in the CRL are marked as **revoked**. Certificates in
neither list are treated according to the CA's completeness policy.

### Epoch numbering

The epoch is a monotonically increasing integer that prevents rollback
attacks. Edge nodes refuse to load a bundle with an epoch lower than the
currently loaded one. If `--epoch` is not specified, the signer
auto-increments from the previous bundle's epoch.

### Example

```sh
hoike sign \
  --ca enterprise-issuing-01 \
  --issuer-cert /etc/pki/ca.crt \
  --signer-cert /etc/pki/ocsp-signer.crt \
  --signer-key /etc/pki/ocsp-signer.key \
  --crl /var/lib/pki/ca.crl \
  --good-serials /var/lib/pki/good-serials.txt \
  --sig-alg ecdsa-p256 \
  --certid-compat dual \
  --epoch 42 \
  --output /var/lib/hoike/bundles/enterprise.ahu
```

---

## hoike import

Import a bundle for air-gap or enclave deployments where gossip is not
available.

```
hoike import --bundle <PATH> [OPTIONS]
```

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--bundle <PATH>` | Yes | -- | Path to the ahu bundle file to import |
| `--config <PATH>` | No | -- | Path to hoike.toml (for target directory resolution) |
| `--force` | No | false | Skip epoch and seal checks during import |

### Description

Copies an ahu bundle into the configured bundle directory and registers
it with the state database. This is the manual alternative to gossip-based
bundle distribution.

The import process:

1. Verifies the bundle seal and integrity
2. Checks that the epoch is greater than any currently loaded bundle for
   the same CA scope
3. Copies the bundle to `bundle_dir`
4. Updates the state database

Use `--force` to bypass epoch and seal checks (for disaster recovery or
initial bootstrap only).

### Example

```sh
# Standard import
hoike import --bundle /mnt/usb/enterprise.ahu \
  --config /etc/hoike/hoike.toml

# Force import (disaster recovery)
hoike import --bundle /mnt/usb/enterprise.ahu \
  --config /etc/hoike/hoike.toml --force
```
