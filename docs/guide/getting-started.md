# Getting started

## Signing in

Depending on how the app is set up, you can sign in with:

- **Email and password.** Your administrator creates your account. Use **Forgot password?** to reset it if email is set up; otherwise ask the administrator.
- **Email me a sign-in link.** Enter your email and use the link sent to you. It works once, for a short time.
- **Single sign-on** (for example *Sign in with Authentik*), if your organization uses it.

If you've set up an authenticator app (see [Your profile](profile.md#two-factor-sign-in)), signing in with a password or an emailed link then asks for its 6-digit code.

After 10 failed tries in a row (wrong passwords or codes), an account is locked for 15 minutes and its owner is emailed. Wait, or ask the administrator to unlock it.

The very first visit to a new installation asks for the administrator account instead. It also asks for a one-time setup code, which is printed only in the server's log (the line starting `Setup code`; with Docker, `docker compose logs web | grep "Setup code"`), so only whoever runs the server can create that account.

## Roles

What you can do depends on your role on each aircraft. These are the built-in roles as they come; the administrator can change what each allows and add others (see [Administration](administration.md#roles)).

| | Viewer | Pilot | Mechanic | Owner |
|---|:-:|:-:|:-:|:-:|
| See everything on the aircraft | ✓ | ✓ | ✓ | ✓ |
| Log flights, correct the ones you logged | | ✓ | | ✓ |
| Update hours, report and defer squawks, add notes, oil and fuel | | ✓ | ✓ | ✓ |
| Sign logbook entries (with your own certificate) | | ✓ | ✓ | ✓ |
| Write logbook entries; components, inspections, ADs, major records, W&B, documents | | | ✓ | ✓ |
| Edit squawks and notes, resolve squawks; edit oil and fuel records | | | ✓ | ✓ |
| Weekly reminders and overdue alerts | | | ✓ | ✓ |
| Correct or delete any flight, imports, exports, restore from history | | | | ✓ |
| Edit the aircraft, manage people and share links | | | | ✓ |

Administrators can do everything on every aircraft, and manage users, roles, settings, procedures and audits for the whole app. Whoever adds an aircraft becomes its Owner; the administrator decides who can (Admin → Settings: administrators only, or everyone). You only see aircraft you have a role on; administrators see all of them.

## Finding your way around

- **Fleet** (top left) lists your aircraft with their airworthiness.
- Each aircraft has tabs: **Overview, Components, Squawks, Flights, Oil & Fuel, Logbook, Inspections, ADs, Documents, Major Records, W&B, Notes, Activity**.
- **Log Flight** and **Report Squawk** are at the top of every aircraft page (when your role allows them). Next to them, **More** has the status report and, depending on your role, **Access & sharing**, editing the aircraft, and its downloads. Buttons for things your role doesn't allow aren't shown.
- Each section shows its main action as a button (such as **+ New Entry**). Less frequent ones, such as imports, exports and printing, are under that section's **More** button.
- **Search** (the box in the top bar, or ☰ → Search on a phone) looks through the logbook, squawks, notes, ADs, documents (including the text of their pages), components, flights and major records of your aircraft at once.
- Your name (or ☰ on a phone) leads to your **Profile**, this **Help**, and for admins the **Admin** pages.

## On a phone

The app works on phones. The tabs collapse into a **Section** menu, and wide tables scroll sideways.

The top bar shows the connection at a glance. It turns **red** when the server can't be reached (no signal, or one too weak to get an answer) and back on its own when it can. A small **ring** next to the menu fills while pages are being saved for offline use or what you logged offline is being sent, with the percentage in its middle; while flights or squawks are waiting to send, it's **amber** with how many.

Install it like an app from **Profile → This device** (or in Safari: **Share → Add to Home Screen**). Installed, it:

- opens from the home screen, with **Log Flight** and **Report Squawk** shortcuts on a long press of its icon;
- logs flights and reports squawks without signal and sends them when the connection is back (see [Flights](flights.md) and [Squawks](squawks.md)); the number waiting shows on the icon;
- opens without signal: while you're online it saves the **Fleet** page and, for each of your aircraft (up to 10), the **Overview**, **W&B**, **Log Flight** and **Report Squawk** pages and its photo, refreshed at most hourly. So at the plane you can check airworthiness and loading, and log or report as usual. A copy shown offline says when it was saved. Any other page shows the offline page, which links to the saved ones, instead of loading forever: after 10 seconds without an answer, and within a few seconds once the app knows it's offline;
- can show notifications (**Profile → This device**).

When a new version is installed on the server, a notice offers **Reload**. Signing out clears the forms and pages the device kept; flights or squawks not yet sent stay and are sent the next time you sign in on that device. They're only ever sent under the account that saved them.

The sun/moon button switches between light and dark themes.
