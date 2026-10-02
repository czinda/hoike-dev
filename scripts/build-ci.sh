#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p .build/bin
export PATH="$ROOT/.build/bin:$HOME/.cargo/bin:$PATH"

# Workers Builds runs on Ubuntu x86_64. Verify pinned release archives before use.
install_linux_tool() {
  local name="$1" version="$2" url="$3" sha="$4"
  if command -v "$name" >/dev/null && "$name" --version | grep -Fq "$version"; then return; fi
  if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
    echo "Install $name $version, then retry npm run build." >&2
    exit 1
  fi
  local archive="$ROOT/.build/$name.tar.gz"
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$url" -o "$archive"
  printf '%s  %s\n' "$sha" "$archive" | sha256sum --check
  tar -xzf "$archive" -C "$ROOT/.build/bin" "$name"
}

install_linux_tool mdbook 0.5.3 \
  https://github.com/rust-lang/mdBook/releases/download/v0.5.3/mdbook-v0.5.3-x86_64-unknown-linux-gnu.tar.gz \
  e2fd508a4fac06cbaa9f88b97d27bdc3b55a08946304ca845879fe26a3699e11
install_linux_tool mdbook-mermaid 0.17.1 \
  https://github.com/badboy/mdbook-mermaid/releases/download/v0.17.1/mdbook-mermaid-v0.17.1-x86_64-unknown-linux-gnu.tar.gz \
  9afcfa5b8463afe606d48595a7ae338564302903e626ea5b6edb8007d29393a5

if ! command -v rustup >/dev/null; then
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 https://sh.rustup.rs -o .build/rustup-init.sh
  sh .build/rustup-init.sh -y --profile minimal --default-toolchain none --no-modify-path
fi
rustup toolchain install 1.97 --profile minimal
export RUSTUP_TOOLCHAIN=1.97

# AWS-LC needs CMake, which the build image does not guarantee. No root required.
if ! command -v cmake >/dev/null; then
  python3 -m venv .build/cmake-env
  .build/cmake-env/bin/pip install --disable-pip-version-check cmake==4.1.2
  export PATH="$ROOT/.build/cmake-env/bin:$PATH"
fi

REF="$(tr -d '\n\r' < HOIKE_REF)"
[[ "$REF" =~ ^[0-9a-f]{40}$ ]] || { echo 'HOIKE_REF must contain a full Git commit SHA.' >&2; exit 1; }
SOURCE="$ROOT/.build/hoike-source"
if [[ ! -d "$SOURCE/.git" ]]; then
  git init "$SOURCE"
  git -C "$SOURCE" remote add origin https://github.com/czinda/hoike.git
fi
git -C "$SOURCE" fetch --depth 1 origin "$REF"
git -C "$SOURCE" checkout --detach "$REF"
make build HOIKE_REPO="$SOURCE"
