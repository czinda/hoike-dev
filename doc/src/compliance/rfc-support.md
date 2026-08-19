# RFC Support Reference

hoike implements or profiles the following IETF standards. This page lists
every requirement with its implementation status and the relevant
conformance checks.

## Standards matrix

| RFC | Title | Role in hoike | Status |
|-----|-------|---------------|--------|
| [RFC 6960](https://www.rfc-editor.org/rfc/rfc6960) | Online Certificate Status Protocol (OCSP) | Base protocol: request/response format, all status values, extensions | Fully implemented |
| [RFC 9919](https://www.rfc-editor.org/rfc/rfc9919) | Lightweight OCSP Profile for High Volume Environments | Primary operating profile: pre-production, unauthorized semantics, byKey ResponderID, SHA-256 CertID, HTTP caching | Fully implemented |
| [RFC 9654](https://www.rfc-editor.org/rfc/rfc9654) | OCSP Nonce Extension | Nonce length validation, rejection rules | Fully implemented |
| [RFC 5280](https://www.rfc-editor.org/rfc/rfc5280) | Internet X.509 PKI Certificate and CRL Profile | AIA `id-ad-ocsp`, responder certificate profile, `id-pkix-ocsp-nocheck` | Referenced for certificate validation |

## RFC 6960 -- OCSP base protocol

### Request handling

| Requirement | Section | Implementation |
|-------------|---------|----------------|
| Accept GET and POST methods | 3.1 | Both methods handled by axum router |
| DER-encoded request body for POST | 3.1 | Body read and passed to strict DER parser |
| Base64+URL-encoded request for GET | A.1 | Path segment decoded (URL-decode then base64-decode) |
| Parse `OCSPRequest` structure | 4.1.1 | `x509-ocsp` crate with strict DER parsing |
| Support `CertID` with OID-identified hash | 4.1.1 | SHA-256 (primary) and SHA-1 (compatibility) |
| Ignore signed requests in pre-signed mode | 4.1.1 | Signature field parsed but not validated |

### Response production

| Requirement | Section | Implementation |
|-------------|---------|----------------|
| Produce `OCSPResponse` with responseStatus | 4.2.1 | All six status values supported |
| `good` -- certificate is not revoked | 4.2.1 | Generated for serials in good-serials list |
| `revoked` -- certificate is revoked | 4.2.1 | Generated from CRL entries with reason and time |
| `unauthorized` -- responder has no information | 4.2.1 | Returned for unknown serials or CAs |
| `malformedRequest` -- request is invalid | 4.2.1 | Returned for parse failures, profile violations |
| `internalError` -- server fault | 4.2.1 | Returned for unexpected processing errors |
| `BasicOCSPResponse` with `ResponseData` | 4.2.1 | Signed during batch production |
| `producedAt` timestamp | 4.2.1 | Set to batch start time |
| `thisUpdate` and `nextUpdate` per SingleResponse | 4.2.1 | Computed from batch window + jitter |
| `ResponderID` identification | 4.2.3 | `byKey` form only (per RFC 9919) |

### Extensions

| Extension | OID | Implementation |
|-----------|-----|----------------|
| Nonce | 1.3.6.1.5.5.7.48.1.2 | Validated per RFC 9654, not echoed in pre-signed mode |
| `id-pkix-ocsp-nocheck` | 1.3.6.1.5.5.7.48.1.5 | Included in responder certificate profile |

## RFC 9919 -- Lightweight OCSP Profile

This is hoike's primary operating profile. All requirements are mandatory
unless noted.

| Requirement | Section | Implementation |
|-------------|---------|----------------|
| Pre-produced responses (no on-demand signing) | 4 | Core design -- all responses are batch-signed |
| Single CertID per request | 4 | Multi-CertID requests rejected as `malformedRequest` |
| SHA-256 `CertID` hash algorithm | 4 | Default; SHA-1 accepted for compatibility |
| `byKey` ResponderID (SHA-1 hash of responder public key) | 5 | Only form used |
| `unauthorized` for unknown serials | 5 | Returned when serial not in working set |
| No nonce echoing | 5 | Nonces validated but never echoed |
| `Content-Type: application/ocsp-response` | 6 | Set on all responses |
| HTTP `Cache-Control` header | 7.2 | `max-age`, `public`, `no-transform`, `must-revalidate` |
| HTTP `Last-Modified` header | 7.2 | Set to `thisUpdate` |
| HTTP `Expires` header | 7.2 | Set to `nextUpdate` |
| HTTP `ETag` header | 7.2 | Hex SHA-256 of response octets |
| HTTP 200 for all OCSP responses (including errors) | 6 | All OCSP responses returned with HTTP 200 |

## RFC 9654 -- OCSP Nonce Extension

| Requirement | Section | Implementation |
|-------------|---------|----------------|
| Nonce minimum length: 1 octet | 4 | Validated; shorter nonces rejected |
| Nonce maximum length: 32 octets | 4 | Validated; longer nonces rejected |
| Nonce rejection produces error response | 4 | Returns `malformedRequest` when policy is `reject` |

## RFC 5280 -- Certificate and CRL Profile

| Requirement | Section | Implementation |
|-------------|---------|----------------|
| Authority Information Access (AIA) `id-ad-ocsp` | 4.2.2.1 | Used by clients to discover hoike endpoints |
| CRL parsing for revocation status | 5 | CRL entries consumed by signer for revoked status |
| `id-pkix-ocsp-nocheck` in responder cert | 4.2.2.1 | Delegated responder certificates include this extension |

## Conformance test suite

The conformance suite in `crates/hoike-server/tests/conformance.rs`
exercises 20 checks covering the RFC requirements above. Each check
validates a specific protocol behavior:

| # | Check | Validates |
|---|-------|-----------|
| 1 | GET request with valid base64-encoded CertID | RFC 6960 Section 3 / A.1 |
| 2 | POST request with valid DER body | RFC 6960 Section 3 |
| 3 | POST with wrong Content-Type rejected | RFC 6960 Section 3 |
| 4 | Oversized request rejected as malformedRequest | Size guard |
| 5 | Non-minimal DER length encoding rejected | Strict DER parsing |
| 6 | Trailing bytes after request rejected | Strict DER parsing |
| 7 | Multi-CertID request rejected | RFC 9919 Section 4 |
| 8 | SHA-256 CertID returns valid response | RFC 9919 Section 4 |
| 9 | SHA-1 CertID returns valid response (compat) | Backward compatibility |
| 10 | Good status for known, non-revoked serial | RFC 6960 Section 4.2.1 |
| 11 | Revoked status includes reason and time | RFC 6960 Section 4.2.1 |
| 12 | Unknown CA returns unauthorized | RFC 9919 Section 5 |
| 13 | Unknown serial returns unauthorized (authoritative) | RFC 9919 Section 5 |
| 14 | byKey ResponderID used | RFC 9919 Section 5 |
| 15 | Nonce in request not echoed in response | RFC 9919 Section 5 |
| 16 | Overlong nonce rejected | RFC 9654 Section 4 |
| 17 | Content-Type header correct | RFC 9919 Section 6 |
| 18 | Cache-Control header present and correct | RFC 9919 Section 7.2 |
| 19 | ETag header is hex SHA-256 of response | RFC 9919 Section 7.2 |
| 20 | Last-Modified and Expires headers present | RFC 9919 Section 7.2 |

Run the conformance suite:

```sh
cargo test -p hoike-server --test conformance
```

## Non-goals

hoike intentionally does not implement:

- **OCSP stapling (RFC 6066 Section 8):** This is a TLS-server
  responsibility, not a responder behavior. hoike produces responses that
  *can be* stapled by a TLS server.
- **Signed OCSP requests:** The request signature field is parsed but never
  validated. RFC 9919 Section 4.1 explicitly states that signed requests
  are not required in the lightweight profile.
- **OCSP response signing on demand:** All responses are pre-signed during
  batch production. There is no code path for on-demand signing.
