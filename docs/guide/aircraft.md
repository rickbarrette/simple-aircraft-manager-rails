# Aircraft and airworthiness

## The fleet

**Fleet** shows every aircraft you have access to, with its airworthiness and its most pressing issues. **+ Add Aircraft** creates one (you become its owner). **More → Import from a .sam.zip archive** loads an aircraft from a `.sam.zip` archive (see [Access, sharing and transfer](sharing.md)).

## An aircraft's overview

The **Overview** tab shows:

- **Airworthiness**: the overall status and each reason for it.
- **Active squawks**, **Consumption** (oil and fuel rates), **Notes** and **Recent activity**.
- **Last flight**: the most recent day's legs as one route, the meters at the end, and the fuel and oil left.
- **Update Hours**: enter the current meter readings (see [Flights and hours](flights.md)).
- **Details**. The **Status report** link is on the Airworthiness card, and under **More** at the top of every aircraft page.

## What the airworthiness status means

The app works out a status from the records:

- **Grounded**: something makes the aircraft unairworthy: an overdue AD, a squawk marked *Ground Aircraft*, an overdue inspection that grounds, a replacement-critical part overdue or expired, or an expired registration.
- **Limited**: airworthy with a limitation, such as *VFR only* when the IFR (91.411) check is overdue, or no transponder use when the 91.413 check is.
- **Due soon**: something comes due within 10 hours or 30 days.
- **Current**: nothing due.

It's only as good as the records entered, and the pilot in command still decides whether the aircraft is airworthy (14 CFR 91.7).

## Editing the aircraft

**Edit** (owners) on the overview changes:

- Tail number, make, model, serial number, status (Available, In Maintenance, Grounded, Unavailable), ICAO type (used for AirTrail), description and picture.
- **Current tach / hobbs**, and **offsets** subtracted for maintenance math after a meter is replaced.
- Which meter is the maintenance clock (tach or Hobbs).
- **Electronic records since**: the date this app became the maintenance record. Earlier records stay in the paper logbooks.
- **Enforce airworthiness**: blocks flight logs and hours updates while the aircraft is grounded.

The **Danger zone** deletes the aircraft and everything in it. Export it first if you might need it again.

## Status report

**Status report** is a printable summary of the aircraft's maintenance status (14 CFR 91.417(a)(2)): total time, life-limited parts, time since overhaul, inspections, AD status with method and revision, major alterations and open discrepancies. Print it or save it as a PDF from the browser.
