# ScanIt API contract (`/v1`)

This document is the human-readable source. The machine source is `scanit-server/openapi.yaml`
(spec-first, swift-openapi-generator, as in aaru). If they disagree, fix the spec, then this file.

Base URL: `https://api.{{domain}}/v1`. All bodies are JSON, all times are RFC 3339 UTC, and all
money is `{ "amountMinor": 199, "currency": "EUR" }`.

## Error shape (every non-2xx)

```json
{ "code": "invalid_token", "message": "Human readable", "details": {} }
```

## Auth

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/auth/apple` | `{ idToken, nonce, fullName? }` | `Session` |
| POST | `/auth/google` | `{ idToken }` | `Session` |
| POST | `/auth/refresh` | `{ refreshToken }` | `Session` (the refresh token is rotated) |
| POST | `/auth/logout` | `{ refreshToken }` | 204 |
| GET | `/me` | — | `{ id, email?, providers: ["apple","google"], createdAt }` |
| DELETE | `/me` | — | 204. Hard-deletes the user and every row they own. |

`Session = { accessToken, accessTokenExpiresAt, refreshToken, user }`.

The server verifies the ID token signature against the provider JWKS, plus `iss`, `exp` and `aud`.

- `aud` must be one of:
  - Apple: the iOS bundle ID, and the Services ID used by the web and Android flows.
  - Google: the iOS, Android and web client IDs.
- Linking: the same email from both providers does **not** auto-merge accounts in v1 (**OPEN**).

**Later, for Android and web:** `GET /auth/apple/start` and `POST /auth/apple/callback` (Apple `form_post`). These run the Sign in with Apple web flow and redirect back with a one-time code that the client exchanges at `POST /auth/exchange`.

## Sync

Every syncable entity has this envelope:

```json
{
  "entity": "session",           // store | session | cart_item | price_observation
  "id": "uuid",
  "updatedAt": "2026-10-09T10:00:00Z",
  "deletedAt": null,
  "data": { }                    // entity fields, see below
}
```

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/sync/push` | `{ changes: [Envelope] }`, at most 500 | `{ accepted: [id], rejected: [{ id, code }], cursor }` |
| GET | `/sync/pull?cursor=<string>&limit=500` | — | `{ changes: [Envelope], cursor, hasMore }` |

Rules:

- **LWW per row:** a change is stored only if its `updatedAt` is newer than the stored one. Otherwise the change is "accepted" but ignored, and the newer row comes back on the next pull.
- **Cursor:** opaque to clients. It is the server's `server_seq`, a Postgres sequence bumped on every write. Clients store it and never parse it.
- **Deletes:** tombstones (`deletedAt` set) are kept for 90 days, then pruned. A client that has not pulled for over 90 days does a full resync (`cursor` empty).
- **References:** a `cart_item` whose `sessionId` is unknown is rejected with `missing_parent`. The client pushes parents first.

### Entity `data` fields

| Entity | Fields |
| --- | --- |
| store | `name`, `chain?`, `countryCode`, `currency` |
| session | `storeId?`, `limit?: Money`, `currency`, `startedAt`, `endedAt?`, `status`, `tillTotal?: Money` |
| cart_item | `sessionId`, `code`, `codeKind` (`gtin` / `opaque`), `productName?`, `quantity`, `weightGrams?`, `unitPrice: Money`, `priceSource`, `scannedAt` |
| price_observation | `storeId`, `code`, `price: Money`, `observedAt`, `source` |

## Stats (P9, web)

Definitions are in `DESIGN.md` → Insights catalogue. The IDs match.

| Method | Path | Returns |
| --- | --- | --- |
| GET | `/stats/summary?from&to&currency` | INS-01, 02, 03, 09 |
| GET | `/stats/stores?from&to&currency` | INS-04 |
| GET | `/stats/products?from&to&currency&limit=10` | INS-05, 06 |
| GET | `/stats/products/{code}/prices` | price history per store (INS-06, 07) |
| GET | `/stats/categories?from&to&currency` | INS-08 (needs the category cached server-side; **OPEN**, see BACKLOG WEB-104) |

## Health

`GET /healthz` gives liveness and `GET /readyz` checks the DB. Neither is authenticated. Both are used by the chart probes.
