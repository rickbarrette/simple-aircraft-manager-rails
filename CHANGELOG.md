# What's new

Each release has a **version** (year.month.release, e.g. 2026.11.0) and a **build** (the exact source commit, shown on Admin → About). The newest release is first.

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
- Calendar feed of everything coming due, with dates projected from recent flying for hour-based items.
- Weight and balance with a loading calculator (CG envelope in inches or lb-in/1000).

### Flying

- Flight log grouped by day with the route and totals; long logs load as you scroll.
- Engine monitor data charts, GPS tracks, AirTrail sync, spreadsheet import, and oil and fuel trends.

### Accounts and security

- Single sign-on (OpenID Connect), sign-in links, account lockout, breached-password check and optional authenticator codes.
- Command-line account recovery and maintenance commands (health report, records check, restore).

### Help

- A user guide for every area, in the app under Help.
