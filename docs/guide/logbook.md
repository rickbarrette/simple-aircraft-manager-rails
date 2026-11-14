# The logbook

The **Logbook** tab holds the maintenance record entries. Owners write and edit them; anyone with a certificate can sign them (see [Electronic records and signing](records.md)).

## Writing an entry

**+ New Entry**:

1. Choose a **Template** to start the wording if one fits, and fill in its blanks (`__`). The built-in ones are for a pilot doing preventive maintenance on an aircraft they own or operate (14 CFR 43.3(g)); admins can add their own.
2. Fill in the date, the **logbook** (aircraft, engine, propeller or other), the **entry type** (usually maintenance or inspection) and the **airframe total time**.
3. For an engine or propeller entry, pick the component: its total time and time since overhaul at the entry fill in from the airframe time. Tick any **sub-components** included in the work (an oil filter on the engine) to record their times as well. On a new entry, set a sub-component to **Serviced** or **Replaced** to record that on the Components tab at the same time (an oil and filter change resets their time since service), dated to the entry.
   Its time since service then counts from the airframe time on the entry.
   Under **Inspections completed**, tick any inspection the work completes (an Oil Change): it's recorded as done on the Inspections tab at the entry's date and airframe time, linked to the entry.
4. Write the **entry text**: what was done, with reference to the data used.
5. The sign-off fields (who, certificate kind and number, location) are filled in when the entry is signed electronically. Fill them in yourself for an entry copied from a paper logbook.
6. For an inspection, record the **inspection result** (approved for return to service, or a list of discrepancies given to the owner).

The entry flags anything 14 CFR 43.9 or 43.11 requires that's missing.

An entry can link to the page of a scanned document it came from.

Unsigned entries can be edited and deleted. Signed entries are locked; see [corrections](records.md#mistakes).

## Searching

Search the text, filter by logbook, and show only unverified transcribed entries.

## Importing scanned logbooks

**More → Import scans** uploads photos or PDFs of paper logbook pages as a document, in file-name order (name them `page-001`, `page-002`…). If the administrator has set an Anthropic API key, Claude reads them and adds each entry to the logbook.

Transcribed entries are marked **unverified** until someone compares each with the scan and chooses **Matches the scan: mark verified**; the app then moves to the next one. Fix any mistake with **Edit** first.

Mark the scans as **legacy records** (see [Documents](documents.md)): the paper logbooks stay the record for that period, and must be kept.

## Printing entries for the paper logbook

Tick entries and choose **Print selected** (it appears once an entry is ticked), or **Print for logbook** on one entry (under **More** on an unsigned entry). Choose Avery 5163/8163 or 5164/8164 labels, or half-letter or letter pages (letter also fits full-sheet labels); on a part-used label sheet, pick the first free label. Print at 100% (“Actual size”), not “Fit to page”, and try a plain sheet first.

Each printed entry has a line to sign by hand: a printed entry isn't a record until it's signed. An entry signed electronically prints with its electronic signature and fingerprint instead.

## Templates

Admins change the template list under **Admin → Logbook Templates** (also linked from the new-entry form). See [Administration](administration.md).
