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

What you can do depends on your role on each aircraft:

| | Pilot | Owner | Admin |
|---|:-:|:-:|:-:|
| See everything on the aircraft | ✓ | ✓ | ✓ |
| Log flights, update hours, report squawks, add notes, oil and fuel | ✓ | ✓ | ✓ |
| Defer a squawk as inoperative | ✓ | ✓ | ✓ |
| Sign logbook entries (with your own certificate) | ✓ | ✓ | ✓ |
| Edit squawks and notes, resolve squawks | | ✓ | ✓ |
| Components, logbook, inspections, ADs, documents, major records, W&B | | ✓ | ✓ |
| Edit the aircraft, manage people and share links | | ✓ | ✓ |
| Users, settings, procedures and audits for the whole app | | | ✓ |

Anyone can add an aircraft and becomes its owner. You only see aircraft you have a role on; admins see all of them.

## Finding your way around

- **Fleet** (top left) lists your aircraft with their airworthiness.
- Each aircraft has tabs: **Overview, Components, Squawks, Flights, Oil & Fuel, Logbook, Inspections, ADs, Documents, Major Records, W&B, Notes, Activity**.
- **Log Flight** and **Report Squawk** are at the top of every aircraft page. Next to them, **More** has the status report and, for owners, **Access & sharing**, editing the aircraft, and its downloads.
- Each section shows its main action as a button (such as **+ New Entry**). Less frequent ones, such as imports, exports and printing, are under that section's **More** button.
- **Search** (the box in the top bar, or ☰ → Search on a phone) looks through the logbook, squawks, notes, ADs, documents (including the text of their pages), components, flights and major records of your aircraft at once.
- Your name (or ☰ on a phone) leads to your **Profile**, this **Help**, and for admins the **Admin** pages.

## On a phone

The app works on phones. The tabs collapse into a **Section** menu, and wide tables scroll sideways.

Install it like an app from **Profile → This device** (or in Safari: **Share → Add to Home Screen**). Installed, it:

- opens from the home screen, with **Log Flight** and **Report Squawk** shortcuts on a long press of its icon;
- logs flights and reports squawks without signal and sends them when the connection is back (see [Flights](flights.md) and [Squawks](squawks.md)); the number waiting shows on the icon;
- opens without signal: while you're online it saves the **Fleet** page and, for each of your aircraft (up to 10), the **Overview**, **W&B**, **Log Flight** and **Report Squawk** pages and its photo, refreshed at most hourly. So at the plane you can check airworthiness and loading, and log or report as usual. A copy shown offline says when it was saved;
- can show notifications (**Profile → This device**).

When a new version is installed on the server, a notice offers **Reload**. Signing out clears the forms and pages the device kept; flights or squawks not yet sent stay and are sent the next time you sign in on that device. They're only ever sent under the account that saved them.

The sun/moon button switches between light and dark themes.
