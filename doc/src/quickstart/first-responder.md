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
state_db   = "/tmp/hoike-demo/state"
max_chain  = 24

[[ca]]
label          = "demo-ca"
bundle_file    = "/tmp/hoike-demo/bundles/demo-ca.ahu"
nonce_policy   = "ignore"
completeness   = "authoritative-complete"
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
- All referenced bundle files exist and pass seal verification
- The storage directories are accessible
- Gossip seeds (if configured) are reachable

Fix any reported issues before proceeding.

## 3. Start the responder

Launch the OCSP responder:

```sh
hoike serve --config /tmp/hoike-demo/hoike.toml
```

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

## 5. Test with curl

OCSP also supports HTTP GET with a base64-encoded request in the URL path.
For a quick connectivity check:

```sh
# Health check (if supported)
curl -s http://localhost:2560/health
```

## Understanding the response path

When the edge server receives an OCSP request, it:

1. Parses the request to extract the `CertID` (issuer name hash, issuer
   key hash, and serial number)
2. Looks up the `CertID` in the ahu bundle's sorted index via binary
   search
3. Returns the pre-signed response bytes directly from the memory-mapped
   bundle

There is no cryptographic work at request time. The response was fully
signed during the `hoike sign` step. The edge node is keyless.

## Stopping the server

```sh
# If running in the foreground, press Ctrl+C
# If running in the background:
kill %1
```

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
