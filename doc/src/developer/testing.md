# Testing

hoike has 103 tests across 6 crates covering unit, integration, end-to-end,
conformance, seal verification, ML-DSA, key rotation, and live nonce signing.

## Running all tests

```sh
cargo test --workspace
```

With verbose output:

```sh
cargo test --workspace -- --nocapture
```

With `cargo-nextest` (recommended for faster parallel execution):

```sh
cargo nextest run --workspace
```

## Test categories

### Unit tests

Each crate contains inline unit tests (`#[cfg(test)]` modules) covering
individual functions and types.

```sh
# Run unit tests for a specific crate
cargo test -p ahu
cargo test -p hoike-core
cargo test -p hoike-sign
cargo test -p hoike-server
cargo test -p hoike-gossip
```

### Integration tests

Integration tests are in `tests/` directories within each crate. They test
cross-module behavior using the public API.

#### ahu integration tests

Located in `crates/ahu/tests/`. These cover:

- Bundle creation: write manifest, index, data, and seal
- Bundle reading: parse and verify a bundle from bytes
- Round-trip: create a bundle and read it back
- Index binary search correctness at various sizes
- Delta bundle creation and application
- Corrupt bundle detection (tampered seal, modified data)
- Format version handling

```sh
cargo test -p ahu --tests
```

#### Anti-rollback tests

Located in `crates/hoike-core/tests/anti_rollback.rs`. These verify the
epoch chain enforcement:

- Accept a bundle with epoch > current epoch
- Reject a bundle with epoch <= current epoch (rollback)
- Reject a bundle with incorrect parent hash (fork)
- Accept epoch 1 with null parent hash (initial load)
- Reject epoch 2+ with null parent hash (missing chain)

```sh
cargo test -p hoike-core --test anti_rollback
```

### Conformance suite

Located in `crates/hoike-server/tests/conformance.rs`. This suite
exercises the 20 protocol conformance checks listed in the
[RFC Support Reference](../compliance/rfc-support.md#conformance-test-suite).

The conformance tests spin up an in-process axum server with a test bundle
and exercise the full HTTP request path:

```sh
cargo test -p hoike-server --test conformance
```

Each test function is named after the check it validates:

```
conformance::get_valid_request
conformance::post_valid_request
conformance::post_wrong_content_type
conformance::oversized_request_rejected
conformance::non_minimal_der_rejected
conformance::trailing_bytes_rejected
conformance::multi_certid_rejected
conformance::sha256_certid_response
conformance::sha1_certid_compat
conformance::good_status
conformance::revoked_status_with_reason
conformance::unknown_ca_unauthorized
conformance::unknown_serial_unauthorized
conformance::bykey_responder_id
conformance::nonce_not_echoed
conformance::overlong_nonce_rejected
conformance::content_type_header
conformance::cache_control_header
conformance::etag_header
conformance::last_modified_expires_headers
```

### ML-DSA tests

Located in `crates/hoike-sign/tests/`. These cover post-quantum signing
and verification:

- ML-DSA-44 key generation and response signing
- ML-DSA-65 key generation and response signing
- ML-DSA-87 key generation and response signing
- Bundle creation with ML-DSA signatures
- Bundle verification of ML-DSA seals
- Round-trip: sign with ML-DSA, bundle, load, verify

```sh
cargo test -p hoike-sign -- ml_dsa
```

## Test data generation

The `testdata/generate.rs` script creates test certificates, keys, CRLs,
and serial lists used by the test suite. Run it to regenerate test
fixtures:

```sh
cargo run --example generate -p hoike-cli
```

This produces:

| File | Contents |
|------|----------|
| `testdata/ca.crt` | Test CA certificate (self-signed, P-256) |
| `testdata/ca.key` | Test CA private key |
| `testdata/ocsp.crt` | Delegated OCSP responder certificate |
| `testdata/ocsp.key` | OCSP responder private key |
| `testdata/ee*.crt` | End-entity certificates |
| `testdata/ca.crl` | CRL with one revoked certificate |
| `testdata/good-serials.txt` | Serial numbers of non-revoked certificates |

The test data is committed to the repository so that `cargo test` works
without running the generator first.

## Writing new tests

### Conventions

- Use `#[test]` for synchronous tests
- Use `#[tokio::test]` for async tests (server and gossip crates)
- Name tests descriptively: `fn rejects_overlong_nonce()` not `fn test_3()`
- Put integration tests in `crates/<crate>/tests/`
- Put unit tests inline in the module being tested

### Test helpers

Common test utilities are available in each crate's `tests/` or as
`#[cfg(test)]` modules:

- **`hoike-core`**: Test bundle builder, mock CaContext, sample CertIDs
- **`hoike-server`**: In-process server launcher, HTTP client helpers
- **`ahu`**: Bundle builder with configurable manifest fields

### Example: adding a conformance check

To add a new conformance check:

1. Add the test function to `crates/hoike-server/tests/conformance.rs`
2. Name it after the behavior being verified
3. Use the test server and HTTP client helpers
4. Document the RFC requirement in the test's doc comment

```rust
/// RFC 9919 Section X: <requirement description>
#[tokio::test]
async fn new_conformance_check() {
    let server = TestServer::start().await;
    let response = server.post_ocsp_request(&build_test_request()).await;
    assert_eq!(response.status(), 200);
    // ... verify the specific behavior
}
```

4. Update the conformance check table in
   `doc/src/compliance/rfc-support.md`

## Continuous integration

The CI pipeline runs:

```sh
cargo fmt --check          # Formatting
cargo clippy --workspace   # Lints
cargo test --workspace     # All tests
cargo doc --workspace --no-deps  # Documentation builds
```

All four checks must pass before a pull request can be merged.
