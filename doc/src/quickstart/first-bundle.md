# Your First Bundle

This walkthrough creates a test CA, generates a CRL, signs an ahu bundle,
and inspects the result. By the end you will have a working bundle ready to
serve OCSP responses.

## 1. Generate a test CA and certificates

Use OpenSSL to create a minimal CA for testing. In production you would
use your organization's existing CA infrastructure.

```sh
mkdir -p /tmp/hoike-demo && cd /tmp/hoike-demo

# Create a CA key and self-signed certificate
openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -new -x509 -key ca.key -out ca.crt -days 365 \
  -subj "/CN=Demo Issuing CA/O=Hoike Test"

# Create an OCSP signing key and certificate
openssl ecparam -name prime256v1 -genkey -noout -out ocsp.key
openssl req -new -key ocsp.key -out ocsp.csr \
  -subj "/CN=Demo OCSP Signer/O=Hoike Test"
openssl x509 -req -in ocsp.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out ocsp.crt -days 365 \
  -extfile <(echo "extendedKeyUsage=OCSPSigning")

# Issue a few end-entity certificates
for i in 1 2 3; do
  openssl ecparam -name prime256v1 -genkey -noout -out "ee${i}.key"
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
  --issuer-cert ca.crt \
  --signer-cert ocsp.crt \
  --signer-key ocsp.key \
  --crl ca.crl \
  --good-serials good-serials.txt \
  --sig-alg ecdsa-p256 \
  --certid-compat dual \
  --epoch 1 \
  --output demo-ca.ahu
```

This reads the CRL for revocation data, marks the serials in
`good-serials.txt` as good, signs each OCSP response with the OCSP signing
key, and packages everything into `demo-ca.ahu`.

**Flag summary:**

| Flag | Value | Meaning |
|------|-------|---------|
| `--ca` | `demo-ca` | Label for this CA scope in the bundle |
| `--sig-alg` | `ecdsa-p256` | Signature algorithm for OCSP responses |
| `--certid-compat` | `dual` | Produce both SHA-256 and SHA-1 CertID entries |
| `--epoch` | `1` | Monotonic epoch number for anti-rollback |

## 5. Inspect the bundle

Use `ahu inspect` to examine the bundle metadata:

```sh
ahu inspect demo-ca.ahu
```

You should see output showing the manifest (CA label, epoch, entry count,
signature algorithm, timestamps) and a summary of the scopes and response
counts.

## 6. Verify the bundle

Run a full verification of the seal, digests, and sort order:

```sh
ahu verify demo-ca.ahu
```

To also verify each individual entry:

```sh
ahu verify demo-ca.ahu --entries
```

A successful verification confirms that the bundle has not been tampered
with and that all entries are correctly signed and ordered.

## What you have now

- `demo-ca.ahu` -- a signed ahu bundle containing pre-signed OCSP
  responses for three certificates (two good, one revoked)
- The bundle is self-describing: it carries all the metadata an edge node
  needs to serve responses without any external configuration

## Next steps

Head to [Starting the Responder](./first-responder.md) to serve these
responses over HTTP.
