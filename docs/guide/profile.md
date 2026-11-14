# Your profile

Open your name in the top bar (☰ → **Profile** on a phone).

## Details and password

Change your name, email and password. Leave the password blank to keep the current one. A password needs at least 12 characters, and one that has appeared in a known data breach is refused (checked with Have I Been Pwned, which never receives the password itself).

**Weekly maintenance reminders**: on Mondays the app emails owners about anything overdue or coming due on their aircraft, and certificates about to expire. Untick it to stop them. (Emails need the administrator to have set up email.)

**Time zone** is *Automatic* by default: times show in your device's zone, and "today" (for example a new flight's date) is your local date. Choose a zone to use it on every device. Signatures and the record history always show UTC.

## Two-factor sign-in

**Set up** adds a code from an authenticator app on your phone (Google Authenticator, Microsoft Authenticator, 1Password, Authy…) to password and emailed-link sign-in, so a stolen password alone can't get in. It also asks for the code when you sign a logbook entry with your password.

1. Scan the QR code with the app (or type in the key shown under it).
2. Enter the code the app shows and choose **Turn on**.
3. Save the **recovery codes**: each one signs you in once if you lose your phone. They're shown only once.

To make new recovery codes or turn it off, enter a current code (or a recovery code) on your profile. If you've lost both your phone and your recovery codes, ask the administrator to reset it.

Signing in with single sign-on doesn't ask for this code: the sign-on provider handles its own second factor.

## Calendar feed

**Create calendar link** gives a private address for your calendar app (Google Calendar: Other calendars → From URL; iPhone: tap **Subscribe**). It shows what's coming due on your aircraft as all-day events: inspections, ADs, part replacements, TBO and inspection limits, and expiring documents. Items due by hours get a date projected from the aircraft's flying over the past year, marked "projected". Calendar apps refresh it every few hours.

Anyone with the link can see the list, so keep it private; **Make a new link** retires the old one.

## Certificates

Add each certificate you sign maintenance records with: its kind (A&P, IA, airframe, powerplant, repairman, repair station, pilot…), its number, and for an IA, its expiry. You need one to sign a logbook entry, and the entry records which one you used. An IA expires on March 31 of each odd-numbered year unless renewed; you're reminded 60 days ahead.

## Single sign-on

If the app offers single sign-on, **Link** your account to it here so you can sign in with it, or **Unlink** it.

## This device

**Install the app** adds Simple Aircraft Manager to the home screen (or the computer's apps), for offline flights and squawks, pre-flight pages without signal and notifications; see [On a phone](getting-started.md#on-a-phone). On iPhone and iPad, install from Safari's **Share → Add to Home Screen**.

**Notifications → Turn on** lets this device show:

- a **Ground Aircraft** squawk on an aircraft you have access to (not one you reported);
- items that newly become overdue, or newly limit the aircraft (VFR only, no transponder), on aircraft you own; checked each morning, each item once;
- a request to sign a logbook entry sent to your email address.

Turn it on on each phone or computer you want them on; **Send a test** checks it works. On iPhone and iPad, notifications work in the installed app (iOS 16.4 or later). If the browser blocked them, allow notifications for the site in its settings.

## Sessions

**Sign out everywhere else** ends your sessions on other devices, for example after using a shared computer or losing a phone.

## Integrations: AirTrail

**AirTrail sync** pushes the flights you log to your AirTrail flight map, with their GPS tracks. In AirTrail, create an API key (Settings → Security) with the scopes shown, then paste your AirTrail address and key here. A full sync first links flights already in AirTrail, so nothing is duplicated. If an airport code can't be matched, enter the code AirTrail uses for it.

If your AirTrail server is on your private network (an address like 192.168.x.x or 10.x.x.x), only an administrator can connect to it, unless the administrator lists it in `AIRTRAIL_ALLOWED_HOSTS`. This stops accounts from using the app to probe the private network. The app's own server and link-local addresses can't be used at all.
