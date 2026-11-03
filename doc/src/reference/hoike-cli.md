# hoike CLI Reference

The `hoike` binary is the main entry point for the OCSP responder. It
provides six subcommands: `serve`, `init-state`, `check`, `sign`, `import`,
and `query`.

## Global options

```
hoike [OPTIONS] <COMMAND>
```

| Option | Description |
|--------|-------------|
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

In **edge mode**, the server loads bundle files into memory and serves
responses at memory-read speed with no cryptographic work at request time.

If gossip is enabled in the configuration, the server also starts a SWIM
protocol listener for fleet coordination and bundle distribution.

### Example

```sh
hoike serve --config /etc/hoike/hoike.toml
```

---

## hoike init-state

Initialize a fresh state directory.

```
hoike init-state --config <PATH>
```

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--config <PATH>` | Yes | -- | Path to the `hoike.toml` configuration file |

### Description

One-time bootstrap for the state directory. `hoike serve` never creates
state implicitly: on a fresh deployment, run `hoike init-state` once
before the first `hoike serve`.

Initialization is the operator's acknowledgment that the directory is new.
Existing state or recovery material in the directory is refused, and there
is no `--force` reset -- to recover a lost state directory, restore the
anti-rollback marks and bundle snapshots together. The command holds the
state directory's exclusive writer lock while initializing, so it cannot
race a concurrent writer.

### Example

```sh
hoike init-state --config /etc/hoike/hoike.toml
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
| `--issuer <FILE>` | Yes | -- | Issuer certificate (PEM or DER) for CertID computation. CRL sources require independent issuer authorization: the CRL signature must verify under this certificate |
| `--signing-key <FILE>` | * | -- | PKCS#8 PEM/DER signing key. Mutually exclusive with `--demo-key`. |
| `--demo-key` | * | false | Use an ephemeral key (testing only). Mutually exclusive with `--signing-key`. |
| `-o <FILE>` | No | `output.ahu` | Output bundle file path |
| `--sig-alg <ALG>` | No | `ecdsa-p256` | Signature algorithm (see below) |
| `--certid-compat <MODE>` | No | `dual` | CertID hash compatibility mode (see below) |
| `--epoch <N>` | No | `1` | Epoch number for anti-rollback |
| `--good-serials <FILE>` | No | -- | File of hex serial numbers to mark as good |
| `--issuer-name-b64 <B64>` | No | derived from `--issuer` | Base64-encoded DER issuer name for correct CertID hashes |
| `--issuer-key-b64 <B64>` | No | derived from `--issuer` | Base64-encoded issuer public key bytes |
| `--seal-key <FILE>` | No | -- | PKCS#8 PEM/DER P-256 seal key, paired with `--seal-cert` or omitted entirely. Required for production signing keys; must be distinct from the signing key |
| `--seal-cert <FILE>` | No | -- | PEM or DER seal certificate matching `--seal-key` |
| `--dual-alg <ALG>` | No | -- | Produce a dual-algorithm bundle alongside `--sig-alg` (e.g., `ml-dsa-87`) |
| `--pq-signing-key <FILE>` | No | -- | PKCS#8 PEM/DER PQ signing key file (required with `--dual-alg`) |

\* One of `--signing-key` or `--demo-key` is required. hoike refuses to sign without an explicit key source.

