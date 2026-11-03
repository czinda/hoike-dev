# Request Path

This page traces an OCSP request from HTTP arrival to response delivery.
Every step on this path is designed for minimal latency: no heap allocation,
no cryptographic work, no database queries. The edge serves pre-signed
bytes from bundles loaded into memory.

## Overview

```mermaid
flowchart TD
    A[HTTP Request] --> B{Method?}
    B -->|GET| C[Base64-decode + URL-decode<br/>path segment]
    B -->|POST| D[Read body<br/>Content-Type: application/ocsp-request]
    C --> E[Size guard]
    D --> E
    E --> F[DER parse<br/>strict, reject non-minimal lengths]
    F --> G{Profile checks}
    G -->|violation| H[malformedRequest]
    G -->|pass| I[Nonce validation<br/>RFC 9654]
    I --> J{Route by CertID}
    J -->|no match| K[unauthorized]
    J -->|match| L[Binary search<br/>sorted index]
    L -->|hit| M[Write stored<br/>octets verbatim]
    L -->|miss| N{Authoritative complete<br/>+ nonce?}
    N -->|yes| S[Sign fresh unknown<br/>(live) or forward<br/>to signer]
    N -->|no| K[unauthorized]
    M --> P[HTTP headers<br/>per RFC 9919]
    K --> P
    S --> P
```

## HTTP method handling

hoike accepts OCSP requests via both GET and POST, as required by RFC 6960
Section 3 and profiled by RFC 9919 Section 6.

### GET requests

The OCSP request is DER-encoded, then base64-encoded, then URL-encoded in
the path segment:

```
GET /AhwwGjAYMBYwFDASBBB...base64...= HTTP/1.1
```

hoike:

1. Extracts the path segment after the base path
2. URL-decodes the segment
3. Base64-decodes (standard alphabet, with padding) to obtain the DER bytes

### POST requests

The OCSP request is sent as the raw body:

```
POST / HTTP/1.1
Content-Type: application/ocsp-request

<DER bytes>
```

hoike reads the body up to the size limit. The `Content-Type` header must
be `application/ocsp-request`.

## Size guard

Before parsing, hoike enforces a maximum request size (`server.max_request`,
default 8192 bytes). OCSP requests are small -- a single-certificate request
is typically 80-120 bytes. A request exceeding the limit is rejected with
`malformedRequest`.

## DER parsing

hoike uses strict DER parsing via the RustCrypto `der` crate:

- **Non-minimal length encodings are rejected.** DER requires that length
  octets use the smallest possible encoding. A length of 127 encoded in
  long form (0x81 0x7F instead of 0x7F) is rejected.
- **Trailing bytes are rejected.** The DER parser must consume the entire
  input.
- **Tag mismatches are rejected.** The parser validates every ASN.1 tag
  against the expected schema.

This strict parsing is a security boundary: it prevents malformed requests
from reaching the routing or lookup logic.

### Parsed structure

The parsed `OCSPRequest` yields:

```
OCSPRequest ::= SEQUENCE {
    tbsRequest      TBSRequest,
    optionalSignature  [0] EXPLICIT Signature OPTIONAL
}

TBSRequest ::= SEQUENCE {
    version         [0] EXPLICIT Version DEFAULT v1,
    requestorName   [1] EXPLICIT GeneralName OPTIONAL,
    requestList     SEQUENCE OF Request,
    requestExtensions [2] EXPLICIT Extensions OPTIONAL
}

Request ::= SEQUENCE {
    reqCert         CertID,
    singleRequestExtensions [0] EXPLICIT Extensions OPTIONAL
}

CertID ::= SEQUENCE {
    hashAlgorithm   AlgorithmIdentifier,
    issuerNameHash  OCTET STRING,
    issuerKeyHash   OCTET STRING,
    serialNumber    CertificateSerialNumber
}
```

## Profile checks

hoike validates the request against the RFC 9919 Lightweight OCSP Profile:

| Check | Rule | Failure |
|-------|------|---------|
| Version | Must be v1 (default) | malformedRequest |
| Request count | Single CertID per request (RFC 9919 Section 4) | malformedRequest |
| Hash algorithm | SHA-256 preferred; SHA-1 accepted for compatibility | malformedRequest if unsupported |
| Signed request | Signature on request is ignored (RFC 9919 Section 4.1) | N/A |

## Nonce validation

If the request contains a nonce extension, hoike first validates its length
per RFC 9654, regardless of policy:

| Nonce length | Behavior |
|--------------|----------|
| 0 octets | `malformedRequest` -- a nonce extension with an empty value is invalid |
| 1 -- 15 octets | Responder MAY omit the nonce from the response |
| 16 -- 32 octets | Responder MUST accept and reflect the nonce |
| 33 -- 128 octets | Responder MAY omit the nonce from the response |
| > 128 octets | `malformedRequest` |

How a valid nonce is then handled is a per-CA policy (`nonce_policy` in the
`[[ca]]` section):

| Policy | Behavior |
|--------|----------|
| `ignore` (default) | Serve the pre-signed response without a nonce; any nonce in the request is ignored. The only policy compatible with pure bundle serving, since pre-signed responses were signed before the request arrived |
| `forward` | The edge forwards nonce-bearing requests to the CA's `forward_to` signer, which signs a fresh response containing the nonce. No-entry requests are also forwarded when the scope is authoritative-complete, so the signer can produce a signed unknown (see below). Requests without a nonce are served from the local bundle |
| `live` | The signer or combined node signs a fresh response containing the nonce for every request. Works with ECDSA file keys and PKCS#11 HSM signing keys; not valid on keyless edges |

