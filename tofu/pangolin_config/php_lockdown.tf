# ---------------------------------------------------------------------------
# Temporary lockdown of the PHP apps, until a critical PHP vulnerability
# disclosed on 2026-10-21 is patched in their images.
#
# Every public path that reached PHP code without the SSO wall is closed:
#
#   - Betisier and nextcloud, the two PHP resources without SSO, get it. No
#     role is bound: only the Pangolin admins get through, and the apps'
#     monitors keep working on their access tokens.
#   - the path ACCEPTs of Monica (`/dav`, `.well-known`) and FreshRSS (Google
#     Reader and Fever APIs), open worldwide, are disabled rather than deleted:
#     a deleted rule would still be live in Pangolin at plan time and fail the
#     rule inventory audit (rules.tf), and a disabled one keeps its id, its
#     backslash guard and path_bypass_images.json as they are.
#
# BookStack was already behind the SSO with no bypass.
#
# Lifting it: empty both sets (or revert the commit that added this file) once
# the patched images are deployed, then apply. Phone sync (CardDAV/CalDAV on
# Monica, RSS readers on FreshRSS) and non-admin access to nextcloud and
# Betisier are down until then.
# ---------------------------------------------------------------------------
locals {
  # Keys of local.websites forced behind the SSO, whatever their entry says.
  php_lockdown_sso = toset(["betisier", "nextcloud"])

  # Keys of local.path_bypasses whose ACCEPTs are disabled.
  php_lockdown_path_bypasses = toset(["Monica CRM", "RSS"])
}
