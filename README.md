# Simple Aircraft Manager (Rails)

A Ruby on Rails port of [Simple Aircraft Manager](https://github.com/marbindrakon/simple-aircraft-manager), a self-hosted app for tracking records and status for small fleets of aircraft: components and TBO, squawks, ADs, inspections, logbook, documents, oil and fuel trends, and read-only share links for mechanics and buyers.

The port aims to be **easy to host**. It runs as one process with one SQLite database directory. It needs no Postgres, no Redis, no nginx, and no Kubernetes.

## Stack

- Rails 8.1, SQLite. Solid Queue, Solid Cache, and Solid Cable all use SQLite, so there are no extra services.
- Hotwire (Turbo and Stimulus) with importmap, so there is no Node build step. Tailwind CSS 4 runs through `tailwindcss-rails`.
- Active Storage on local disk handles pictures, document pages, squawk attachments, and track logs.
- Chartkick and Chart.js draw the oil and fuel charts.
- Authentication uses the Rails 8 built-in generator (sessions plus password reset).

## Quick start (development)

```bash
bundle install
bin/rails db:prepare
DEMO=1 bin/rails db:seed     # optional: demo aircraft N12345
bin/dev                      # http://localhost:3000
```

With demo data, sign in as `admin@example.com` / `password123` (owner) or `pilot@example.com` / `password123` (pilot).
Without demo data, the first visit asks you to create the admin account.

Run the tests: `bin/rails test`

## Hosting

Everything persistent lives in `storage/`: the SQLite databases and the uploaded files. Back up that one directory.

### Option A: Docker Compose (simplest)

```bash
cp .env.example .env          # set SECRET_KEY_BASE (bin/rails secret), APP_HOST, FORCE_SSL
docker compose up -d --build  # http://<host>:3000
```

Data lives in the `sam_storage` volume. Set `FORCE_SSL=false` if you serve plain HTTP on a LAN. Set it to `true` when a TLS reverse proxy such as Caddy, Traefik, or Cloudflare Tunnel sits in front.

### Option B: Kamal (any VPS, automatic TLS)

Edit `config/deploy.yml` with your server IP, registry, and domain, then run `bin/kamal setup`. Kamal Proxy handles Let's Encrypt certificates. Background jobs run inside Puma (`SOLID_QUEUE_IN_PUMA`).

### Option C: Plain server / PaaS

The app is a standard Rails app. Run `bin/rails db:prepare && bin/thrust bin/rails server` with `RAILS_ENV=production`, `SECRET_KEY_BASE`, and `SOLID_QUEUE_IN_PUMA=true`. Mount `storage/` on persistent disk.

### Environment variables

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Required in production (`bin/rails secret`). Alternatively provide `RAILS_MASTER_KEY`. |
| `FORCE_SSL` | `true` (default) redirects to HTTPS and sets secure cookies. Use `false` for plain HTTP. |
| `APP_HOST` | Host used in password-reset email links. |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM` | Optional. They enable email: password resets and **Email me a sign-in link**. Without them an admin resets passwords from **Users**. Check the setup with **Admin → About → Send test email**. |
| `SMTP_TLS` | `true` for servers that use TLS from the start. That's the default on port 465; other ports upgrade with STARTTLS. |
| `ANTHROPIC_API_KEY` | Optional. Lets Claude transcribe scanned logbook pages into entries (**Logbook → Import scans**). Without it, scans are only uploaded. |
| `LOGBOOK_AI_MODEL`, `LOGBOOK_AI_EFFORT` | Optional. The Claude model and effort used for transcription (default `claude-opus-5-5`, `high`). |
| `APP_URL` | Optional public base URL, e.g. `https://aircraft.example.com` (default `https://APP_HOST`). Used for the SSO callback. |
| `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` | Optional. Turn on single sign-on with an OpenID Connect provider (see below). |
| `OIDC_PROVIDER_NAME` | Button label, e.g. `Authentik` (default `SSO`). |
| `OIDC_AUTO_CREATE_USERS` | `true` creates an account for anyone the provider lets in. New accounts start with no aircraft. Default off: an admin adds users first. |
| `OIDC_TRUST_EMAIL` | `true` links existing accounts by email even if the provider doesn't mark it verified. Only use it if users can't edit their own email at the provider. |
| `OIDC_ADMIN_GROUP` | Optional. Members of this provider group become admins and others lose admin, synced at each sign-in. |
| `PASSWORD_LOGIN` | `false` hides email/password sign-in, emailed sign-in links and password resets once SSO works. It's ignored while SSO isn't configured, so you can't lock yourself out. |

### Single sign-on (Authentik example)

1. In Authentik, create an **OAuth2/OpenID Provider** (confidential client) with the redirect URI `https://YOUR-HOST/auth/oidc/callback` and the scopes `openid`, `email` and `profile`. Then create an **Application** that uses it.
2. Set `OIDC_ISSUER` to the provider's issuer URL (`https://auth.example.com/application/o/<slug>/`), plus `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` and `OIDC_PROVIDER_NAME=Authentik`, then restart.
3. The sign-in page now shows **Sign in with Authentik**. The first SSO sign-in links an existing account with the same email if Authentik marks the email verified. Otherwise, sign in with your password and use **Profile → Link Authentik**.
4. Once everyone can sign in with SSO, optionally set `PASSWORD_LOGIN=false`.

Other OIDC providers (Keycloak, Google, Entra ID…) work the same way.

### Backups

SQLite runs in WAL mode, so a plain file copy taken while the app is running can be inconsistent. Use the SQLite backup command instead:

```bash
mkdir -p backup
for db in storage/production*.sqlite3; do sqlite3 "$db" ".backup 'backup/$(basename "$db")'"; done
rsync -aH --exclude '*.sqlite3*' storage/ backup/  # uploaded files (-H keeps the hard links that store duplicates once)
```

Alternatively, stop the container and copy the volume.

To back up or move a single aircraft with all its files, use **Access & Sharing → Download .sam.zip** (or `bin/rails "sam:export[N12345]"`). Import it from **Fleet → Import** (or `bin/rails "sam:import[file.sam.zip,owner@example.com]"`). The archive format is the original Simple Aircraft Manager's, so archives move between the two apps.

## Features

| Area | Notes |
|---|---|
| Fleet dashboard | Every aircraft you can access, with airworthiness status and its top issues. |
| Airworthiness | RED/ORANGE/GREEN from AD compliance, grounding squawks, inspection recurrency, and replacement-critical components. Warnings start 10 hours or 30 days ahead. Logic: `app/services/airworthiness.rb`, `app/services/compliance.rb`. |
| Hours | Absolute tach/hobbs updates or per-flight logs. Both apply the delta to every in-service component. Downward corrections are clamped at 0. |
| Flight import | Owners can import historical flights from `.xlsx` or `.csv` (Date, From, To, Tach, Hobbs, Oil Added, Fuel Added). Each flight's time is derived from the previous row's reading. A preview flags typos such as a tach going backwards, and rows already imported are skipped. History only: component hours aren't changed unless you choose to advance the aircraft's meters. |
| Airworthiness enforcement | Optional per aircraft. It blocks flight logs and hours updates while the aircraft is RED. |
| Components | Tree of parent and child parts, TBO and replacement limits, and service/replace reset. Owners can create new component types inline. |
| Squawks | Four priorities. "Ground Aircraft" makes the aircraft RED. Supports attachments, resolve, and reopen. |
| ADs and bulletins | Shared across aircraft and applicable to the airframe or to specific components. Hour- and month-based recurrence (due at end of month), conditional and non-mandatory types, per-aircraft "not applicable" determinations, and compliance history. |
| AD import | Import ADs from an FAA DRS export (`.xlsx` recommended: its AD numbers link to each AD's DRS page, which the import keeps; `.csv` works without links). ADs are matched by number, so nothing is duplicated. The preview suggests Track, Not applicable or Skip for each AD, and flags superseded or non-current ADs, model mismatches, appliance or STC-only ADs, and repetitive actions. |
| Inspections | Shared inspection types with hour, month, and day recurrence, plus history. |
| Logbook | Maintenance entries with search and a link to a scanned document page. |
| Documents | Collections, multi-file documents with a page viewer, and per-document share visibility. |
| Major repairs and alterations | Form 337, STC, and ICA tracking. |
| Oil and fuel | Records, trend charts, and averages (last 20 intervals, IQR outlier filtering, manual exclusion). |
| Activity log | Every write is recorded as an `AircraftEvent`. |
| Access | Admin, owner, and pilot roles, plus share links (Status or Maintenance privilege, optional expiry, at most 10 per aircraft). |

### Roles

| Action | Admin | Owner | Pilot |
|---|:-:|:-:|:-:|
| View everything on the aircraft | ✓ | ✓ | ✓ |
| Update hours, log flights, add squawks/notes/oil/fuel | ✓ | ✓ | ✓ |
| Edit or delete squawks and notes, resolve squawks | ✓ | ✓ | |
| Components, logbook, ADs, inspections, documents, major records | ✓ | ✓ | |
| Edit or delete aircraft, manage people and share links | ✓ | ✓ | |
| Create aircraft (creator becomes owner) | ✓ | ✓ | ✓ |
| Manage users and component types | ✓ | | |

Users who aren't on an aircraft get a 404 for it, identical to a missing record.

## Mapping from the Django original

| Django | Rails |
|---|---|
| `health/services.py` | `app/services/airworthiness.rb`, `compliance.rb`, `hours_service.rb`, `consumption_stats.rb` |
| `AircraftScopedMixin` / `core/permissions.py` | `app/controllers/concerns/aircraft_scoped.rb` |
| `EventLoggingMixin` / `log_event` | `Aircraft#log_event!`, called from controllers |
| DRF viewsets + Alpine.js mixins | Server-rendered controllers and ERB views with Turbo |
| `AD` | `AirworthinessDirective` |
| `MajorRepairAlteration` | `MajorRecord` |
| `DocumentImage` | `Document has_many_attached :pages` |
| `AircraftShareToken` | `ShareToken` (`has_secure_token`) |
| `views_public.py` | `SharedController` → `/shared/:token` |

Differences from the original:
- Integer primary keys instead of UUIDs. Share tokens are 32-character random strings.
- Logbook entries and inspection records don't keep many-to-many links to components. An inspection record or AD compliance can reference one component.
- Accounts are created by an admin, or by the first-run setup. The original's invitation codes aren't implemented yet.

### Not yet ported

The MCP server for AI agents, OIDC single sign-on, invitation codes, per-aircraft feature switches, the plugin system, and the desktop builds.

### Added in this port

AirTrail sync and export, an airport database, FAA DRS AD import, spreadsheet flight import, engine monitor data (CGR-30P/C) with interactive charts, AvLab and Blackstone oil analysis import with trends, multiple squawk attachments with a photo viewer, AI logbook transcription with Claude (images and PDFs), and an installable PWA.

## License

The original project is released under [The Unlicense](https://unlicense.org). This port follows the same spirit.
