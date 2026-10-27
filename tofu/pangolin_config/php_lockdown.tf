# ---------------------------------------------------------------------------
# Temporary lockdown of the PHP apps, until a critical PHP vulnerability
# disclosed on 2026-10-21 is patched in their images.
#
# Every public path that reached PHP code without the SSO wall is closed:
#
#   - every PHP resource without SSO gets it. The set is empty again: Betisier
#     left it once its image moved to PHP 8.5.12 (sylvainmetayer/Betisier-TP#1),
#     nextcloud once its image was patched.
#   - the path ACCEPTs of Monica (`/dav`, `.well-known`), open worldwide, are
#     disabled rather than deleted: a disabled rule keeps its id, its backslash
#     guard and path_bypass_images.json as they are. FreshRSS's (Google Reader
#     and Fever APIs) are gone for good: it is read in the browser only, its API
#     is off (website_rss.tf).
#
# BookStack was already behind the SSO with no bypass.
#
# Lifting it: empty both sets once
# the patched images are deployed, then apply. Phone sync (CardDAV/CalDAV on
# Monica) is down until then.
# ---------------------------------------------------------------------------
locals {
  # Keys of local.websites forced behind the SSO, whatever their entry says.
  php_lockdown_sso = toset([])

  # Keys of local.path_bypasses whose ACCEPTs are disabled.
  php_lockdown_path_bypasses = toset(["Monica CRM"])
}
