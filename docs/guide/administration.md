# Administration

Admins see the **Admin** menu (on a phone, under ☰). Admins can see and edit every aircraft.

## Users

**Users** lists every account.

- **+ New User**: name, email and a starting password. Tick **Administrator** to make them an admin. Then add them to aircraft from each aircraft's **Access & Sharing** tab (or they add their own aircraft).
- **Edit** to change details or reset a password when email isn't set up.
- **Locked** marks an account locked for 15 minutes after 10 failed sign-ins in a row (the user is emailed). **Unlock** clears it straight away, once you know it was really them.
- **2FA** marks someone using an authenticator app. **Reset 2FA** turns it off for a user who lost their phone and recovery codes. Confirm it's really them first (call them); they can then set it up again.
- **Disable** someone who no longer needs access: they're signed out and can't sign in or sign entries, and their past signatures stay. **Enable** reverses it. Users who have signed entries can't be deleted, only disabled.

With single sign-on, accounts can be created automatically at first sign-in, and admin rights can follow a group at the provider (see the main README).

## Account recovery from the command line

If nobody can sign in to fix an account in the app (a forgotten admin password, a lockout, a lost phone with no recovery codes, the only admin disabled), run these on the server. With Docker Compose, put `docker compose exec web` in front; in Portainer, open the container's **Console** and run them there. Anyone who can run commands on the server already has the data, so they ask for nothing else. Each one is written to the log.

| Command | What it does |
|---|---|
| `bin/rails users:list` | Lists accounts, with admin, disabled, locked, 2FA and SSO status |
| `bin/rails "users:reset_password[jane@example.com]"` | Sets a new generated password and shows it once; also unlocks the account and signs it out everywhere. `PASSWORD=...` in front sets your own instead (it then stays in your shell history) |
| `bin/rails "users:sign_in_link[jane@example.com]"` | Prints a one-time sign-in link (15 minutes), for when email isn't working. Two-factor still asks for the code |
| `bin/rails "users:unlock[jane@example.com]"` | Clears a lockout after failed sign-ins |
| `bin/rails "users:reset_two_factor[jane@example.com]"` | Turns off the authenticator app |
| `bin/rails "users:enable[jane@example.com]"` / `users:disable[…]` | Enables or disables an account |
| `bin/rails "users:make_admin[jane@example.com]"` | Makes an existing account an admin (with `OIDC_ADMIN_GROUP` set, the next single sign-on sets it from the group again) |
| `bin/rails "users:create_admin[jane@example.com,Jane Pilot]"` | Creates a new admin account with a generated password |

Keep the quotes around commands with brackets: some shells treat `[` specially.

If single sign-on is broken and `PASSWORD_LOGIN=false` is set, remove that setting and restart first, so password sign-in (and sign-in links) work again.

## Component Types, Airports, Logbook Templates

- **Component Types**: the list of types used for components (owners can also add new types while adding a component).
- **Airports**: airport data from OurAirports, used for From/To autocomplete and AirTrail. It downloads by itself when the app first starts; **Update from OurAirports** refreshes it. Add private strips here; they're never overwritten.
- **Logbook Templates**: the wording offered when writing an entry. Use `__` for blanks. **Restore built-in templates** adds back any deleted built-in ones.

## Settings

- **Uploads**: the largest file anyone can upload. A proxy in front of the app may have its own smaller limit.
- **Backups**: how many nightly database copies to keep, on the server and in Google Drive.

## About

**About** shows the running version, features and storage, and has tools:

- **Send test email** and **Send me this week's reminder** check that email works.
- **Records integrity**: the last nightly backup, off-site copy and records check. **Back up and check now** runs the backup and check straight away.
- **Records**: the current recordkeeping procedures revision, the last audit and when the next is due.
- **Software versions**: when each version of the app was first run.

## Backups

Every night at 3:30 the app makes a verified copy of the database in `storage/backups`, then checks the record history and every signature. Admins are emailed if anything fails.

Those copies sit on the same server, so the records also need a copy somewhere else. The app can make that copy to Google Drive itself (below). Otherwise back up the whole storage volume to another machine or a cloud service, and test restoring it now and then. A restore test is part of every records audit.

## Off-site backup to Google Drive

**Admin → Off-site Backup** connects a Google account. Every night after the database backup, the app copies to that account's Drive:

- the verified database copy, compressed (`database/sam-….sqlite3.gz`), keeping the newest 30 (change it in **Settings**);
- every uploaded file (scans, documents, photos, track logs) not already copied (`files/`). Files are never deleted there, so one deleted here by mistake can still be recovered.

The app can only see the files it created in your Drive. Admins are emailed if a copy fails, and the About page shows the last one.

Google Drive is the only cloud service built in. iCloud Drive can't be used: Apple offers no way for a server to upload to it. To use iCloud anyway, a Mac signed in to iCloud can copy `storage/backups` and the uploaded files into iCloud Drive on a schedule; describe that in the procedures' off-site backup field, since the app can't check it.

### Setting it up (once)

You create your own Google "OAuth client" so the app can ask for access. The steps are also on the page:

