---
layout: default
title: ntfy — Adding a Friend
parent: Services
grand_parent: Docs
nav_order: 2
---

# ntfy — Adding a Friend

**Server:** `https://ntfy.schultzsolutions.tech`
**Host:** CT 115 (`192.168.1.34`)
**Auth mode:** `auth-default-access: deny-all` — every user needs an explicit account + ACL grant

This walkthrough covers onboarding a new user (friend, family member, etc.)
so they can receive their own push notifications from the self-hosted ntfy
instance, typically for use with the Price Tracker app but works for any
ntfy-compatible publisher.

## Architecture

Because ntfy runs with `auth-default-access: deny-all`, nothing works without
authentication. Each user gets:

1. **Their own ntfy account** (username + password for the web UI and mobile
   app)
2. **A namespaced topic prefix** like `bob-*` — wildcard ACLs scope them to
   topics starting with `bob-` so they can't read or publish to anyone
   else's topics
3. **A personal access token** for machine-to-machine publishing (e.g. the
   Price Tracker backend sending alerts on their behalf)

This model means:
- You stay the only admin
- Every friend is isolated in their own namespace — no cross-talk, no
  collisions
- You can revoke a single user's access without touching anyone else's
- You never have to share tokens or passwords between users

## Prerequisites

- SSH access to CT 115 (`ssh root@192.168.1.34` from CT 300)
- An admin-level ntfy account on that instance (the `andrew` account
  created during initial setup)
- A price-tracker invite code ready for the friend (generated from the
  Admin page at `https://prices.schultzsolutions.tech/admin`), if they
  also need access to the Price Tracker app

## Step 1 — Create the ntfy account

SSH into CT 115 and run:

```bash
# Pick a password up front. ntfy reads NTFY_PASSWORD non-interactively,
# which avoids shell history leaks.
NTFY_PASSWORD='pick-a-strong-password' ntfy user add bob
```

Expected output:

```
user bob added with role user
```

Save the password — the friend will need it to log into the ntfy web UI and
to authenticate the ntfy mobile app on their phone.

## Step 2 — Grant access to their topic namespace

Wildcard ACL so they can create any topic starting with their username:

```bash
ntfy access bob 'bob-*' rw
```

Expected output:

```
granted read-write access to topic bob-*
```

Now `bob` can read and publish to `bob-price-alerts`, `bob-home-assistant`,
`bob-whatever`, but **not** `andrew-*` or any other user's topics.

Verify the ACL:

```bash
ntfy access bob
```

Should show:

```
user bob (role: user, tier: none)
- read-write access to topic bob-*
```

## Step 3 — Generate an access token

This is the credential the Price Tracker backend (or any other publisher)
uses to authenticate as `bob` without needing the password:

```bash
ntfy token add --label 'price-tracker' bob
```

Expected output:

```
token tk_somebase32stringhere... created for user bob, never expires
```

Copy this token. It's shown once and then stored hashed — if you lose it,
you have to generate a new one.

## Step 4 — Hand the credentials to your friend

Give them **four pieces of information**:

| Field            | Value                                      |
| ---------------- | ------------------------------------------ |
| Server URL       | `https://ntfy.schultzsolutions.tech`       |
| Username         | `bob`                                      |
| Password         | *(the one you set in Step 1)*              |
| Access token     | `tk_...` *(from Step 3)*                   |

Tell them their topic prefix is `bob-` and they can pick any topic name
starting with it (e.g. `bob-price-alerts`).

## Step 5 — Friend configures the Price Tracker

The friend goes to `https://prices.schultzsolutions.tech/settings` after
logging into their Price Tracker account and:

1. Pastes `https://ntfy.schultzsolutions.tech/bob-price-alerts` into the
   **ntfy URL** field (they can pick any topic name starting with `bob-`)
2. Pastes the access token into the **Access token** field
3. Clicks **Save**
4. Clicks **Test** — should show a green "Sent!" and the corresponding
   notification will land once step 6 is complete

## Step 6 — Friend configures their phone

1. Install the ntfy app on their phone
   - **iOS:** [apps.apple.com/us/app/ntfy/id1625396347](https://apps.apple.com/us/app/ntfy/id1625396347)
   - **Android:** [Play Store](https://play.google.com/store/apps/details?id=io.heckel.ntfy) or F-Droid
2. Open the app → **Settings** → **Users**
3. Add a new user:
   - Server: `https://ntfy.schultzsolutions.tech`
   - Username: `bob`
   - Password: *(from Step 1)*
4. Back on the main screen, tap **+** → **Subscribe to topic**
5. Enter the topic name (`bob-price-alerts`) and — important — **select the
   custom server** (not the default `ntfy.sh`)
6. Tap Subscribe. Done.

Trigger another test from the Price Tracker Settings page and the
notification should land on their phone within a second.

## Alternate: web UI subscription

If your friend prefers browser notifications (no app install required),
they can log into `https://ntfy.schultzsolutions.tech` with username +
password, subscribe to their topic, and grant browser push permission.
This is handy as a backup channel or for folks who don't want the mobile
app.

## Ongoing management

| Task                              | Command                                           |
| --------------------------------- | ------------------------------------------------- |
| List all users                    | `ntfy user list`                                  |
| Change a user's password          | `ntfy user change-pass bob`                       |
| See a user's tokens               | `ntfy token list bob`                             |
| Revoke a single token             | `ntfy token remove bob tk_...`                    |
| Add another topic ACL for user    | `ntfy access bob 'other-topic-*' rw`              |
| Revoke a topic ACL                | `ntfy access --reset bob 'bob-*'`                 |
| Delete a user entirely            | `ntfy user del bob`                               |

Deleting a user removes all their tokens and ACL grants in one shot — no
cleanup needed.

## What friends cannot do (by design)

- **Read or publish to other users' topics** — ACL scopes them to `bob-*`
  only
- **See the user list or other accounts** — ntfy only exposes this to
  admins
- **Register new accounts** — `enable-signup: false` in `/etc/ntfy/server.yml`
- **Reserve topics outside their namespace** — the wildcard ACL is the
  hard boundary

You remain the only admin. The only way to escalate them is an explicit
`ntfy user change-role bob admin`.

## Troubleshooting

### "403 Forbidden" when the Price Tracker test button fires

The Authorization header is missing or the token is wrong. Double-check:

1. The token was copied in full (they start with `tk_` and are about 32
   characters)
2. The token wasn't generated for a different user
3. The topic in the URL matches the user's namespace (e.g. `bob` cannot
   publish to `andrew-price-alerts`)

### Mobile app shows "Unauthorized" when subscribing

The app is trying to subscribe without credentials, or it's using the
wrong server. In the app: **Settings → Users** → verify the custom server
is listed and the credentials are correct. Then when subscribing to a
topic, explicitly pick the custom server instead of the default `ntfy.sh`.

### Friend can subscribe but notifications never arrive

Confirm the Price Tracker is actually trying to publish. On CT 302:

```bash
journalctl -u price-tracker -n 50 --no-pager | grep -iE 'ntfy|notification'
```

Look for `"ntfy price alert sent"` (success) or `"ntfy price alert failed"`
with the HTTP status code. A `401` or `403` means auth is wrong; a `200`
means ntfy accepted it and the problem is downstream in the friend's
mobile app subscription.

### Everything worked once but stopped

Most likely: the token was rotated or the user was deleted. Run
`ntfy token list bob` to confirm the token is still present and still
owned by the right user.
