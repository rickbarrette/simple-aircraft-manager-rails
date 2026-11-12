# Airworthiness directives

The **ADs** tab lists the ADs and bulletins that apply to the aircraft or its components, their compliance status, and the compliance history.

## Adding ADs

- **+ New AD**: the number, type (AD, SAIB, SB, alert, other), standard or conditional, what it requires, whether it recurs (every so many hours and/or days, months or years; months and years are due at the end of the month) and a link to the AD. A conditional AD only applies when its trigger happens (“on prop strike”) and doesn't affect airworthiness. Non-mandatory bulletins can be tracked too.
- **Link existing**: ADs are shared between aircraft; link one already entered for another aircraft.
- **Import from FAA DRS**: export the ADs for the aircraft, engine and propeller from the FAA's Dynamic Regulatory System, preferably as `.xlsx` so each AD keeps its DRS link, and upload it. The preview suggests **Track**, **Not applicable** or **Skip** for each AD and flags superseded ADs, model mismatches, appliance and STC-only ADs, and recurring actions. Nothing is duplicated.

## The AD baseline

The full list of ADs comes from DRS imports; the weekly search (below) adds what's published afterwards. The **AD baseline** panel on the ADs tab shows the last import, which of the aircraft's models it covered, and any model (airframe, engine or propeller) that was never imported. Import again at least once a year to pick up revised ADs: the weekly email and the records audit remind you when it's due.

## Newly published ADs

The app searches the Federal Register weekly for new ADs mentioning the aircraft make and model, the engine and propeller models (and their families, e.g. O-200 for an O-200A), and every other installed component by its maker, type and model, such as magnetos, the ELT and radios. ADs often name a series rather than the exact model, so "Bendix" + "magneto" is searched as well as the model. You can add your own terms (an STC, a part that isn't a component); they're searched as well. Tracking an AD found through a component makes it apply to that component. **Check now** runs it straight away. For each match, **Track** it or **Dismiss** it. Matches are only *possibly* applicable: check the AD's applicability and serial number ranges first.

## Recording compliance

**Comply** records the date, aircraft hours, the component, the logbook entry, the method (inspection, terminating action, AMOC) and the AD revision complied with, with details of what was done. **N/A** records that an AD doesn't apply, and why (for example, serial number outside the affected range). Recurring ADs then show when they're next due.

Applying an AD to the aircraft or a component, removing it, and changes to it are kept in **Activity → Record history**, with who and when. An owner can **Restore** an AD that was removed by mistake from there.

Make the logbook entry for the work as well; the status report lists each AD with its method and revision (91.417(a)(2)(v)).