See [Nonce Policies](../operator/nonce-policies.md) for the operational
trade-offs between the three.

## CertID routing

The `CertID` from the parsed request is used to route to the appropriate
CA context. Routing uses the **issuerKeyHash** as the primary key, with
**hashAlgorithm** and **issuerNameHash** as validation:

```mermaid
flowchart LR
    CertID --> IKH[issuerKeyHash]
    IKH --> Multimap[IKH multimap]
    Multimap -->|match| CaCtx[CaContext]
    Multimap -->|no match| Unauth[unauthorized]
    CaCtx --> Validate{issuerNameHash<br/>matches?}
    Validate -->|yes| Lookup
    Validate -->|no| Unauth
```

The issuerKeyHash multimap allows a single hoike instance to serve
responses for multiple CAs. Each CA's loaded bundle is associated with
the SHA-256 (and optionally SHA-1) hash of the issuer's Subject Public Key
Info.

## Index lookup

Once a CaContext is selected, hoike looks up the specific certificate in
the ahu bundle's sorted index.

### Entry key computation

The entry key is the SHA-256 hash of the DER-encoded CertID:

```
entry_key = SHA-256(DER(CertID))
```

This hashing step normalizes all CertID variants (SHA-1 vs SHA-256 hash
algorithm) into a uniform 32-byte key.

### Binary search

The index is a sorted array of 48-byte records in the loaded bundle.
hoike performs a standard binary search:

```
Index region (in memory):
+--------+--------+--------+--------+--------+
| rec[0] | rec[1] | rec[2] | ...    | rec[N] |
+--------+--------+--------+--------+--------+
   48 B      48 B     48 B             48 B

Each record:
  [entry_key: 32 B] [offset: 8 B] [length: 4 B] [flags: 2 B] [discriminator: 2 B]
```

Records are sorted by `(entry_key, discriminator)`, so in a dual-algorithm
bundle the ECDSA and ML-DSA variants of the same certificate sit adjacent
and one search finds both. For a bundle with N entries, lookup requires at
most ceil(log2(N)) comparisons:

| Entries | Max comparisons |
|---------|-----------------|
| 1,000 | 10 |
| 100,000 | 17 |
| 1,000,000 | 20 |
| 10,000,000 | 24 |

### Hit: verbatim byte serving

On a hit, the index record yields an offset and length into the data
region. hoike writes those bytes directly to the HTTP response body:

```rust
// Conceptual hot path
let data_slice = &bundle_data[data_start + offset .. data_start + offset + length];
response_body.write_all(data_slice);
```

No deserialization, no re-encoding, no signing. The bytes in the data
region are a complete, valid `OCSPResponse` DER encoding.

### Miss: signed unknown or unauthorized

If the entry key is not found in the index:

- **Authoritative-complete scope, nonce present**: The bundle asserts that
  it contains responses for every certificate issued by this CA, so a serial
  with no stored entry is provably never-issued. A signer or combined node
  signs a fresh RFC 6960 `certStatus: unknown` response on demand (the
  signed-unknown path). A keyless edge with `nonce_policy = "forward"`
  forwards the request to the scope's `forward_to` signer, which synthesizes
  the signed unknown.
- **Authoritative-complete scope, no nonce**: The unsigned `unauthorized`
  error (RFC 9919 Section 3.2.3). A pre-signed bundle cannot carry a nonce,
  so the provably never-issued answer degrades to the unsigned error.
- **Partial scope**: The bundle is a working set, not the full issuance. An
  out-of-scope CertID is answered with the unsigned `unauthorized` error --
  the edge never fabricates a `good` for a serial it cannot see.

## HTTP response headers

hoike sets response headers per RFC 9919 Section 6 and Section 7.2:

```http
HTTP/1.1 200 OK
Content-Type: application/ocsp-response
Last-Modified: Thu, 01 Jan 2026 00:00:00 GMT
Expires: Fri, 02 Jan 2026 00:00:00 GMT
ETag: "a1b2c3d4..."
Cache-Control: max-age=86400, public, no-transform, must-revalidate
Content-Length: 503
```

| Header | Source | RFC |
|--------|--------|-----|
| `Content-Type` | Always `application/ocsp-response` | RFC 6960 Section 3 |
| `Last-Modified` | `thisUpdate` from the OCSP response | RFC 9919 Section 7.2 |
| `Expires` | `nextUpdate` from the OCSP response | RFC 9919 Section 7.2 |
| `ETag` | Hex SHA-256 of the response octets | RFC 9919 Section 7.2 |
| `Cache-Control` | `max-age` derived from nextUpdate minus now | RFC 9919 Section 7.2 |

The `ETag` is quoted and computed over the raw response bytes. This allows
HTTP caches and CDNs to cache OCSP responses efficiently, reducing load on
hoike edge nodes.

## Error responses

| Condition | OCSP response status | HTTP status |
|-----------|----------------------|-------------|
| Unparseable request | `malformedRequest` (1) | 200 |
| Out-of-scope CertID (no matching CA) | `unauthorized` (6) | 200 |
| No entry, partial scope or no nonce | `unauthorized` (6) | 200 |
| No entry, authoritative-complete + nonce | Signed response, `certStatus: unknown` | 200 |
| Request too large | `malformedRequest` (1) | 200 |
| Server error | `internalError` (2) | 200 |

Per RFC 6960, OCSP error responses are returned with HTTP 200 and
`Content-Type: application/ocsp-response`. The OCSP response status byte
within the body conveys the error.
