# Your First Bundle

This walkthrough creates a test CA, generates a CRL, signs an ahu bundle,
and inspects the result. By the end you will have a working bundle ready to
serve OCSP responses.

## 1. Generate a test CA and certificates

Use OpenSSL to create a minimal CA for testing. In production you would
use your organization's existing CA infrastructure.

```sh
mkdir -p /tmp/hoike-demo && cd /tmp/hoike-demo

# Create a CA key and self-signed certificate (genpkey emits PKCS#8,
# the format hoike's key loaders accept)
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ca.key
openssl req -new -x509 -key ca.key -out ca.crt -days 365 \
  -subj "/CN=Demo Issuing CA/O=Hoike Test"

# Create the OCSP signing key. hoike signs responses with this key; the
# one-shot `hoike sign` command does not embed a responder certificate.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ocsp.key

# Create a separate seal key and certificate for the CMS bundle seal.
# The seal key must be distinct from the OCSP signing key; hoike enforces
# the separation.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out seal.key
openssl req -new -x509 -key seal.key -out seal.crt -days 365 \
  -subj "/CN=Demo Bundle Sealer/O=Hoike Test"

# Issue a few end-entity certificates
for i in 1 2 3; do
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "ee${i}.key"
  openssl req -new -key "ee${i}.key" -out "ee${i}.csr" \
    -subj "/CN=server${i}.example.com/O=Hoike Test"
  openssl x509 -req -in "ee${i}.csr" -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out "ee${i}.crt" -days 180
done
```

## 2. Create a CRL

Revoke one certificate and generate a CRL that hoike will consume:

```sh
# Set up a minimal CA database
touch index.txt
echo '01' > crlnumber

# Create an openssl.cnf for CRL generation
cat > openssl.cnf <<'EOF'
[ca]
default_ca = demo_ca

[demo_ca]
database       = ./index.txt
crlnumber      = ./crlnumber
default_md     = sha256
default_crl_days = 30
EOF

# Revoke ee3
openssl ca -config openssl.cnf -revoke ee3.crt \
  -keyfile ca.key -cert ca.crt

# Generate the CRL
openssl ca -config openssl.cnf -gencrl \
  -keyfile ca.key -cert ca.crt -out ca.crl
```

## 3. Create a good-serials file

hoike needs to know which serial numbers should be marked as "good." Extract
the serial numbers from the non-revoked certificates:

```sh
for i in 1 2; do
  openssl x509 -in "ee${i}.crt" -noout -serial | cut -d= -f2
done > good-serials.txt

cat good-serials.txt
```

## 4. Sign an ahu bundle

Now use `hoike sign` to produce the bundle:

```sh
hoike sign \
  --ca demo-ca \
  --crl ca.crl \
  --good-serials good-serials.txt \
  --issuer ca.crt \
  --signing-key ocsp.key \
  --seal-key seal.key \
  --seal-cert seal.crt \
  --sig-alg ecdsa-p256 \
  --certid-compat dual \
  --epoch 1 \
  -o demo-ca.ahu
```

This reads the CRL for revocation data, marks the serials in
`good-serials.txt` as good, signs each OCSP response with the signing
key, seals the bundle with the seal key, and packages everything into
`demo-ca.ahu`.

> **Note:** `--signing-key` or `--demo-key` is required; hoike refuses to
> sign without an explicit key source. File-key signing additionally
> requires a complete seal pair: pass both `--seal-key` and `--seal-cert`,
> or neither. A half-configured pair is an error, and the signing key is
> never implicitly reused for sealing. `--demo-key` (with no seal inputs)
> generates a distinct ephemeral seal pair for testing.

**Flag summary:**

| Flag | Value | Meaning |
|------|-------|---------|
| `--ca` | `demo-ca` | Label for this CA scope in the bundle |
| `--signing-key` | `ocsp.key` | PKCS#8 signing key file (or use `--demo-key` for testing) |
| `--seal-key` | `seal.key` | PKCS#8 P-256 key for the CMS bundle seal; paired with `--seal-cert` (pass both or neither) |
| `--seal-cert` | `seal.crt` | PEM or DER seal certificate matching the seal key |
| `--sig-alg` | `ecdsa-p256` | Signature algorithm (also: `ml-dsa-44`, `ml-dsa-65`, `ml-dsa-87`) |
| `--certid-compat` | `dual` | Produce both SHA-256 and SHA-1 CertID entries |
| `--epoch` | `1` | Monotonic epoch number for anti-rollback |
| `--issuer` | `ca.crt` | Issuer certificate (PEM or DER) for automatic CertID computation |
| `--dual-alg` | `ml-dsa-87` | Produce a dual-algorithm bundle alongside `--sig-alg` |
| `--pq-signing-key` | `pq.key` | PKCS#8 PQ signing key (required with `--dual-alg`) |

## 5. Inspect the bundle

Use `ahu inspect` to examine the bundle metadata:

```sh
ahu inspect demo-ca.ahu
```

You should see output showing the manifest (CA label, epoch, entry count,
signature algorithm, timestamps) and a summary of the scopes and response
counts.

## 6. Verify the bundle

Verification requires an explicit mode. For a structural check of the
digests and sort order:

```sh
ahu verify demo-ca.ahu --structure-only
```

This prints `Structure valid; authenticity not checked.` on success — it
does not authenticate the bundle. To authenticate the CMS seal, provision
seal trust in a configuration file first (the next page does exactly
this by pinning `seal.crt`) and run:

```sh
ahu verify demo-ca.ahu --config hoike.toml
```

A bare `ahu verify demo-ca.ahu` fails; it does not discover
configuration. To also verify each individual entry's OCSP signature via
the embedded responder keys, add `--entries` (requires `--config`):

```sh
ahu verify demo-ca.ahu --config hoike.toml --entries
```

A successful authenticated verification confirms that the bundle has not
been tampered with and that all entries are correctly signed and ordered.

## What you have now

- `demo-ca.ahu` -- a signed ahu bundle containing pre-signed OCSP
  responses for three certificates (two good, one revoked)
- The bundle is self-describing: it carries the responses, index, and
  manifest an edge node needs to serve them. The edge still needs a
  configured seal trust policy before it will admit the bundle; the next
  page sets that up by pinning `seal.crt`

## Next steps

Head to [Starting the Responder](./first-responder.md) to serve these
responses over HTTP.
