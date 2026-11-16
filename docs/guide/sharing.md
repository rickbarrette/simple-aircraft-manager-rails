# Access, sharing and transfer

**Access & sharing** is for people whose role lets them manage the aircraft's people, share links or exports (Owners): open it from **More** at the top of the aircraft's pages.

## People

Add people by email with a role: **Owner**, **Mechanic**, **Pilot**, **Viewer**, or one the administrator added (they need an account; ask the administrator). Change or remove their role at any time; **What each role can do** on the page lists them. See the roles table in [Getting started](getting-started.md).

Only an Owner can give or take away the Owner role, nobody can change their own, and an aircraft always keeps at least one Owner. An administrator can also give people roles on any aircraft from **Admin → Users**.

## Someone without an account

For someone who doesn't have an account yet, ask the administrator: they add the account, or send an invitation link that makes it and gives the role (Admin → Invitations). An outside mechanic who only needs to sign an entry can create their own account from your signing invitation (**Ask someone to sign** on the entry; see [Electronic records and signing](records.md)).

## Share links

**Create Share Link** gives a read-only link that needs no account, for a mechanic, partner, buyer or insurer:

- **Current Status**: airworthiness, open squawks, components, inspection and AD status, consumption, notes and shared documents.
- **Maintenance Detail**: also the logbook, inspection and AD compliance history, major repairs and alterations, resolved squawks and the printable status report.

Give it a label and optionally an expiry. Documents only appear if their visibility allows it (see [Documents](documents.md)). Delete a link to revoke it. An aircraft can have up to 10.

## Records package

**Download records package** builds a zip for the FAA, a buyer or a new maintainer: every logbook entry as a PDF with its signatures, a signature register, the change history, the status report, the current recordkeeping procedures, and the data archive. Its README explains each file, links to the source code, and includes a ready-to-run `viewer/docker-compose.yml`. With Docker Desktop, the recipient runs `docker compose up` in that folder and opens http://localhost:3000 to browse everything the way you see it: the archive is imported by itself, and no account is needed.

That copy is a **read-only viewer**: nothing in it can be changed, it can only be reached from their own computer, and it isn't connected to your system. It runs the release of the app that made the package, and shows a banner naming the archive and when it was exported. Electronic signatures appear as imported, to compare with the PDF and signature register.

## Backup and transfer

**Download .sam.zip** exports the whole aircraft with its files. Anyone can load it with **Fleet → More → Import from a .sam.zip archive** (in this app or the original Simple Aircraft Manager) to make a copy they own, for example when the aircraft is sold. Use a new tail number if the original is already in that app. If an older download arrived as a folder (Safari can unzip downloads by itself), compress the folder back into a zip (in Finder: right-click → Compress) and import that.

## Activity

The **Activity** tab lists everything done on the aircraft and by whom, newest first, loading more as you scroll (filter it by category). **Record history** shows every change to the maintenance records field by field (see [Electronic records and signing](records.md)).