The seal key and seal certificate are a paired choice: exactly one of the
two is an error, and reusing the OCSP signing key as the seal key is
rejected (the ECDSA signer proves separation by signing a
domain-separated message verified under the seal public key). Production
signing keys (file or PKCS#11) require a complete seal pair; `--demo-key`
generates a distinct ephemeral seal pair instead.

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
neither list produce no bundle entry; serving nodes answer them per their
miss handling (see the [Request Path](../architecture/request-path.md)).

### Epoch numbering

The epoch is a monotonically increasing integer that prevents rollback
attacks. Serving nodes refuse a bundle whose epoch is not greater than the
recorded high-water mark for the CA (an equal epoch is accepted only for an
identical generation, such as a restart replay).

`hoike sign` is offline: it reads no serving state and writes none. There
is no auto-increment -- `--epoch` defaults to `1`, and the operator
supplies the next epoch for the CA explicitly when producing successive
generations.

### Example

```sh
# Production (with PKCS#8 key files and a seal pair)
hoike sign \
  --ca enterprise-issuing-01 \
  --crl /var/lib/pki/ca.crl \
  --issuer /var/lib/pki/ca.crt \
  --signing-key /etc/pki/ocsp-signer.key \
  --seal-key /etc/pki/ocsp-seal.key \
  --seal-cert /etc/pki/ocsp-seal.crt \
  --good-serials /var/lib/pki/good-serials.txt \
  --sig-alg ecdsa-p256 \
  --certid-compat dual \
  --epoch 42 \
  -o /var/lib/hoike/bundles/enterprise.ahu

# Testing (with demo key and ephemeral seal pair)
hoike sign \
  --ca test-ca \
  --crl test.crl \
  --issuer test-ca.crt \
  --demo-key \
  -o test.ahu
```

---

## hoike import

Install a bundle for air-gap or enclave deployments where gossip is not
available.

```
hoike import --bundle <PATH> --ca <LABEL> --config <PATH>
```

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--bundle <PATH>` | Yes | -- | Path to the ahu bundle file to install |
| `--ca <LABEL>` | Yes | -- | Configured CA label whose destination to install into |
| `--config <PATH>` | Yes | -- | Path to hoike.toml (determines the CA destination and state directory) |

### Description

Offline, authenticated, recoverable installation. The import:

1. Verifies the bundle seal and integrity against the configured seal
   trust
2. Checks anti-rollback (epoch) and chain continuity for the CA scope
3. Reads the source bundle once and takes an immutable snapshot
4. Atomically commits the state descriptor and publishes the bundle at
   the CA's destination path

Import is offline by design: it holds the state directory's exclusive
writer lock for the full installation, so it fails promptly while a server
holds the same lock -- stop the writer process first. There is no
`--force`; recovery means restoring the state marks and snapshots
together.

### Example

```sh
hoike import --bundle /mnt/usb/enterprise.ahu \
  --ca enterprise-issuing-01 \
  --config /etc/hoike/hoike.toml
```

---

## hoike query

Query a running OCSP responder with optional algorithm preference
negotiation.

```
hoike query --url <URL> --serial <HEX> --issuer-name-b64 <B64> --issuer-key-b64 <B64> [OPTIONS]
```

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--url <URL>` | Yes | -- | Responder URL (e.g., `http://localhost:2560`) |
| `--serial <HEX>` | Yes | -- | Hex-encoded certificate serial number |
| `--issuer-name-b64 <B64>` | Yes | -- | Base64-encoded DER issuer name |
| `--issuer-key-b64 <B64>` | Yes | -- | Base64-encoded issuer public key bytes |
| `--prefer <ALGS>` | No | -- | Comma-separated preferred algorithms (e.g., `ml-dsa-87,ecdsa-p256`) |

### Description

Builds an OCSP request for the given serial number and issuer, sends it
to the specified responder, and prints the parsed response: per-response
certificate status (**GOOD** / **REVOKED** with reason / **UNKNOWN**),
signature algorithm, timestamps, and nonce handling.

When `--prefer` is specified, the request includes an RFC 6960 §4.4.7.1
`PreferredSignatureAlgorithms` extension built from the comma-separated
algorithm list. This is used to test dual-algorithm bundle negotiation --
requesting `ml-dsa-87` from a responder serving a dual-algorithm bundle
returns the ML-DSA response.

### Example

```sh
# Basic query
hoike query \
  --url http://localhost:2560 \
  --serial 0A1B2C \
  --issuer-name-b64 "..." \
  --issuer-key-b64 "..."

# Query with post-quantum preference
hoike query \
  --url http://localhost:2560 \
  --serial 0A1B2C \
  --issuer-name-b64 "..." \
  --issuer-key-b64 "..." \
  --prefer ml-dsa-87
```
