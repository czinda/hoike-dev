# Testing

hoike has 311 tests on the default build (338 with `--features tls,metrics,pkcs11,dogtag-sync`) across 6 crates covering unit, integration, end-to-end, conformance, seal verification, bundle admission, state locking and installation, ML-DSA, key rotation, and live nonce signing.

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

- Accept a bundle with an epoch above the current high-water mark
- Reject a bundle with a lower epoch (rollback)
- Accept an identical generation on restart (same epoch, identical manifest digest)
- Reject two bundles claiming the same epoch with different content (fork)
- Accept any epoch on a first run with no prior state
- Keep marks unchanged when persistence or a reload fails, and recover committed snapshots

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
conformance::good_serial_returns_successful
conformance::revoked_has_reason
conformance::nextupdate_present
conformance::responder_id_by_key
conformance::unauthorized_on_unknown
conformance::nonce_0_malformed
conformance::nonce_1_accepted
conformance::nonce_15_accepted
conformance::nonce_16_must_accept
conformance::nonce_32_must_accept
conformance::nonce_33_accepted
conformance::nonce_128_accepted
conformance::nonce_129_malformed
conformance::http_content_type
conformance::http_content_type_on_error
conformance::http_cache_control
conformance::http_etag
conformance::error_no_caching
conformance::get_method
conformance::sha256_certid_supported
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

## Test data and fixtures

Test certificates, keys, CRLs, and bundles are generated inline by each
suite's helpers — for example `build_conformance_bundle` in
`crates/hoike-server/tests/conformance.rs` and `make_bundle` in
`crates/hoike-core/tests/anti_rollback.rs` — so `cargo test` works from a
fresh clone with no separate generation step.

Shared committed fixtures live in `testdata/`:

| Path | Contents |
|------|----------|
| `testdata/hoike-test.toml` | Test configuration |
| `testdata/wire-profile-0.1/` | Independently generated golden vectors for the frozen ahu 0.1 wire profile (minimal-full and dual-algorithm bundles) |

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

5. Update the conformance check table in
   `doc/src/compliance/rfc-support.md`

## Continuous integration

CI (`.github/workflows/ci.yml` in the repository) runs:

- **Check and lint** — the web UI is built first (`npm ci`, `tsc --noEmit`,
  `vite build`) so the all-features clippy gate (which includes the
  `embed-webui` feature) always compiles against a real UI build; then
  `cargo check --workspace --locked`, a `pkcs11` feature check, all-features
  clippy with `-D warnings`, and `cargo fmt --check`.
- **Test matrix** — the default workspace suite runs on stable and nightly
  (nightly is allowed to fail); the stable leg additionally runs the feature
  suite (`--features tls,metrics,pkcs11,dogtag-sync`), the runtime-independent
  ahu profile (`cargo check`/`cargo test -p ahu --no-default-features`), and a
  release-mode parser regression
  (`overflowing_entry_offsets_never_panic_in_heap_or_mmap`).
- **Platform matrix** — the state-machine suites (`state_lock`,
  `anti_rollback`, and `installation` in hoike-core) run on both Linux and
  macOS, because flock-based writer exclusion, strict state reopen, and
  durable installation behave differently across kernels; both platforms are
  required before release.
- **Security audit** — `cargo audit` runs against the lockfile on `main` and
  on a monthly schedule; it is currently green (zero vulnerabilities, one
  non-fatal unmaintained-crate warning).

CI also builds release binaries for four targets, publishes a container
image to GHCR, and cuts releases on `v*` tags.
