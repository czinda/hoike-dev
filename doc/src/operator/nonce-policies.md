# Nonce Policies

OCSP nonces allow a client to bind a response to a specific request, preventing replay attacks. hoike supports three nonce policies that trade off between throughput and replay protection. The policy is configured per CA in the `[[ca]]` section.

## The Three Policies

### `ignore` (default)

```toml
[[ca]]
nonce_policy = "ignore"
```

Pre-signed responses contain no nonce. Any nonce in the request is silently ignored — the response is served from the ahu bundle as-is.

This is the default and the best choice for most deployments. Pre-signed responses from ahu bundles cannot include nonces (they were signed before the request arrived), so `ignore` is the only policy compatible with pure bundle serving. It delivers the highest throughput: every request is a simple index lookup with no cryptographic operations at serving time.

RFC 6960 makes nonces optional, and most OCSP clients (including browsers) do not send them.

### `forward`

```toml
[[ca]]
nonce_policy = "forward"
forward_to   = "https://signer.pki.example:2560"
```

The edge proxies nonce-bearing requests to the signer for live signing. The signer produces a fresh response that includes the client's nonce, and the edge relays it back.

Requests **without** a nonce are still served from the local bundle — only nonce-bearing requests are forwarded. This gives you the throughput of pre-signed responses for the common case while satisfying clients that require nonce echo.

The `forward_to` URL is **required** when `nonce_policy = "forward"`. It must point to a signer (or combined-mode node) that has the signing keys for this CA.

### `live`

```toml
[[ca]]
nonce_policy = "live"
```

Every request is signed fresh, including the client's nonce in the response. This provides the strongest replay protection but the lowest throughput — every request requires a signing operation.

**`live` is only valid on signer or combined mode.** Configuring `nonce_policy = "live"` on an edge node is a **startup error**, because edge nodes have no signing keys.

## Choosing a Policy

| Policy | Throughput | Replay protection | Key required on serving node | Network to signer |
|---|---|---|---|---|
| `ignore` | Highest | None (relies on short validity) | No | No |
| `forward` | High (degrades for nonce requests) | For nonce-bearing requests | No | Yes |
| `live` | Lowest | Full | Yes | N/A (is the signer) |

**Use `ignore`** unless you have a specific compliance requirement for nonce echo. Short response validity windows (e.g., 24 hours with 1-hour batch intervals) limit the replay window without nonces.

**Use `forward`** when a compliance framework mandates nonce support but you want to keep edge nodes keyless. The signer must be reachable from every edge that uses `forward`.

**Use `live`** only for small-scale deployments or when compliance requires every response to include a nonce. Since `live` requires signing keys on the serving node, it eliminates the security benefit of the signer/edge split.

## RFC 9654 Nonce Length Validation

Regardless of nonce policy, hoike validates nonce length per RFC 9654 before processing:

| Nonce length | Behavior |
|---|---|
| 0 octets | `malformedRequest` — a nonce extension with empty value is invalid |
| 1 – 15 octets | MAY omit nonce from response |
| 16 – 32 octets | MUST be accepted |
| 33 – 128 octets | MAY omit nonce from response |
| > 128 octets | `malformedRequest` |

Nonces in the 16–32 octet range are the "MUST accept" window defined by RFC 9654. Nonces outside this range but within 1–128 octets are valid requests, but the responder is permitted to omit the nonce from the response.

## Startup Validation

hoike validates nonce policy configuration at startup and refuses to start on invalid combinations:

| Condition | Result |
|---|---|
| `nonce_policy = "live"` on `mode = "edge"` | **Startup error** — edges have no signing keys |
| `nonce_policy = "forward"` without `forward_to` | **Startup error** — no signer URL to proxy to |
| `nonce_policy = "forward"` on `mode = "signer"` | **Warning** — a signer forwarding to itself is valid but unusual |

## Performance Implications

The nonce policy directly affects the serving path:

- **`ignore`**: O(1) hash lookup + O(log n) binary search in the bundle index. No cryptography at serving time.
- **`forward`**: Same as `ignore` for non-nonce requests. Nonce-bearing requests add a network round-trip to the signer plus a signing operation. Latency depends on signer proximity and signing algorithm.
- **`live`**: The signer looks up the CertID status from its loaded bundle (pre-signed response exists → status is known), then builds a fresh `SingleResponse` with that status and the client's nonce in `responseExtensions`, and signs it. This avoids a round-trip to the CA — the signer already has the data. Throughput is bounded by the signing rate (ECDSA P-256: fast; ML-DSA-65: slower).
