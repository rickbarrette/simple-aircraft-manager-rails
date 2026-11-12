# Flights and hours

Every hour flown is added to the aircraft and to each installed component, which is what moves inspections, ADs, TBOs and replacement times toward due.

## Log a flight

**Log Flight** (top of every aircraft page) records:

- The date, and **tach out / in** and **Hobbs out / in**, or just the durations.
- Oil and fuel added, the level after and the product. These feed the oil and fuel trends.
- The route (From/To airports autocomplete) and notes.
- Optionally a **track log** (GPX, KML or CSV) and **engine monitor data** (CGR-30P / CGR-30C `.csv`), which you can chart on the flight's page.

### With no signal

On a phone or tablet with the app installed (see [Getting started](getting-started.md)), you can log a flight without a connection, as long as you've opened **Log Flight** for that aircraft on that device before. Without signal, the form opens from the copy the device kept, and **Log Flight** saves the flight on the device instead of sending it. The next leg starts where the last one ended. When the connection is back, the app sends the saved flights by itself and says so at the top of the page. A flight that's rejected (for example a typo in the tach) stays there with the reason, to log again by hand or discard. Sending twice never logs a flight twice.

Track and engine data files attached offline are kept and sent too.

## Update hours

When you don't log each flight, use **Update Hours** on the overview: enter the current meter readings and the difference is applied to every installed component. A reading lower than the current one is treated as a correction.

If **Enforce airworthiness** is on, neither works while the aircraft is grounded.

## The Flights tab

The **Flights** tab shows totals and hours by month, then the flight log grouped by day: each day shows the whole route flown (KOQU → KBID → KOQU; a "·" marks where the aircraft moved without a logged leg) and that day's tach and Hobbs time, fuel and oil. Click a day to see its legs, and a leg to open the flight. The most recent 30 days load with the page; earlier ones load as you scroll down (or with **Load more**). From there:

- **Import from spreadsheet** (owners): historical flights from `.xlsx` or `.csv` (Date, From, To, Tach, Hobbs, Oil Added, Fuel Added). A preview flags problems such as a tach going backwards and skips rows already imported. It only adds history: component hours don't change unless you choose to advance the meters.
- **Export for AirTrail**: a file to import into AirTrail. For automatic syncing, see [Your profile](profile.md).
- **Standardize airport codes**: fix codes that don't match a known airport (often a typo), or add a private strip.
