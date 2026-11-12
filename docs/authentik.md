# Running behind Authentik

This is a reference for putting Simple Aircraft Manager behind [Authentik](https://goauthentik.io). Two separate pieces can be used together:

1. **Single sign-on (OpenID Connect).** The app's sign-in page gets a **Sign in with Authentik** button, so people sign in with their Authentik account, and its two-factor rules.
2. **Forward auth (proxy provider).** The reverse proxy asks Authentik before letting any request reach the app, so nobody without an Authentik account can even see the app's pages. A short list of addresses is left open for share links and for outside mechanics signing an entry.

The examples use `https://aircraft.example.com` for the app and `https://auth.example.com` for Authentik. Replace them with your own.

## 1. Single sign-on

### In Authentik

1. **Applications → Providers → Create → OAuth2/OpenID Provider**:
   - Client type: **Confidential**.
   - Redirect URI (strict): `https://aircraft.example.com/auth/oidc/callback`
   - Scopes: `openid`, `email`, `profile`.
   - Signing key: any (the default certificate is fine).
2. **Applications → Applications → Create**: name it, pick the provider, and set the launch URL to `https://aircraft.example.com/`.
3. Optional: bind a group or policy to the application to limit who can use it.

### In the app (environment variables)

```bash
APP_URL=https://aircraft.example.com
OIDC_ISSUER=https://auth.example.com/application/o/<application-slug>/
OIDC_CLIENT_ID=...
OIDC_CLIENT_SECRET=...
OIDC_PROVIDER_NAME=Authentik
# Optional:
OIDC_ADMIN_GROUP=aircraft-admins     # members become app admins; others lose admin at sign-in
OIDC_AUTO_CREATE_USERS=true          # create an account at first sign-in (new accounts have no aircraft)
```

Restart the app. The first SSO sign-in links an existing account with the same email if Authentik marks the email verified. Otherwise sign in with the password and use **Profile → Link Authentik**.

**Keep password sign-in on** (leave `PASSWORD_LOGIN` unset) if outside mechanics will sign entries through invitations: they get an app account with a password, not an Authentik account.

SSO sign-ins don't ask for the app's own authenticator code. Require MFA in the Authentik authentication flow instead (for example an authenticator validation stage).

## 2. Forward auth

### In Authentik

1. **Applications → Providers → Create → Proxy Provider**, choose **Forward auth (domain level)** (or **Forward auth (single application)** for this app alone). For domain level, set the authentication URL (`https://auth.example.com`) and the cookie domain (`example.com`).
2. Add the unauthenticated URLs below to the provider's **Unauthenticated URLs** (domain level) or **Unauthenticated Paths** (single application) field.
3. Create an application for the provider and add it to your proxy outpost (**Applications → Outposts**, for example the embedded outpost).

### In the reverse proxy (Traefik example)

A forward-auth middleware pointing at the outpost, used on the app's router:

```yaml
labels:
  - traefik.http.middlewares.authentik.forwardauth.address=http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
  - traefik.http.middlewares.authentik.forwardauth.trustForwardHeader=true
  - traefik.http.middlewares.authentik.forwardauth.authResponseHeaders=X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid
  - traefik.http.routers.aircraft.rule=Host(`aircraft.example.com`)
  - traefik.http.routers.aircraft.middlewares=authentik@docker
```

Check the [Authentik documentation for your proxy](https://docs.goauthentik.io/docs/add-secure-apps/providers/proxy/server_traefik) for the outpost routes your setup needs (nginx, Caddy and others work the same way).

The app doesn't read the `X-authentik-*` headers: people still sign in to the app itself, either with **Sign in with Authentik** (immediate, since they're already signed in to Authentik) or with a password.

### Unauthenticated URLs

For domain-level forward auth, Authentik matches each line as a regular expression against the full URL. For single-application mode, drop the `^https://aircraft\.example\.com` part and match the path.

```
^https://aircraft\.example\.com/manifest\.json$
^https://aircraft\.example\.com/service-worker\.js$
^https://aircraft\.example\.com/offline\.(html|js)$
^https://aircraft\.example\.com/favicon\.svg$
^https://aircraft\.example\.com/icon(-192|-maskable)?\.(png|svg)$
^https://aircraft\.example\.com/apple-touch-icon\.png$
^https://aircraft\.example\.com/assets/.+$
^https://aircraft\.example\.com/shared/[A-Za-z0-9]{32}(/report)?$
^https://aircraft\.example\.com/rails/active_storage/(blobs/redirect|disk)/.+$
^https://aircraft\.example\.com/sign/[A-Za-z0-9_-]{43}(/account)?$
^https://aircraft\.example\.com/session(/new|/two_factor)?(\?.*)?$
^https://aircraft\.example\.com/profile/certificates(\?.*)?$
^https://aircraft\.example\.com/profile/two_factor(/new|/recovery_codes)?(\?.*)?$
^https://aircraft\.example\.com/help/records$
^https://aircraft\.example\.com/calendar/[A-Za-z0-9]{32}\.ics$
```

What each group is for:

| Lines | Needed for | What's exposed |
|---|---|---|
| `manifest.json`, `service-worker.js`, `offline.html`, `offline.js`, icons | Installing the app on a phone (the browser fetches these without cookies), and share pages | Static files with no data |
| `/assets/…` | Styles and scripts for share pages and the signing pages | Static files with no data |
| `/shared/<token>`, `/shared/<token>/report` | Read-only share links (Access & Sharing) | Only with a valid, unexpired, unrevoked 32-character token, and only what that link's level shows |
| `/rails/active_storage/blobs/redirect/…`, `/rails/active_storage/disk/…` | The aircraft picture and shared documents on share pages | A file only to someone holding its signed link (from a page they could see). Disk links expire after a few minutes; redirect links don't, so a forwarded link keeps working |
| `/sign/<token>`, `/sign/<token>/account` | Outside mechanics signing an entry from an emailed invitation | Only with a valid, unused invitation token (43 characters, 14-day expiry, stored as a fingerprint) |
| `/session`, `/session/new`, `/session/two_factor` | The app's own sign-in, for invited mechanics | The sign-in page. Protected by rate limits, the account lockout (10 failures lock an account for 15 minutes) and optional authenticator codes. A signed-in app account still can't reach any other page through the proxy |
| `/profile/certificates` | Invited mechanics adding their certificate before signing | Adding a certificate to their own account; it only returns to a `/sign/…` page |
| `/profile/two_factor…` | Invited mechanics setting up an authenticator app | Their own two-factor setup |
| `/help/records` | The "How signing works" link on the signing form | The signing instructions, for signed-in accounts |
| `/calendar/<token>.ics` | Calendar apps fetching the due-items feed (Profile → Calendar feed) | The due list of that user's aircraft, only with their secret 32-character token; making a new link retires the old one |

Leave out lines for features you don't use: without share links drop `/shared` and Active Storage; without calendar feeds drop `/calendar`; if mechanics never sign through invitations drop `/sign`, `/session`, `/profile/…` and `/help/records`.

Everything else stays behind Authentik: the fleet, records, admin pages, the emailed sign-in links and password resets (an invited mechanic who forgets their password asks the administrator, who resets it under Admin → Users or sends a new invitation), and the Google Drive callback (`/admin/offsite_backup/callback`), which comes back to the administrator's own signed-in browser.

### Checking it

In a private window:

1. `https://aircraft.example.com/` should go to Authentik.
2. A share link should open without signing in, styled, with the aircraft picture.
3. A signing invitation should let you create an account (or sign in), add a certificate and sign.
4. After that, `https://aircraft.example.com/aircraft` in the same window should still go to Authentik.

### Client addresses

The app's rate limits and logs use the client's IP address. Rails trusts `X-Forwarded-For` from proxies on private networks (Docker networks included), so behind Traefik on the same Docker host the real address comes through. If the proxy reaches the app from a public address, configure `config.action_dispatch.trusted_proxies`.
