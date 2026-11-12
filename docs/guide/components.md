# Components

The **Components** tab is a tree of the aircraft's parts: engine, propeller, magnetos, filters, ELT battery and so on, each with its own time and limits. Owners manage it.

## Adding a component

**+ Add Component**, or **+ Sub-component** on a component's page to put one under it (an oil filter under the engine, say). For each:

- **Type** (pick one, or type a new one), manufacturer, model, serial number, install location and status.
- **Time**: date in service, total time, last overhaul or service, hours since, and for engines and propellers the overhaul kind (printed in logbook entries as SMOH, SFOH or SNEW).
- **Limits**:
  - **Replace every** hours and/or a calendar interval in days, months or years (whichever comes first); **Replacement critical** makes overdue replacement ground the aircraft (oil, filters, ELT battery…).
  - **Expires on**: a date marked on the part, such as an ELT battery's.
  - **TBO** hours and/or a calendar interval. Under Part 91 TBO is usually a recommendation; tick **Treat TBO as a hard limit** only when an AD or the airworthiness limitations make it one, or **On condition** to show it without warnings.
  - **Replacement counts from**: *Last service* (the default), or *Installation (life limit)* for a part that's cleaned and reused but has a life limit, such as a reusable oil filter: its limit then counts from its total time and in-service date, and only a replacement restarts it.

**Inspections** of a part (a magneto's 500-hour inspection, an oil change, the ELT check) are inspection types applied to the component: use **+ Inspection** on the component's page, or set one up on the **Inspections** tab. The component's page lists them with when they were last done and are next due; they're tracked from their records, count toward airworthiness, and can be completed from a logbook entry.

Logged hours are added to every component that's in service.

## Service and replacement

On a component's page, **Service / Replace → Record Service** resets hours since overhaul or service to 0 and sets the service date to today, for example after an oil change. Tick *Part was physically replaced* to reset its total time and in-service date too.

Record the work in the [logbook](logbook.md) as well: the component reset tracks time, the logbook entry is the record.

**Show disposed** lists parts that have been removed and disposed of.