1. In the [Google Cloud console](https://console.cloud.google.com/), signed in as the account that will hold the backups, create a project and enable the **Google Drive API**.
2. Under **Google Auth Platform**, fill in **Branding** (an app name and your email). Under **Audience**, choose **External**, then **Publish app**. While it's left in "Testing", Google ends the access after 7 days. Google doesn't need to verify it, because the app only asks for access to files it creates.
3. Under **Clients**, create an **OAuth client ID** of type **Web application**, with the redirect URI shown on the Off-site Backup page (it ends in `/admin/offsite_backup/callback`, at the address you use for the app).
4. Paste the client ID and secret on the page, choose **Save client**, then **Connect Google Drive** and allow access. Google warns that the app isn't verified: choose **Advanced → Go to …**.

The first backup starts straight away. It copies every uploaded file, so it can take a while.

**Back up now** runs a backup straight away. **Test restore** downloads the newest database copy from Drive, opens it and checks it, and downloads a few random files and compares them with their checksums. **Disconnect** stops the copies; what's already in Drive stays there.

### Restoring from Google Drive

If the server is lost:

1. Set up the app again (see the main README) with the **same `SECRET_KEY_BASE`**, but don't start it yet.
2. From Google Drive, download the newest file in **Simple Aircraft Manager backups → database** (`sam-….sqlite3.gz`) and copy it onto the server.
3. Put it in place: `bin/rails "backups:restore[/path/to/sam-….sqlite3.gz]"`. With Docker, run it in a one-off container while the app is stopped: `docker compose run --rm web bin/rails "backups:restore[/rails/storage/sam-….sqlite3.gz]"` (copy the file into the storage volume first). It checks the copy, keeps any existing database aside, and asks before replacing.
4. Start the app and sign in. The records are back, but uploaded files are still missing.
5. Restore the files: `bin/rails offsite:restore_files` downloads them from Drive (the connection is in the restored database). If that doesn't work (for example the `SECRET_KEY_BASE` is lost), download the **files** folder from Drive, unzip it on the server and run `bin/rails "offsite:restore_files[/path/to/files]"`.
6. Check everything: `bin/rails records:check` (history and signatures intact) and `bin/rails sam:doctor`, then open a few entries and documents.

The same `backups:restore` (with no file) puts back the newest nightly copy from `storage/backups`, for example after a mistake that can't be undone in the app; `bin/rails backups:list` shows the copies.

## Maintenance commands

Run on the server like the account recovery commands (`docker compose exec web` in front, or the container's Console in Portainer).

| Command | What it does |
|---|---|
| `bin/rails sam:doctor` | Health report: secret key, address, HTTPS, email (SMTP reachable), single sign-on (issuer reachable), Google Drive, migrations, disk space, background jobs, and how recent the backup, records check, off-site copy, procedures and audit are. Exits non-zero if something fails |
| `bin/rails records:check` | Backs up the database now and checks the record history and every signature; prints any problems and exits non-zero |
| `bin/rails backups:list` | Lists the nightly database copies |
| `bin/rails "backups:restore[file]"` | Replaces the database with a backup (newest nightly copy if no file; a Google Drive `.sqlite3.gz` works too). The app must be stopped: `docker compose stop web`, then `docker compose run --rm web bin/rails backups:restore`. The current database is moved to `storage/pre-restore-…`, never deleted. `CONFIRM=yes` skips the question |
| `bin/rails users:sign_out_all` | Signs every user out of every device, if you think an account or session was compromised |
| `bin/rails "sam:records_package[N12345]"` | Writes the aircraft's records package to a zip, for when the web side is down |
| `bin/rails "email:test[you@example.com]"` | Sends a test email and shows the mail settings |
| `bin/rails offsite:backup` / `offsite:restore_test` | Runs the Google Drive copy or a restore test now and prints the result |

## Recordkeeping procedures

If the app replaces the paper logbooks, AC 120-78B asks for a written procedures document. **Recordkeeping Procedures** generates one from the app's setup:

1. Fill in the **details** the app can't know: the owner/operator, the person responsible for the records, how the app is hosted, how it's backed up off-site (described automatically when Google Drive is connected), and how often to audit and how many entries to sample.
   **Insert suggested text** under *Hosting and network* and *Additional procedures* fills the box with a starting draft: what the app knows from its settings (HTTPS, how people sign in, the password and lockout rules, the date electronic records began) and common procedures for a Part 91 owner (who signs, outside signers, share links, retention, paper records, sale). Replace each [bracketed] blank with your own details and change anything that isn't how you work; a revision can't be adopted while a blank is left.
2. **Preview the draft** and read it through.
3. **Adopt** it as a revision, with a note of what changed. Adopted revisions can't be changed; print one or save it as a PDF with the records.

The document covers responsible personnel, users and roles, the signing process, system controls, audits, making records available to the FAA, transfer, continuity and changes, with these [user instructions](records.md) as an appendix. Adopt a new revision whenever users, hosting or procedures change. The current revision goes into each aircraft's records package.

## Records audits

**Records Audits** is the periodic quality check the procedures promise. **Start an audit**:

- The app shows its own checks: the latest integrity check, backup and off-site copy, the procedures, signatures, expired certificates, and software changes since the last audit.
- You confirm the rest: that you restored the off-site backup somewhere separate and opened it (with Google Drive, run **Test restore** and also open a downloaded copy yourself); that a random sample of entries matches their work orders or receipts; that the users and roles are right (disable anyone who no longer needs access); and that the paper logbooks are kept.
- Add a note for each item and overall, then **Record audit**. Audits can't be changed afterwards.

The next one is due after the interval set in the procedures. It shows on About, and admins are reminded in the weekly email.
