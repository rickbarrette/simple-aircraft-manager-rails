# What's new

Each release has a **version** (year.month.release, e.g. 2026.11.0) and a **build** (the exact source commit, shown on Admin → About). The newest release is first.

## 2026.11.7

### Changes

- **Correct a flight.** Open it and choose **Edit**: the date, airports, route, notes, oil and fuel (its oil and fuel records follow) and its files can always be fixed. The meter readings only on the latest flight, while nothing else has changed the hours; the aircraft and its components then move by the difference. On earlier flights the readings are shown locked. Owners can correct any flight; pilots, the ones they logged.
- **Roles you can set up.** Each person has a role on each aircraft: **Owner**, **Mechanic** (maintenance records, signing, components, inspections, ADs, squawks, reminders), **Pilot** (as before) or **Viewer** (sees everything, changes nothing). Owners and pilots keep exactly what they could do. Buttons for what your role doesn't allow aren't shown.
- **Reminders and overdue alerts** go to the roles that get them: Owners and Mechanics, as roles come.
- **Records package viewer, with no account.** The package's `viewer/docker-compose.yml` now runs a read-only copy on the recipient's computer: `docker compose up`, open http://localhost:3000, and the records are there (imported by itself, nothing can be changed, reachable only from that computer). It runs the release that made the package.

### For administrators

- **Admin → Roles**: change what Mechanic, Pilot and Viewer can do (31 permissions, grouped), or add your own roles (a partner, an instructor). Owner always has everything. **Admin → Users → Edit** lists each person's role on every aircraft, to add, change or remove. Only an Owner (or an administrator) can give the Owner role, nobody changes their own, and every aircraft keeps an Owner.
- **Admin → Invitations**: a link that makes an account (or is accepted with one) and gives roles on aircraft; limited uses, an expiry, optionally one email address (and then emailed). With single sign-on, **Continue with** on the invitation makes the account.
- **New accounts come only from an administrator**, an administrator's invitation, or an Owner's signing invitation to an outside mechanic (for that address). Signing invitations from others need an existing account.
- **Who can add aircraft** (Admin → Settings) is **administrators only** by default: adding or importing an aircraft makes you its Owner, who can bring in mechanics. **After this update, other users can't add aircraft** until you choose *Everyone* there.
- `OIDC_AUTO_CREATE_USERS=true` still gives an account to anyone the identity provider lets in, without an invitation; leave it off to keep accounts to administrators and their invitations.
- The REST API follows the person's role; its `owners_only` error is now `not_permitted`.
- The update adds the roles and invitations tables, filled in automatically when the new version starts.
- The compose files and `.env.example` mention the first-run setup code and the push notification, language and image settings.

### Fixes

- Disabled fields look disabled (they looked like any other).
- The records package's viewer said to just create an account (it needs the setup code since 2026.11.5) and named the wrong menu.

## 2026.11.6

### Changes

