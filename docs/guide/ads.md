# Airworthiness directives

The **ADs** tab lists the ADs and bulletins that apply to the aircraft or its components, their compliance status, and the compliance history.

## Adding ADs

- **+ New AD**: the number, type (AD, SAIB, SB, alert, other), standard or conditional, what it requires, whether it recurs (every so many hours and/or months; due at the end of the month) and a link to the AD. A conditional AD only applies when its trigger happens (“on prop strike”) and doesn't affect airworthiness. Non-mandatory bulletins can be tracked too.
- **Link existing**: ADs are shared between aircraft; link one already entered for another aircraft.
- **Import from FAA DRS**: export the ADs for the aircraft, engine and propeller from the FAA's Dynamic Regulatory System, preferably as `.xlsx` so each AD keeps its DRS link, and upload it. The preview suggests **Track**, **Not applicable** or **Skip** for each AD and flags superseded ADs, model mismatches, appliance and STC-only ADs, and recurring actions. Nothing is duplicated.

## Newly published ADs

The app searches the Federal Register weekly for new ADs mentioning the aircraft model, the engine and propeller models (and their families, e.g. O-200 for an O-200A), and the make and model of every other installed component, such as magnetos, the ELT and radios (or only the terms you set). Tracking an AD found through a component makes it apply to that component. **Check now** runs it straight away. For each match, **Track** it or **Dismiss** it. Matches are only *possibly* applicable: check the AD's applicability and serial number ranges first.

## Recording compliance

**Comply** records the date, aircraft hours, the component, the logbook entry, the method (inspection, terminating action, AMOC) and the AD revision complied with, with details of what was done. **N/A** records that an AD doesn't apply, and why (for example, serial number outside the affected range). Recurring ADs then show when they're next due.

Make the logbook entry for the work as well; the status report lists each AD with its method and revision (91.417(a)(2)(v)).
