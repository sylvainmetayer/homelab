---
name: pocket-id-app
description: Connect an existing homelab app to Pocket ID (OIDC login at id.sylvain.cloud) through Tofu - client, groups for admin/user roles, secret handed to Ansible without SOPS - while keeping a break-glass login. Use when asked to add OIDC / SSO / Pocket ID login to an app, or to map Pocket ID groups to an app's admin and user roles.
---

# Connect an app to Pocket ID

Pocket ID (ADR 0030, `docs/runbooks/pocket-id.md`) is the passkey-only OIDC
provider. Its clients and groups are declared in
`tofu/pangolin_config/pocket_id.tf` through its API (provider `trozz/pocketid`,
admin key `pocket_id_static_api_key` = the container's `STATIC_API_KEY`).
Homebox (client + group `homebox`) and the Pangolin wall (IdP « Pocket ID »)
are the two reference implementations: copy them.

## 0. Ask before starting (AskUserQuestion, options)

1. **Which app, and who logs in**: Sylvain only, or the household too?
   Household means each person needs a Pocket ID account (created by the
   admin, one-time code) and passkeys; say so.
2. **Admin vs user**: does the app read a role from OIDC? (section 2 says how
   to find out). If yes: which Pocket ID groups (`<app>-admin`, `<app>`), who
   goes in each. If no: roles stay in the app (invitations, local settings),
   OIDC only gates access; say it plainly.
3. **Break glass**: keep the app's local login (default, recommended), or
   OIDC only? Never remove the local login during the pilot (ADR 0030).
4. **Existing local accounts**: does the app link an OIDC login to an existing
   account (by email, by username) or create a new one? If unknown, say it is
   tested at the first login and the local account stays usable either way.
5. **Who does the UI steps**: Sylvain adds people to Pocket ID groups (Tofu
   never declares users, see pitfalls). Confirm he will.

Apply, deploys and SOPS writes follow the session's delegation
(`pangolin-config-plan` skill, section 0). Secrets never go through the chat.

## 1. Read the app's OIDC support, at the pinned version

From the app's docs **and code** at the image tag in its compose:

- the exact callback path, with or without trailing slash (declare both);
- **how it builds the callback URL**: from a hostname setting, from
  `X-Forwarded-*`, with or without adding the scheme itself (Homebox adds
  `https://` to `HBOX_OPTIONS_HOSTNAME`: a value with a scheme gave
  `https://https:/...`);
- PKCE: sent or not (a client with `pkce_enabled = true` refuses a flow
  without it);
- claims read: `groups` (needs the `groups` scope), a role claim, email;
- allowed-groups filter on the app side, if any;
- the switch that keeps the local login (`HBOX_OPTIONS_ALLOW_LOCAL_LOGIN`,
  Immich `passwordLogin`, Nextcloud `/login?direct=1`...).

`docs/login-unifie-applis.md` has a first pass per app; re-check it against the
current tag.

## 2. Admin vs user

Pocket ID only says who the person is and which groups they are in. The app
decides what that means:

| App reads | Pattern in `pocket_id.tf` |
|---|---|
| `groups` claim (Nextcloud `user_oidc`, Pangolin's JMESPath) | one `pocketid_group` per role (`<app>-admin`, `<app>`); scope `groups`; the app maps the group names |
| a role claim (Immich `immich_role`, TREK admin claim) | a group with `custom_claims = { <claim> = "admin" }`; members get the claim |
| nothing (Homebox 0.27.1) | one group to gate access (`allowed_user_groups`); roles stay in the app (Homebox: home owner, invitations) |

`allowed_user_groups` on the client lists every group that may log in (admins
included). **Empty or omitted means every Pocket ID user** (provider doc):
always set it, unless the app has its own gate (the Pangolin client has none
because Pangolin still requires an org user). A user in no listed group gets access denied at Pocket ID: put
Sylvain in the groups (UI), or the first test fails for a reason that looks
like a bug.

Pangolin itself: one role per user outside the paid edition; the pilot keeps
`role_mapping = "'Member'"`.

## 3. Declare it (copy Homebox)

In `tofu/pangolin_config/pocket_id.tf`:

```hcl
# toset(["pangolin", "homebox", "<app>"])
resource "random_password" "pocket_id_client" { ... }

resource "pocketid_group" "<app>" {
  name          = "<app>"          # technical name, sent in `groups`
  friendly_name = "<App>"
  # custom_claims = { immich_role = "admin" }   # role-claim apps, admin group only
}

resource "pocketid_client" "<app>" {
  name                = "<App>"
  client_id           = "<app>"      # ALWAYS set: unset, the provider leaves it empty
  client_secret       = random_password.pocket_id_client["<app>"].result
  callback_urls       = ["https://<host>/<path>", "https://<host>/<path>/"]
  allowed_user_groups = [pocketid_group.<app>.id]
  launch_url          = "https://<host>"   # else hidden from « My apps »
  pkce_enabled        = true         # Pangolin and Homebox send it; false only if the app does not
  is_public           = false
}

output "pocket_id_<app>_client_id"     { value = pocketid_client.<app>.client_id }
output "pocket_id_<app>_client_secret" {
  value     = random_password.pocket_id_client["<app>"].result
  sensitive = true
}
```

In the app's role, **defaults** read the outputs (as `homebox` does), so
nothing in the playbook changes:

```yaml
<app>_oidc_client_id: "{{ terraform_outputs.pocket_id_<app>_client_id.value | default('') }}"
<app>_oidc_client_secret: "{{ terraform_outputs.pocket_id_<app>_client_secret.value | default('') }}"
<app>_oidc_enabled: "{{ <app>_oidc_client_id | length > 0 and <app>_oidc_client_secret | length > 0 }}"
```

Render the OIDC block of the app's env only when enabled, local login kept
on, secrets in the `0600` env with `diff: false` (AGENTS.md).

Tests:

- `tofu/pangolin_config/tests/invariants.tftest.hcl`, run
  `pocket_id_stays_outside_the_sso_wall_and_provisions_nobody`: assert the
  client (confidential, PKCE as decided, callback, groups) and that the role
  defaults read `terraform_outputs.pocket_id_<app>_client_secret.value`.
- Molecule `converge.yml` of the app: `vars: terraform_outputs:` with fake
  `value`s (see `ansible/molecule/homebox/converge.yml`); `verify.yml` asserts
  the OIDC env lines and the local-login switch.
- `mise exec -- tofu -chdir=tofu/pangolin_config test`.

Docs: the app's role README (OIDC, break glass, where roles live),
`docs/runbooks/pocket-id.md` (one line per app), the table of
`docs/login-unifie-applis.md`.

## 4. Apply, deploy, test

1. `pangolin-config-plan` skill: the plan must hold only the new
   `random_password`, `pocketid_group`(s), `pocketid_client` and nothing else.
2. Deploy the app's role from the workstation (`--check` first, then for
   real): CI deploys only from 08:00 (ADR 0029) and is slow. `nas.yml`,
   `pve.yml`, `lxc.yml` are by hand anyway.
3. Check the app logs say OIDC initialised with the right `client_id` and
   issuer.
4. Sylvain adds himself (and whoever was agreed) to the groups in Pocket ID
   (Administration, Users, Groups), then tests in a private window. Then the
   local login, to prove the break glass still works.

## Pitfalls already hit (2026-11-05)

| Symptom | Cause | Avoid |
|---|---|---|
| Pocket ID pages blank, `NS_ERROR_CORRUPTED_CONTENT`, « disallowed MIME type ("") » | Traefik rate limit on `id.sylvain.cloud` returned 429: a page loads ~100 files | `pangolin_idp_rate_burst` 300 (role `pangolin`); blank page again: check 429 first |
| `redirect_uri 'https://https:/...' is not registered` | app prepends the scheme to a hostname setting that already had one | section 1: read how the app builds the callback |
| `403 Key does not have root access` creating `pangolin_idp` | Pangolin org key cannot create an IdP | provider alias `pangolin.root`, key `pangolin_root_api_key` (IdP actions + « get organization ») |
| `Pangolin API key lacks access ... 403` at plan | provider start-up probe `GET /org/<org>` | root key also has « get organization » |
| Pangolin: `User with username sylvain is unprovisioned` | `auto_provision = false`: no org user is created at login | create the external user in the org (IdP Pocket ID, same username, role) |
| Tofu cycle client ↔ IdP | client callback is the IdP's `redirect_url`, IdP needs the client id | fixed `client_id` literal (local), not read from the resource |
| Pocket ID « My apps » empty | the launcher lists only clients with a `launch_url` | set `launch_url` on every client |
| `HBOX_OIDC_CLIENT_ID` empty | `pocketid_client.client_id` stays null unless set | always set `client_id` |
| `tofu test`: `invalid callback URL` | mocked `redirect_url` is random | `mock_resource "pangolin_idp"` with a URL default on the `root` alias mock (both test files) |
| plan of the whole module fails | Pocket ID down, `pocketid_*` cannot refresh | `-exclude=pocketid_client.<x>` ... for the unrelated change |
| merge redeploys a whole playbook | outputs read in a playbook's `pre_tasks` | read them in the role's defaults |
| plan wants to destroy what was just merged | worktree from a stale `FETCH_HEAD` | `pangolin-config-plan` section 1 |
| secret visible in the session | `tofu show -json`, `tofu output` of a sensitive value | never; text plan only, `random_password` for client secrets |

Never declare a `pocketid_user`: an apply must never be able to modify or
delete the admin account. Membership is set in the UI.

## Break glass, always

- the app's local login stays on (its switch in the env, asserted in Molecule);
- Pangolin: the organisation's internal **owner** account (password + 2FA),
  never linked to the IdP;
- Pocket ID itself: one-time access code created on the host
  (`docs/runbooks/pocket-id.md`, « Secours »).
