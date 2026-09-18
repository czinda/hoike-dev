# Web UI

hoike includes a React + PatternFly 6 web dashboard for monitoring and managing the OCSP responder. The UI is served at `/ui/` alongside the OCSP protocol endpoints.

## Pages

| Page | Description |
|------|-------------|
| **Dashboard** | Server mode, uptime, total entries, bundle count. Per-CA status table with rotation indicators. |
| **Bundles** | Bundle inventory table. Reload button. Detail view per CA. Inspect page for uploaded bundles. |
| **CAs** | Per-CA list with algorithm, nonce policy, cert expiry, rotation status. Detail view with config and action buttons. |
| **Signing** | Trigger signing operations (combined/signer mode only). Per-CA sign buttons. |
| **Query** | OCSP query form with serial, issuer hashes, and algorithm preference. Displays parsed results. |
| **Gossip** | Cluster membership status (when gossip is enabled). |
| **Config** | Read-only view of the running configuration (passwords and keys redacted). |

## Setup

### Development mode (disk serving)

Build the UI and configure hoike to serve from disk:

```sh
cd webui
npm install
npm run build    # Produces webui/dist/
```

Add to `hoike.toml`:

```toml
[server.webui]
static_dir = "/path/to/hoike/webui/dist"
```

For hot-reload during development:

```sh
cd webui
npm run dev      # Starts Vite on http://localhost:9000
```

The Vite dev server proxies `/api/admin` to `http://localhost:2560`.

### Production mode (embedded binary)

Build with the `embed-webui` feature to bake the UI into the binary:

```sh
cd webui && npm run build
cd .. && cargo build --release --features embed-webui
```

Add `[server.webui]` to your config (without `static_dir`) to enable the embedded UI:

```toml
[server.webui]
# No static_dir — served from embedded binary
```

### Authentication

The webui requires `[server.admin]` to be configured with at least one operator. The login page authenticates against the admin API and stores a session token in the browser's `sessionStorage`.

Role-based access controls which pages and actions are available:

| Role | Visible pages | Actions |
|------|---------------|---------|
| Administrator | All | Sign, rotate, reload, view config |
| Operator | All except config details | Sign, reload |
| Viewer | Dashboard, Bundles, CAs, Query, Gossip | Read-only |

## Technology stack

- React 19 + TypeScript
- PatternFly 6 (Red Hat's design system)
- Vite 6 (build tool)
- react-router-dom 7 (client-side routing)
- Pure React state management (useState, useEffect, useContext)
