# Flights and hours

Every hour flown is added to the aircraft and to each installed component, which is what moves inspections, ADs, TBOs and replacement times toward due.

## Log a flight

**Log Flight** (top of every aircraft page) records:

- The date, and **tach out / in** and **Hobbs out / in**, or just the durations.
- Oil and fuel added, the level after and the product. These feed the oil and fuel trends.
- The route (From/To airports autocomplete) and notes.
- Optionally a **track log** (GPX, KML or CSV) and **engine monitor data** (CGR-30P / CGR-30C `.csv`), which you can chart on the flight's page.

### With no signal

On a phone or tablet with the app installed (see [Getting started](getting-started.md)), you can log a flight without a connection. While you're online, the app saves what it needs on the device for each of your aircraft (up to 10), so without signal you open the app, tap the aircraft and **Log Flight** as usual: the form opens from the saved copy, and **Log Flight** saves the flight on the device instead of sending it. The next leg starts where the last one ended. When the connection is back, the app sends the saved flights by itself (on Android, even if the app is closed) and says so at the top of the page. The device asks the browser to keep them safe until then. A flight that's rejected (for example a typo in the tach) stays there with the reason, to log again by hand or discard. Sending twice never logs a flight twice.

Track and engine data files attached offline are kept and sent too.

A signal so weak that nothing comes back counts as none. **Log Flight** says *Sending…* while it waits; if the server doesn't answer within 10 seconds (a minute with files attached), the flight is saved on the device as above and the top bar turns red. If it reached the server after all, the copy sent later is recognized and not logged twice. Nothing is sent while the top bar is red; it goes as soon as the server answers again.

## Correct a flight

Open the flight and choose **Edit**. Owners can correct any flight; pilots, the flights they logged (the **Correct any flight** and **Correct own flights** permissions). The date, airports, route, notes, oil and fuel (its oil and fuel records follow), and the track and engine data files can always be changed.

The meter readings can be changed only on the latest flight, and only until the hours change again (another flight, an hours update or an import). The aircraft and its installed components then move by the difference: fixing a tach in of 1001.4 to 1001.6 adds 0.2 hours. On earlier flights the readings are locked, since the flights after them started from those readings; correct the aircraft's hours with **Update Hours** instead.

Deleting a flight (owners) doesn't take its hours back off; use **Update Hours** for that too.

## Update hours

When you don't log each flight, use **Update Hours** on the overview: enter the current meter readings and the difference is applied to every installed component. A reading lower than the current one is treated as a correction.

If **Enforce airworthiness** is on, neither works while the aircraft is grounded.

## The Flights tab

The **Flights** tab shows totals and hours by month, then the flight log grouped by day: each day shows the whole route flown (KOQU → KBID → KOQU; a "·" marks where the aircraft moved without a logged leg) and that day's tach and Hobbs time, fuel and oil. Click a day to see its legs, and a leg to open the flight. The most recent 30 days load with the page; earlier ones load as you scroll down (or with **Load more**). The flight log's **More** button has:

- **Import from spreadsheet** (owners): historical flights from `.xlsx` or `.csv` (Date, From, To, Tach, Hobbs, Oil Added, Fuel Added). A preview flags problems such as a tach going backwards and skips rows already imported. It only adds history: component hours don't change unless you choose to advance the meters.
- **Export for AirTrail**: a file to import into AirTrail. For automatic syncing, see [Your profile](profile.md).
- **Standardize airport codes**: fix codes that don't match a known airport (often a typo), or add a private strip.
