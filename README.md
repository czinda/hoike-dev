# hoike.dev

Documentation website for [hoike](https://github.com/czinda/hoike), deployed as
Cloudflare Workers Static Assets from [czinda/hoike-dev](https://github.com/czinda/hoike-dev).

## Push-to-deploy

Cloudflare Workers Builds connects this repository to the `hoike-dev` Worker:

- **Production branch:** `main`
- **Root directory:** `/`
- **Build command:** `npm run build`
- **Deploy command:** `npx wrangler deploy`
- **Build caching:** enabled
- **Hostnames:** `hoike.dev` and `www.hoike.dev`

A push to `main` installs the locked npm dependencies, builds the site, validates the
generated output, and deploys only if the build succeeds. Cloudflare uses its stored
build token; a developer does not need a local API token to publish a Git commit.
Inspect the **Workers Builds: hoike-dev** check on GitHub or the Worker's **Builds** tab.

The build produces:

1. The landing page and favicon from this repository.
2. The mdBook documentation from `doc/`, including Mermaid support.
3. Rust API documentation from the exact public `czinda/hoike` commit in `HOIKE_REF`.
4. `/build-info.json` containing both source commit IDs and the build timestamp.

Changes in `czinda/hoike` alone do not deploy this site. To update the Rust API reference,
change `HOIKE_REF` to a reviewed full commit SHA and push that change here. The build uses
a separate checkout and target directory under `.build/`, so it does not alter a developer's
adjacent hoike working tree or generated files.

## Local build

Use Node.js 22+, mdBook 0.5.3, mdbook-mermaid 0.17.1, a C/C++ compiler, and CMake.
The build script installs Rust 1.97 through rustup if necessary. In the Cloudflare Linux
build image, it also installs checksum-verified documentation tools and CMake when absent.

```bash
npm ci
npm run build
npm run dev
```

`npm run build` includes checks for required pages, metadata, and asset limits. To inspect
an existing generated tree, use `npm run check`. For manual builds against a local Rust
checkout, use `make build HOIKE_REPO=../hoike`.

For a manual production deployment with authenticated Wrangler:

```bash
npm run deploy
npm run smoke -- https://hoike.dev "$(git rev-parse HEAD)"
npm run smoke -- https://www.hoike.dev "$(git rev-parse HEAD)"
```

The smoke checks verify actual documentation content and the deployed Git commit, not
just HTTP 200 responses. The Rust API root has its own index page rather than relying on
a static hosting fallback to the landing page.

## Hosting and rollback

Static assets are served directly at the edge; the site does not run an OCSP responder
inside a Worker and does not need D1 or a runtime signing key.

The Worker owns the `hoike.dev/*` and `www.hoike.dev/*` routes. The existing proxied DNS
records and the previous `hoike-dev` Pages deployment are retained as a fallback. Worker
routes take precedence over that origin. Removing both Worker routes restores the Pages
site; a subsequent Worker deployment re-applies the routes from `wrangler.jsonc`.

For a normal content rollback, revert the Git commit and push to `main`, or roll back the
Worker version in Cloudflare. Do not run `wrangler pages deploy` for routine releases.
