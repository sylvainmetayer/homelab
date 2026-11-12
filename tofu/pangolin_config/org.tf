# L'organisation Pangolin elle-même : ses réglages (rétention des journaux,
# mise à jour automatique de Newt, politique de session) deviennent visibles
# dans le plan. Importée à la main (README, « Organisation »), jamais créée.
#
# prevent_destroy : supprimer l'organisation supprime sites, ressources, rôles
# et clés. Il arrête aussi un remplacement (subnet ou utility_subnet modifiés).
# Il ne protège PAS d'un plan lancé depuis un checkout d'avant ce fichier, qui
# proposerait « destroy, not in configuration » : ne jamais appliquer un plan
# qui touche pangolin_org.this autrement qu'en « update in-place ».
# Retirer ce fichier (ou revert) planifie la même destruction : d'abord
# `tofu state rm pangolin_org.this`.
#
# Tous les attributs optional+computed sont déclarés (règle du module) ;
# password_expiry_days reste absent : le serveur le rend nul (pas d'expiration)
# et le provider ne sait pas écrire « nul » autrement qu'en ne le posant pas.
resource "pangolin_org" "this" {
  org_id         = local.pangolin_org_id
  name           = "sylvain"
  subnet         = "100.90.128.0/24"
  utility_subnet = "100.96.128.0/24"

  require_two_factor       = false
  max_session_length_hours = 720
  newt_auto_update         = true

  # Journal des requêtes (trafic du proxy) : c'est lui qui grossit la base
  # SQLite de Pangolin (924 Mo le 12/11/2026 à 30 jours).
  log_retention_days_request    = 7
  log_retention_days_connection = 30
  log_retention_days_access     = 90
  log_retention_days_action     = 90
  log_retention_days_ssh        = 0
  # Journal des sessions IA : 90 jours, gardé tel que trouvé le 12/11/2026
  # (décision de Sylvain). Il garde prompts et réponses en entier, sans
  # masquage (README, « AI gateway ») : 0 l'éteint.
  log_retention_days_ai_sessions = 90

  lifecycle {
    prevent_destroy = true
  }
}
