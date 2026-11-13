# What's new

Each release has a **version** (year.month.release, e.g. 2026.11.0) and a **build** (the exact source commit, shown on Admin → About). The newest release is first.

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
