# Installation

hoike produces two binaries:

| Binary | Size | Purpose |
|--------|------|---------|
| `hoike` | ~8 MB | OCSP responder, signer, config checker |
| `ahu` | ~1 MB | Bundle inspection, verification, diffing, patching |

## Prerequisites

- **Rust 1.85+** (install via [rustup](https://rustup.rs/))
- A C linker (provided by Xcode CLT on macOS, `build-essential` on Debian/Ubuntu, `gcc` on Fedora/RHEL)

Verify your Rust version:

```sh
rustc --version
# rustc 1.85.0 (... 2025-...)
```

## Build from source

Clone the repository and build in release mode:

```sh
git clone https://github.com/czinda/hoike.git
cd hoike
cargo build --release
```

The binaries are placed in `target/release/`:

```sh
ls -lh target/release/hoike target/release/ahu
```

Copy them to a directory on your `PATH`:

```sh
sudo install -m 755 target/release/hoike /usr/local/bin/
sudo install -m 755 target/release/ahu /usr/local/bin/
```

Verify the installation:

```sh
hoike --version
ahu --version
```

## Container build

A `Containerfile` is provided for building a minimal container image:

```sh
podman build -t hoike .
```

Or with Docker:

```sh
docker build -t hoike .
```

Run the container with your configuration and bundle directory mounted:

```sh
podman run -d \
  --name hoike \
  -p 2560:2560 \
  -v /etc/hoike/hoike.toml:/etc/hoike/hoike.toml:ro \
  -v /var/lib/hoike/bundles:/var/lib/hoike/bundles:ro \
  hoike serve --config /etc/hoike/hoike.toml
```

## Build individual crates

If you only need the bundle library (for example, to integrate ahu into
another tool):

```sh
cargo build --release -p ahu
```

Or just the CLI without gossip support:

```sh
cargo build --release -p hoike-cli --no-default-features
```

## Next steps

With hoike and ahu installed, proceed to
[Your First Bundle](./first-bundle.md) to create a signed ahu bundle from
a test CA.
