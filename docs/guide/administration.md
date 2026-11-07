# Administration

Admins see the **Admin** menu (on a phone, under ☰). Admins can see and edit every aircraft.

## Users

**Users** lists every account.

- **+ New User**: name, email and a starting password. Tick **Administrator** to make them an admin. Then add them to aircraft from each aircraft's **Access & Sharing** tab (or they add their own aircraft).
- **Edit** to change details or reset a password when email isn't set up.
- **Disable** someone who no longer needs access: they're signed out and can't sign in or sign entries, and their past signatures stay. **Enable** reverses it. Users who have signed entries can't be deleted, only disabled.

With single sign-on, accounts can be created automatically at first sign-in, and admin rights can follow a group at the provider (see the main README).

## Component Types, Airports, Logbook Templates

- **Component Types**: the list of types used for components (owners can also add new types while adding a component).
- **Airports**: airport data from OurAirports, used for From/To autocomplete and AirTrail. It downloads by itself when the app first starts; **Update from OurAirports** refreshes it. Add private strips here; they're never overwritten.
- **Logbook Templates**: the wording offered when writing an entry. Use `__` for blanks. **Restore built-in templates** adds back any deleted built-in ones.

## Settings

- **Uploads**: the largest file anyone can upload. A proxy in front of the app may have its own smaller limit.
- **Backups**: how many nightly database copies to keep.

## About

**About** shows the running version, features and storage, and has tools:

- **Send test email** and **Send me this week's reminder** check that email works.
- **Records integrity**: the last nightly backup and records check. **Back up and check now** runs both straight away.
- **Records**: the current recordkeeping procedures revision, the last audit and when the next is due.
- **Software versions**: when each version of the app was first run.

## Backups

Every night at 3:30 the app makes a verified copy of the database in `storage/backups`, then checks the record history and every signature. Admins are emailed if anything fails.

Those copies sit on the same server. **Back up the whole storage volume somewhere else too** (another machine or a cloud service), and test restoring it now and then. That's part of every records audit.

## Recordkeeping procedures

If the app replaces the paper logbooks, AC 120-78B asks for a written procedures document. **Recordkeeping Procedures** generates one from the app's setup:

1. Fill in the **details** the app can't know: the owner/operator, the person responsible for the records, how the app is hosted, how it's backed up off-site, and how often to audit and how many entries to sample.
2. **Preview the draft** and read it through.
3. **Adopt** it as a revision, with a note of what changed. Adopted revisions can't be changed; print one or save it as a PDF with the records.

The document covers responsible personnel, users and roles, the signing process, system controls, audits, making records available to the FAA, transfer, continuity and changes, with these [user instructions](records.md) as an appendix. Adopt a new revision whenever users, hosting or procedures change. The current revision goes into each aircraft's records package.

## Records audits

**Records Audits** is the periodic quality check the procedures promise. **Start an audit**:

- The app shows its own checks: the latest integrity check and backup, the procedures, signatures, expired certificates, and software changes since the last audit.
- You confirm the rest: that you restored the off-site backup somewhere separate and opened it; that a random sample of entries matches their work orders or receipts; that the users and roles are right (disable anyone who no longer needs access); and that the paper logbooks are kept.
- Add a note for each item and overall, then **Record audit**. Audits can't be changed afterwards.

The next one is due after the interval set in the procedures. It shows on About, and admins are reminded in the weekly email.
