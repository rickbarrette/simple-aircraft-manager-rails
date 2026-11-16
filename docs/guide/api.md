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
| `drafts:write` | Sending draft logbook entries for signing, and withdrawing them (acting for someone who can write logbook entries on the aircraft) |

## Requests and answers

- Base address: `https://<your server>/api/v1`
- JSON in and out. Times are ISO 8601 in UTC, hours are decimals, and values are codes (`ENG`, `IN-USE`) rather than translated labels.
- Lists answer `{ "data": [ … ], "next_after": 123 }`. Ask for more with `?after=123`; `?limit=` sets the page size (up to 200, default 50); `?updated_since=2026-11-01T00:00:00Z` lists only what changed since then.
- Errors answer `{ "error": { "code": "invalid", "message": "…", "fields": { "issue_reported": ["can't be blank"] } } }` with the matching HTTP status: 400 bad request, 401 no or wrong token, 403 not allowed (`missing_scope`; `not_permitted` when the person's role on the aircraft doesn't allow it), 404 not found or not reachable with this token, 409 `idempotency_conflict`, 422 invalid, 429 too many requests (600 a minute per token).

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
| `POST /aircraft/:id/draft_batches` | Send a visit's work as draft logbook entries for signing |
| `GET /aircraft/:id/draft_batches` | Its drafts (`?status=awaiting_signature`, `completed` or `withdrawn`) |
| `GET /draft_batches?external_ref=…` | Find drafts by your id for them |
| `GET /draft_batches/:id` | One draft, with its entries and whether they're signed |
| `DELETE /draft_batches/:id` | Withdraw a draft nothing in which is signed yet |

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

`PATCH /squawks/:id` with `{ "squawk": { … } }`. Anyone who may write can set `external_ref`; changing `issue_reported`, `priority`, `component_id` or `notes` needs the **Manage squawks** permission on the aircraft, as in the app. Reporting one needs **Report squawks**. A resolved squawk can't be changed. Squawks are resolved by a signed logbook entry, in the app.

## Draft entries

Another system that tracks the work, such as Redmine's issues, can send a finished visit to SAM as **draft logbook entries**: the person certifying the work then reviews and signs them in the app. Like writing entries in the app, sending drafts needs the **Write logbook entries** permission (Owners and Mechanics have it): an integration acts for such a person (`SAM-On-Behalf-Of`), such as the director of maintenance.

```
POST /api/v1/aircraft/12/draft_batches
{ "draft_batch": {
    "date": "2026-11-20",
    "aircraft_hours": 4321.4,
    "external_ref": "redmine:visit:77",
    "items": [
      { "log": "ENG", "text": "Changed oil and filter, 7 qt Aeroshell W100.", "external_ref": "redmine:issue:4512" },
      { "log": "AC",  "text": "Replaced left brake linings.", "resolves_squawks": [88], "external_ref": "redmine:issue:4513" },
      { "log": "AC",  "text": "Annual inspection completed IAW Part 43 Appendix D.", "external_ref": "redmine:issue:4519" }
    ],
    "completes_inspections": [ { "inspection_type_id": 3, "result": "approved" } ],
    "signer": { "email": "mechanic@example.com", "send_email": false }
} }
```

- **One entry per logbook.** Items are grouped by `log` (`AC`, `ENG`, `PROP` or `OTHER`) into one unsigned entry each, their texts in order, so a visit that touched the engine and the airframe makes two entries, signed one after the other.
- **Inspections** (`completes_inspections`): each needs its `result`, `approved` (airworthy) or `discrepancies` (a list was given to the owner), and the draft needs `aircraft_hours`. The entry recording it is an inspection entry, in the logbook named by `log`, else the airframe log if an item is for it.
- **Nothing is resolved until it's signed.** The squawks the items resolve and the inspections they complete are held until **every** entry of the draft is signed; then they're resolved and recorded, attributed to the person who signed last, and linked to the entry that described the work. A draft never clears a squawk on its own. The signer sees what signing will do before they sign.
- **The signer.** Anyone with access to the aircraft and a certificate in their profile can sign, from each entry's `sign_url`. Give `signer.email` for someone else (a mechanic who isn't on the aircraft): each entry then gets an `invitation_url`, a link that lets that person sign that entry with their account for that address, for 14 days. They need an account first (the administrator adds it, or invites them). Pass the link on yourself (for example inside Redmine), or set `send_email: true` to have SAM email it.

The answer (`201`):

```json
{ "data": { "id": 301, "status": "awaiting_signature", "external_ref": "redmine:visit:77",
            "held": { "resolves_squawks": [88], "completes_inspections": [3] },
            "entries": [
              { "id": 9001, "log": "AC",  "entry_type": "INSPECTION", "text": "Replaced left brake linings.\n\nAnnual inspection…", "signed": false,
                "sign_url": "https://sam.example.com/aircraft/12/logbook_entries/9001/signature/new", "invitation_url": "https://sam.example.com/sign/…" },
              { "id": 9002, "log": "ENG", "entry_type": "MAINTENANCE", "text": "Changed oil and filter…", "signed": false, … } ] } }
```

When every entry is signed, the draft's `status` becomes `completed` and the `draft_batch.completed` webhook is sent: the moment to close the work order.

A draft can be withdrawn (`DELETE /draft_batches/:id`) while nothing in it is signed; its entries are removed, and the record history keeps them. Once an entry is signed it's a record: mistakes are fixed with a correction entry in the app, never through the API.

## Webhooks

An integration can be told about changes. In Admin → Integrations, give it a webhook address and choose the events. SAM then posts JSON there after each change:

| Event | When |
|---|---|
| `squawk.created` | A squawk is reported |
| `squawk.updated` | A squawk is changed |
| `squawk.resolved` | A squawk is resolved |
| `entry.signed` | A logbook entry is signed |
| `draft_batch.completed` | Every entry of a draft is signed, and what it resolves is done |

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
