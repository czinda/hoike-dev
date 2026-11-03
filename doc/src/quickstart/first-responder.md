# Starting the Responder

This guide picks up from [Your First Bundle](./first-bundle.md). You will
create a minimal configuration, validate it, start the responder, and test
it with an OpenSSL OCSP client.

## 1. Create a configuration file

Create a minimal `hoike.toml` for edge mode (serving pre-signed responses):

```toml
[server]
mode        = "edge"
listen      = "0.0.0.0:2560"
max_request = 8192

[storage]
bundle_dir = "/tmp/hoike-demo/bundles"
state_db   = "/tmp/hoike-demo/state/state.json"
# Pin the demo seal certificate so the edge authenticates the bundle's
# CMS seal on admission. Admission is fail-closed: without configured
# seal trust, the edge refuses to serve the bundle.
seal_signer_pins = ["/tmp/hoike-demo/seal.crt"]

[[ca]]
label          = "demo-ca"
bundle_file    = "/tmp/hoike-demo/bundles/demo-ca.ahu"
nonce_policy   = "ignore"
# The bundle was produced from a CRL, which enumerates revocations but not
# issuance, so its scope is partial. A serial with no entry is answered
# with the unsigned `unauthorized` error -- see Revocation Sources.
completeness   = "partial"
```

Set up the directories and move the bundle into place:

```sh
mkdir -p /tmp/hoike-demo/bundles /tmp/hoike-demo/state
cp /tmp/hoike-demo/demo-ca.ahu /tmp/hoike-demo/bundles/
```

Save the configuration as `/tmp/hoike-demo/hoike.toml`.

## 2. Validate the configuration

Before starting the server, run `hoike check` to validate the
configuration, bundle integrity, and connectivity:

```sh
hoike check --config /tmp/hoike-demo/hoike.toml
```

This verifies:

- The configuration file parses correctly
- All referenced bundle files exist and pass seal verification under the
  same admission trust policy (`hoike check` is read-only; it never
  creates or changes state)
- The storage directories are accessible
- Gossip seeds (if configured) are reachable

Fix any reported issues before proceeding.

## 3. Initialize state and start the responder

hoike never creates anti-rollback state implicitly. Initialize the state
directory once, then launch the OCSP responder:

```sh
hoike init-state --config /tmp/hoike-demo/hoike.toml
hoike serve --config /tmp/hoike-demo/hoike.toml
```

`init-state` bootstraps a fresh state directory and refuses to run against
one that is already initialized (there is no `--force`). `serve` holds an
exclusive writer lock on the state directory for the life of the process,
so only one hoike process may write a given state directory at a time.

You should see log output indicating the server is listening on port 2560
and has loaded the `demo-ca` bundle. The server is now ready to accept
OCSP requests.

To run in the background:

```sh
hoike serve --config /tmp/hoike-demo/hoike.toml &
```

## 4. Test with OpenSSL

Use `openssl ocsp` to query the responder for the status of one of the
issued certificates:

```sh
# Query status of a good certificate
openssl ocsp \
  -issuer /tmp/hoike-demo/ca.crt \
  -cert /tmp/hoike-demo/ee1.crt \
  -url http://localhost:2560 \
  -resp_text
```

You should see a response with status **good**.

Now query the revoked certificate:

```sh
# Query status of the revoked certificate
openssl ocsp \
  -issuer /tmp/hoike-demo/ca.crt \
  -cert /tmp/hoike-demo/ee3.crt \
  -url http://localhost:2560 \
  -resp_text
```

This should return a response with status **revoked**, including the
revocation time from the CRL.

## 5. Test with hoike query

hoike includes a built-in diagnostic client. It takes the CertID preimages
directly -- the issuer's DER-encoded subject Name and the raw issuer public
key bytes -- and computes the hashes itself:

```sh
# Issuer name: the certificate's subject, as DER (the second-to-last
# depth-2 SEQUENCE in the certificate body)
SUBJ_OFF=$(openssl asn1parse -in /tmp/hoike-demo/ca.crt \
  | awk '/d=2/ && /cons/ && /SEQUENCE/ {gsub(/:.*/,"",$1); o[n++]=$1} END{print o[n-2]}')
openssl asn1parse -in /tmp/hoike-demo/ca.crt -strparse "$SUBJ_OFF" \
  -out /tmp/hoike-demo/issuer-name.der -noout
ISSUER_NAME_B64=$(base64 -w0 < /tmp/hoike-demo/issuer-name.der)

# Issuer key: the X9.62 uncompressed point -- the trailing 65 bytes of a
# P-256 SubjectPublicKeyInfo
ISSUER_KEY_B64=$(openssl x509 -in /tmp/hoike-demo/ca.crt -pubkey -noout \
  | openssl ec -pubin -outform DER 2>/dev/null | tail -c 65 | base64 -w0)

# Query status of ee1
SERIAL=$(openssl x509 -in /tmp/hoike-demo/ee1.crt -noout -serial | cut -d= -f2)
hoike query \
  --url http://localhost:2560 \
  --serial "$SERIAL" \
  --issuer-name-b64 "$ISSUER_NAME_B64" \
  --issuer-key-b64 "$ISSUER_KEY_B64"
```

Querying a serial that was never issued (any hex value with no bundle
entry) returns the unsigned `unauthorized` error: the demo scope is
partial, so the responder cannot assert anything about a serial it
cannot see.

## 6. Connectivity checks

The OCSP data plane speaks only OCSP -- there is no `/health` endpoint on
the public port. The queries above are the connectivity check. For
continuous monitoring, configure the dedicated metrics listener
(`server.metrics_listen`, Prometheus format on `/metrics`) and watch that
instead.

## Understanding the response path

When the edge server receives an OCSP request, it:

1. Parses the request to extract the `CertID` (issuer name hash, issuer
   key hash, and serial number)
2. Looks up the `CertID` in the ahu bundle's sorted index via binary
   search
3. Returns the pre-signed response bytes directly from the in-memory
   bundle

There is no cryptographic work at request time. The response was fully
signed during the `hoike sign` step. The edge node is keyless.

## Stopping the server

```sh
# If running in the foreground, press Ctrl+C
# If running in the background:
kill %1
```

## Admin Web UI

If the admin API is configured, you can monitor the responder via a browser. Add to your `hoike.toml`:

```toml
[server.admin]
session_ttl_secs = 3600

[[server.admin.operators]]
name          = "admin"
password_hash = "$2b$12$..."   # bcrypt hash of your password
role          = "administrator"

[server.webui]
static_dir = "/path/to/hoike/webui/dist"
```

Then visit `http://localhost:2560/ui/` to access the dashboard showing bundle status, CA health, rotation status, and more.

## Next steps

You now have a working OCSP responder serving pre-signed responses. From
here you can:

- Read the [Configuration Reference](../operator/configuration.md) for
  all available options
- Set up [Gossip Configuration](../operator/gossip.md) for multi-node
  edge fleets
- Explore the [hoike CLI Reference](../reference/hoike-cli.md) for the
  full set of commands and flags
- Review the [Architecture Overview](../architecture/overview.md) for a
  deeper understanding of the signer/edge split
