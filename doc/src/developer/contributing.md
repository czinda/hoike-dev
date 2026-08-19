# Contributing

This guide covers the development workflow, code style, architecture
rules, and licensing requirements for contributing to hoike.

## Development workflow

1. **Fork and clone** the repository
2. **Create a feature branch** from `main`:
   ```sh
   git checkout -b feature/my-change
   ```
3. **Make your changes** following the guidelines below
4. **Run the full check suite** before committing:
   ```sh
   cargo fmt --check
   cargo clippy --workspace
   cargo test --workspace
   ```
5. **Commit** with a clear message (see [Commit messages](#commit-messages))
6. **Open a pull request** against `main`

## Code style

hoike uses `rustfmt` for formatting and `clippy` for linting.

### Formatting

Format all code before committing:

```sh
cargo fmt
```

The workspace includes a `rustfmt.toml` with project-specific settings.
Do not override these in individual crates.

### Linting

Run clippy with default settings:

```sh
cargo clippy --workspace
```

Fix all warnings. Clippy lints should not be suppressed with
`#[allow(...)]` unless there is a documented reason in a comment.

### Naming

- Types: `PascalCase`
- Functions and methods: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`
- Modules: `snake_case`
- Crate names: `kebab-case` (e.g., `hoike-core`)

### Documentation

All public items must have doc comments (`///`). Include:

- A one-line summary
- Any important invariants or panics
- Examples for non-obvious usage

## Architecture boundaries

These boundaries are load-bearing. Violating them breaks the licensing
model, the security model, or both.

### ahu must not depend on server crates

The `ahu` crate is a pure data-format library. It must **never** depend on:

| Forbidden dependency | Reason |
|---------------------|--------|
| `tokio` | No async runtime in a format library |
| `hyper` | No HTTP in a format library |
| `axum` | No web framework in a format library |
| `PKCS#11` bindings | No HSM coupling in a format library |
| Any GPL-licensed crate | `ahu` is Apache-2.0 OR MIT |

If you need async I/O for bundle operations, put it in `hoike-core` or
`hoike-sign`, not in `ahu`.

### Dependency flow is strictly downward

```
hoike-cli -> hoike-server -> hoike-core -> ahu
                          -> hoike-gossip
          -> hoike-sign   -> hoike-core -> ahu
```

No crate may depend on a crate above it in this graph. Specifically:

- `ahu` depends on nothing in the hoike workspace
- `hoike-core` depends only on `ahu`
- `hoike-sign` depends on `ahu` and `hoike-core`
- `hoike-server` depends on `hoike-core` and `hoike-gossip`
- `hoike-gossip` depends on nothing in the hoike workspace (uses foca)
- `hoike-cli` depends on `hoike-server` and `hoike-sign`

### No signing at request time

The edge path (hoike-server) must never perform cryptographic signing
operations. It reads pre-signed bytes from memory-mapped bundles and writes
them directly to the response. If you find yourself importing signing
functions into hoike-server, the design is wrong.

## Licensing

hoike uses a split licensing model:

| Crate | License | SPDX |
|-------|---------|------|
| `ahu` | Apache License 2.0 OR MIT | `Apache-2.0 OR MIT` |
| `hoike-core` | GNU General Public License v3.0 or later | `GPL-3.0-or-later` |
| `hoike-sign` | GNU General Public License v3.0 or later | `GPL-3.0-or-later` |
| `hoike-server` | GNU General Public License v3.0 or later | `GPL-3.0-or-later` |
| `hoike-gossip` | GNU General Public License v3.0 or later | `GPL-3.0-or-later` |
| `hoike-cli` | GNU General Public License v3.0 or later | `GPL-3.0-or-later` |

### Why the split?

The `ahu` bundle format is intended to be an open standard that any project
can implement. The permissive dual license (Apache-2.0 OR MIT) allows other
OCSP responders, certificate authorities, and PKI tools to read and write
ahu bundles without GPL obligations.

The server components are GPL because hoike's operating logic (routing,
signing policy, batch production) is the core intellectual contribution.

### Adding dependencies

When adding a dependency to `ahu`, verify that its license is compatible
with Apache-2.0 and MIT. Common compatible licenses:

- MIT
- Apache-2.0
- BSD-2-Clause, BSD-3-Clause
- ISC
- Zlib

GPL, LGPL, MPL-2.0, and AGPL dependencies are **not** compatible with
`ahu`. They may be used in the GPL-licensed crates.

## Commit messages

Use conventional-style messages:

```
<type>(<scope>): <summary>

<body>

<trailers>
```

### Types

| Type | Use for |
|------|---------|
| `feat` | New functionality |
| `fix` | Bug fixes |
| `refactor` | Code restructuring without behavior change |
| `test` | Adding or modifying tests |
| `docs` | Documentation changes |
| `chore` | Build, CI, dependency updates |

### Scope

Use the crate name as scope: `ahu`, `core`, `sign`, `server`, `gossip`,
`cli`. Use `workspace` for cross-cutting changes.

### Examples

```
feat(sign): add ML-DSA-87 signing support

Implement FIPS 204 ML-DSA-87 key generation and signing in the batch
production path. Adds tests for round-trip sign-bundle-verify.

Assisted-by: Claude Code (claude.ai/code)
```

```
fix(server): reject overlong nonces per RFC 9654

Nonces longer than 32 octets were accepted and silently ignored.
Now returns malformedRequest as required by RFC 9654 Section 4.

Assisted-by: Claude Code (claude.ai/code)
```

## AI attribution policy

hoike follows Red Hat's AI attribution guidelines:

| Situation | Trailer |
|-----------|---------|
| Human-directed work with AI assistance | `Assisted-by: Claude Code (claude.ai/code)` |
| Large generated blocks with minimal human edit | `Generated-by: Claude Code (claude.ai/code)` |

**Never** use `Co-Authored-By:` for AI tools -- this has CLA and
contributor statistics implications.

Include the appropriate trailer in every commit that involved AI
assistance.

## Pull request checklist

Before submitting a PR, verify:

- [ ] `cargo fmt --check` passes
- [ ] `cargo clippy --workspace` has no warnings
- [ ] `cargo test --workspace` passes (all 81+ tests)
- [ ] `cargo doc --workspace --no-deps` builds without warnings
- [ ] New public APIs have doc comments
- [ ] New behavior has test coverage
- [ ] Commit messages follow the convention above
- [ ] `ahu` crate has no new server-side dependencies
- [ ] License headers are correct for the crate being modified

## Reporting issues

File issues on the [GitHub issue tracker](https://github.com/czinda/hoike/issues).
Include:

- hoike version (`hoike --version`)
- Rust version (`rustc --version`)
- Operating system
- Steps to reproduce
- Expected vs. actual behavior
- Relevant configuration (redact any private key paths)