- **PDFs show on phones.** Android showed nothing for a PDF document and iPhones only its first page. On phones and tablets every page is now drawn in the app, as it scrolls into view, downloading only the parts of the file those pages need (a long manual opens quickly and doesn't use up mobile data). Computers keep the browser's own PDF viewer.
- **Connection status in the top bar.** It turns red when the server can't be reached, and back on its own when it can. A ring fills while pages are saved for offline use or what was logged offline is sent; it's amber with a count while flights or squawks wait to send.
- **A weak signal counts as no signal.** Log Flight and Report Squawk say "Sending…" and, if the server doesn't answer within 10 seconds (a minute with photos), keep the entry on the phone and send it when the connection's back. If it got through after all, it isn't logged twice. Every page falls back to its offline copy or the offline page instead of loading forever.
- **The activity log loads as you scroll** (it stopped at 200 events).
- **What's new** shows the running version's notes on Admin → About; older releases fold to one line each.
- **REST API** for other programs, such as a script that pulls what's coming due or a work-order system: read aircraft, parts, due items, inspections, ADs, squawks and logbook entries; report and update squawks; send draft logbook entries to be signed in the app. Webhooks announce squawks reported, updated and resolved, entries signed, and drafts completed. Personal tokens are made in Profile. The API never signs an entry; see Help → REST API.

### For administrators

- **Admin → Integrations** makes tokens for other systems, acting for the person each request names, limited to the aircraft chosen, plus webhook endpoints.
- The update adds the API's tables; they're created automatically when the new version starts.

## 2026.11.5

### Changes

- **Faster photos.** Aircraft photos load as small copies on the Fleet page and the aircraft header (they were the full original, slow on mobile). The offline copies use the small versions too.
- **Detail cards read one item per row on a phone**: flights, engine data, components and major repairs and alterations. Wider screens show two columns.
- **Profile uses the width of a desktop screen**: your account and its security on the left; calendar, certificates, this device and integrations on the right.
- **Notifications:** opening Profile on a device records its notification subscription again, so a device whose subscription was never saved starts receiving them. **Send test** lists each device and whether its push service accepted the notification, with the reason if not. If turning notifications on fails, the browser's error is shown.

### For administrators

- **The app won't start with a placeholder or short `SECRET_KEY_BASE`** (under 32 characters), since anyone who knows it can sign in as anyone. `sam:doctor` flags one under 64 characters. Use the output of `bin/rails secret`.
- **First-run setup asks for a one-time code** printed in the server log (`docker compose logs web | grep "Setup code"`), so only whoever runs the server can create the admin account.
- **HTTPS without a proxy:** `docker-compose.direct.yml` with `TLS_DOMAIN` gets and renews a Let's Encrypt certificate by itself.
- **The app answers only for its own names** when `APP_HOST` is set: `APP_HOST`, the `APP_URL` host, `localhost`, IP addresses, and any names listed in the new `ALLOWED_HOSTS`. Other names get a short explanation. If you reach the app by another name (such as a LAN name), add it to `ALLOWED_HOSTS`.
- **AirTrail servers on a private network** can be connected only by an administrator, or by anyone when listed in `AIRTRAIL_ALLOWED_HOSTS`. The server itself and link-local addresses are always refused.
- The project is released into the public domain (LICENSE, The Unlicense).

### Fixes

- A file that isn't a photo, or an empty one, chosen as the aircraft photo now shows "must be an image" instead of an error page. An image that can't be read is shown as the original file.
- A component can't be set as a part of its own parts; that made the logbook entry and squawk resolution pages fail.
- Many malformed requests that caused error pages now get a proper answer: pages requested in another format, blank required values, links to records that don't exist, numbers too large to store, and text sent where a file belongs.

## 2026.11.4

### Changes

- **Time zones.** Times show in your own zone and "today" is your local date (a new flight no longer defaults to tomorrow in the evening). It follows your device automatically, or choose one in Profile. The administrator sets the installation's zone with `TZ` (e.g. `America/New_York`), which also sets when the nightly and weekly jobs run. Signatures and the record history still show UTC.
- **Update Hours asks first**, showing each reading's change and that every in-service component moves without logging a flight; the message afterwards says exactly what changed. A lowered reading is marked as a correction.
- **Squawk photos show as thumbnails** that open the photo viewer.
- **Save and log next leg** on Log Flight: saves the flight and opens the form for the next one, starting where it ended.
- **Setup checklist** on a new aircraft's Overview: components, standard inspections, ADs from DRS, registration and airworthiness certificate, weight and balance.
- The component form groups its limits into **Replacement and expiry** and **Overhaul and TBO**, opened only when used.
- Choosing **Ground Aircraft** on a squawk says what it does before you submit.
- The logbook entry form shows **Inspection result** only for inspection entries.
- A new document is named from its file when you leave the name blank.
- Dates read the same way everywhere, including the logbook-entry pickers, the activity log and the airworthiness list.

### Fixes

- On iPad and iPhone home-screen apps, the top bar stays sharp (it's now fixed to the top of the screen).
- An aircraft's description stays inside the Details card.

## 2026.11.3

### Installed app

- **Works without signal.** While you're online the app saves, for each of your aircraft, the Overview, weight and balance, Log Flight and Report Squawk pages and its photo, plus the Fleet page. At the plane with no signal, open the app and use it as usual; a saved copy says when it was saved.
- **Report Squawk offline**, photos included, like Log Flight. Saved items are sent when the connection is back (on Android even with the app closed), only ever under the account that saved them, and the number waiting shows on the app icon.
- **Notifications** (Profile → This device): a grounding squawk on your aircraft, items newly overdue on aircraft you own (checked each morning), and requests to sign a logbook entry. On iPhone and iPad they work in the installed app.
- **Shortcuts**: a long press on the app icon offers Log Flight and Report Squawk.
- **Install help** on Profile, and a **Reload** notice when a new version is installed.
- Signing out clears what the device saved for offline use.

### Changes

- Each section shows its main action as a button; imports, exports, printing and tools are under **More**. The aircraft's **More** menu has the status report and, for owners, Access & sharing, editing the aircraft and its downloads.
- Oil Analysis is under **Oil & Fuel**; the tabs fit on one line.
- The header shows your role on the aircraft, and no longer shows "Available" (the usual status).
- **Print selected** in the logbook appears once an entry is ticked; the logbook filter applies as you change it.
- Dates read the same everywhere (the logbook list, notes, audits, About).
- All the app's text is in one translation file; see Translating in the README.

### Fixes

- The flight statistics' cards fit two to a row on phones, and **By year** shows that it opens.
- Various unused code removed.

## 2026.11.2

### Changes

- A **disclaimer**: the app is provided as is, without warranty, and isn't approved by the FAA or any other aviation authority. If you use it, it's up to you to verify that it's legal and suitable for your aircraft and operation. The full text is under Help → Disclaimer and in the README. A short notice is at the foot of every page and on the first-run setup screen, and Admin → About links to it.

## 2026.11.1

### Fixes

- Logging a flight offline works: the Log Flight form is kept on the device however you open it, the offline page shows its links and icon, and a flight saved while the app's server is unreachable (502/503/504) is queued and sent later instead of failing.
- Marking a sub-component Serviced on a logbook entry restarts its time since service from the airframe time on the entry, so new oil typed in at 0 hours no longer keeps its old hours.

### Changes

- New logbook entries have **Inspections completed**: tick the inspections the work completes (an oil change) and they're recorded on the Inspections tab at the entry's date and airframe time, linked to the entry.
- Components have **Replacement counts from**: last service (as before) or installation, for a life-limited part that's cleaned and reused, such as a reusable oil filter. Only a replacement restarts an installation-based limit.
- A component's own "Inspect every" and "Inspection critical" settings are gone; inspections of a part are inspection types applied to it. A component's page lists its inspections with last done and next due, and **+ Inspection** adds one for that part. Existing settings are converted when upgrading.

## 2026.11.0

The first numbered release. Highlights of what Simple Aircraft Manager does as of this version:

### Records and signatures (AC 120-78B)

- Electronic signatures on logbook entries: the signer picks their certificate, re-enters their password (and authenticator code) or signs in again, and certifies a statement. Signed entries are locked; mistakes are fixed with a signed correction.
- Outside mechanics can sign an entry from an emailed, one-time invitation.
- Every change to the maintenance records is kept, hash-chained and checked nightly, including ADs and inspection types applied to or removed from an aircraft (a removed one can be restored).
- Nightly verified database backup, optional off-site copy to Google Drive, and a restore test.
- Recordkeeping procedures document (with suggested text) and periodic records audits.
- Records package for the FAA or a buyer: entries with signatures, history, status report, procedures and the data archive, with a ready-to-run viewer.

### Maintenance tracking

- Airworthiness status from ADs, inspections, squawks, components and documents, with Part 91 rules (annual as 100-hour, overruns, IFR and transponder limits).
- ADs: FAA DRS import with an AD baseline per model, and a weekly search for newly published ADs covering the aircraft, engine, propeller and every installed component.
- Logbook: templates, engine and propeller times, sub-components (a new entry can also record them serviced or replaced), printable entries for the paper logbook, and AI transcription of scanned pages.
- The Overview shows the last day's flying: route, meters, fuel and oil left.
- Intervals are entered as a number of days, months or years: no converting months to days.
- Calendar feed of everything coming due, with dates projected from recent flying for hour-based items.
- Weight and balance with a loading calculator (CG envelope in inches or lb-in/1000).

### Flying

- Flight log grouped by day with the route and totals; long logs load as you scroll.
- Log flights with no signal: the phone keeps them and sends them when it's back online.
- Engine monitor data charts, GPS tracks, AirTrail sync, spreadsheet import, and oil and fuel trends.

### Accounts and security

- Single sign-on (OpenID Connect), sign-in links, account lockout, breached-password check and optional authenticator codes.
- Command-line account recovery and maintenance commands (health report, records check, restore).

### Finding things

- One search box for the logbook, squawks, notes, ADs, documents (including the text of scanned pages), components, flights and major records.

### Help and polish

- A user guide for every area, in the app under Help; release notes (this page) under What's new.
- Dates read the same way everywhere ("Nov 8, 2026"); keyboard users get a skip link and visible focus; images have descriptions.
