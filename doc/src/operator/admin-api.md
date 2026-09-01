# Admin API

hoike exposes a REST admin API at `/api/admin/` for monitoring and management. The API uses session-based authentication with role-based access control (RBAC).

## Authentication

Login with username and password to receive a session token:

```sh
curl -X POST http://localhost:2560/api/admin/session \
  -H 'Content-Type: application/json' \
  -d '{"name": "admin", "password": "secret"}'
```

Response:
```json
{
  "session_token": "a1b2c3...",
  "role": "administrator",
  "operator": "admin",
  "expires_in_secs": 3600
}
```

Use the token in subsequent requests:

```sh
curl http://localhost:2560/api/admin/status \
  -H 'Authorization: Bearer a1b2c3...'
```

## Roles

| Role | Permissions |
|------|-------------|
| `administrator` | Full access: config view, sign triggers, rotation commands, bundle reload |
| `operator` | Operational actions: reload bundles, trigger sign, query |
| `viewer` | Read-only: dashboard, bundles, CAs, gossip, config view |

## Endpoints

### Status (Viewer+)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/admin/status` | Server mode, uptime, version, bundle/entry counts |
| `GET` | `/api/admin/bundles` | Bundle inventory with per-scope details |
| `GET` | `/api/admin/bundles/{label}` | Detail for a specific CA's bundle |
| `GET` | `/api/admin/certs` | Per-CA responder certificate status |
| `GET` | `/api/admin/rotation` | Per-CA key rotation status |
| `GET` | `/api/admin/gossip` | Gossip cluster membership |
| `GET` | `/api/admin/config` | Running config (sanitized — no keys/passwords) |
| `GET` | `/api/admin/state` | Anti-rollback state (epoch high-water marks) |

### Bundle Operations (Operator+)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/admin/bundles/reload` | Hot-reload all bundles from disk |
| `POST` | `/api/admin/bundles/inspect` | Upload a bundle, return manifest + verify result |
| `POST` | `/api/admin/bundles/verify` | Upload a bundle, return full verification result |

### Signing Operations (Operator+)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/admin/sign/{label}` | Trigger signer pass for a specific CA |
| `POST` | `/api/admin/sign/all` | Trigger signer pass for all CAs |
| `POST` | `/api/admin/rotate/{label}` | Run rotation command for a specific CA (Administrator only) |

### Query (Viewer+)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/admin/query` | OCSP query by serial + issuer hashes |

### Session

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/admin/session` | Login (no auth required) |
| `DELETE` | `/api/admin/session` | Logout |

## Configuration

```toml
[server.admin]
session_ttl_secs = 3600

[[server.admin.operators]]
name          = "admin"
password_hash = "$2b$12$..."   # bcrypt
role          = "administrator"
```

Generate a bcrypt hash:

```sh
htpasswd -nbBC 12 "" 'your-password' | cut -d: -f2
```
