# REST API

Other programs can work with the aircraft through the API: a script that pulls what's coming due, or another system such as Redmine that tracks work orders. The API reads the same records you see in the app and goes through the same rules. Anything it changes is in the record history, with the person it was for.

The API never signs a logbook entry, never changes or deletes a signed one, and never changes users, roles or the record history. Signing always happens in the app, by the person certifying the work ([Electronic records and signing](records.md)).

## Tokens

Each request carries a token:

```
Authorization: Bearer sam_…
```

There are two kinds:

| Kind | Made in | Acts as | Reaches |
|---|---|---|---|
| **Personal** | Profile → API tokens | you | your aircraft, with your role |
| **Integration** | Admin → Integrations (administrators) | the person named in `SAM-On-Behalf-Of` | the aircraft chosen for it, and only those that person can also see |

A token is shown once, when it's made; only its first characters are kept, to tell tokens apart. Revoke a token you no longer need, or one that may have been seen by someone else. Profile and Admin → Integrations show when each token was last used, and from where.

An integration acting for someone names them by email in each request:

```
SAM-On-Behalf-Of: mechanic@example.com
```

Reading works without it (limited to the integration's aircraft). Every write needs it, so each change names a person.

### Scopes

| Scope | Allows |
|---|---|
| `read` | Aircraft, parts, due items, inspections, ADs, squawks and logbook entries |
| `squawks:write` | Reporting squawks and updating them |

## Requests and answers

- Base address: `https://<your server>/api/v1`
- JSON in and out. Times are ISO 8601 in UTC, hours are decimals, and values are codes (`ENG`, `IN-USE`) rather than translated labels.
- Lists answer `{ "data": [ … ], "next_after": 123 }`. Ask for more with `?after=123`; `?limit=` sets the page size (up to 200, default 50); `?updated_since=2026-11-01T00:00:00Z` lists only what changed since then.
- Errors answer `{ "error": { "code": "invalid", "message": "…", "fields": { "issue_reported": ["can't be blank"] } } }` with the matching HTTP status: 400 bad request, 401 no or wrong token, 403 not allowed (`missing_scope`, `owners_only`), 404 not found or not reachable with this token, 409 `idempotency_conflict`, 422 invalid, 429 too many requests (600 a minute per token).

### Safe retries

Send an `Idempotency-Key` header (any unique string up to 100 characters) with each write. If the answer is lost and you send the same request with the same key again, you get the first answer back (with `Idempotent-Replay: true`) instead of a second record. Keys are kept for 24 hours. The same key with a different request is refused (409).

### Linking to the other system

Squawks have an `external_ref`: your own id for them, such as `redmine:issue:4512`. Set it when reporting or later, and find squawks by it with `GET /squawks?external_ref=…`. The other system then doesn't need to store SAM's ids.

## Endpoints

| | |
|---|---|
| `GET /me` | The token, who it acts as, and the aircraft it reaches |
| `GET /aircraft` | The aircraft: tail number, make and model, status, airworthiness, hours |
| `GET /aircraft/:id` | One aircraft |
| `GET /aircraft/:id/components` | Its parts: type, serial, hours, since overhaul, TBO and replacement limits, parent part (`?all=1` includes disposed parts) |
| `GET /aircraft/:id/due` | Everything coming due, soonest first; items due by hours get a projected date |
| `GET /aircraft/:id/inspections` | Each inspection's status and next due date and hours |
| `GET /aircraft/:id/ads` | Each AD's status and next due date and hours |
| `GET /aircraft/:id/logbook_entries` | Logbook entries, with their signatures (`?log=AC`, `ENG`, `PROP` or `OTHER`; `?signed=true` or `false`) |
| `GET /aircraft/:id/squawks` | Squawks (`?status=open`, the default, or `resolved` or `all`) |
| `POST /aircraft/:id/squawks` | Report a squawk |
| `GET /squawks?external_ref=…` | Find squawks by your id for them |
| `GET /squawks/:id` | One squawk |
| `PATCH /squawks/:id` | Update a squawk |

### Reporting a squawk

```
POST /api/v1/aircraft/12/squawks
Authorization: Bearer sam_…
SAM-On-Behalf-Of: pilot@example.com
Idempotency-Key: 7f9c1e2a-…
Content-Type: application/json

{ "squawk": { "issue_reported": "Left mag drop 200 rpm", "priority": 0, "component_id": 41, "external_ref": "redmine:issue:4512" } }
```

`priority` is 0 (ground the aircraft), 1 (fix soon), 2 (fix at the next inspection, the default) or 3 (fix eventually). Like a squawk reported in the app, a grounding squawk notifies the aircraft's other people. Anyone who may report squawks on the aircraft can report one.

The answer is `201` with the squawk:

```json
{ "data": { "id": 88, "aircraft_id": 12, "component_id": 41, "issue_reported": "Left mag drop 200 rpm", "priority": 0,
            "grounding": true, "deferred": false, "resolved": false, "external_ref": "redmine:issue:4512", … } }
```

### Updating a squawk

`PATCH /squawks/:id` with `{ "squawk": { … } }`. Anyone who may write can set `external_ref`; changing `issue_reported`, `priority`, `component_id` or `notes` needs an owner of the aircraft, as in the app. A resolved squawk can't be changed. Squawks are resolved by a signed logbook entry, in the app.

## Webhooks

An integration can be told about changes. In Admin → Integrations, give it a webhook address and choose the events. SAM then posts JSON there after each change:

| Event | When |
|---|---|
| `squawk.created` | A squawk is reported |
| `squawk.updated` | A squawk is changed |
| `squawk.resolved` | A squawk is resolved |
| `entry.signed` | A logbook entry is signed |

Only events on the integration's aircraft are sent. The body:

```json
{ "event": "squawk.created", "id": "6c1f…", "created_at": "2026-11-20T15:04:05Z", "aircraft_id": 12,
  "data": { …the squawk, as the API returns it… } }
```

With the headers `SAM-Event`, `SAM-Delivery` (a number, the same on every retry) and `SAM-Signature: t=<unix time>,v1=<signature>`. Check each post before trusting it: compute the HMAC-SHA256 of `<t>.<body>` with the webhook secret (shown once when the webhook is set up; Admin → Integrations → New secret makes another) and compare it with `v1`. Reject posts whose `t` is more than a few minutes old.

```ruby
t, v1 = request.headers["SAM-Signature"].scan(/t=(\d+),v1=(\h+)/).first
expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{t}.#{request.raw_post}")
valid = ActiveSupport::SecurityUtils.secure_compare(expected, v1.to_s) && (Time.now.to_i - t.to_i).abs < 300
```

Answer any 2xx status to accept it. Anything else, or no answer within 10 seconds, is retried with growing waits (8 tries over about a day), then marked failed. Admin → Integrations lists recent webhooks and what the other system answered. The same event may arrive more than once; use `SAM-Delivery` or the event's `id` to ignore repeats.

A webhook address may be on your private network (where Redmine often runs), but never the server itself or a link-local address.
