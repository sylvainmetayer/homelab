# 0032. Passerelle IA de Pangolin : une clé et un budget par appli

- **Statut** : acceptée
- **Date** : 2026-11-09

## Contexte

Plusieurs applis appellent un modèle de langage (Karakeep, Papra, Nextcloud,
HealthLog, Open WebUI). Une clé Anthropic par appli : autant de secrets, ni
conso par appli ni plafond.

## Décision

- **Passerelle IA de Pangolin** (≥ 1.22) : ressource `inference`
  `https://ia.sylvain.cloud`, fournisseur Anthropic, modèles Haiku, Sonnet et
  Opus 5.5, en Tofu (`tofu/pangolin_config/ai_gateway.tf`).
- **Une clé virtuelle par appli**, lue par Ansible dans le state
  (`ai_gateway_keys`), jamais en SOPS (seule la clé Anthropic l'est).
- **Deux budgets par clé et pour l'organisation**, `monthly` (fenêtre glissante
  de 30 jours) : tokens, bloquant ; dollars, suivi seul. Retirés le 2026-11-13
  (fosrl/pangolin#4077), remis le 2026-11-22 avec Pangolin 1.27.0.
- **Format OpenAI** pour les applis qui ne parlent que lui : le point
  compatible d'Anthropic (`openai_chat`).
- **Pas de filtre FR/DE** : Pangolin refuse toute règle sur une ressource
  `inference` ; exception à 0002 (`local.unruled_resources`).
- **Journal des appels éteint** (prompts en clair), rallumé le temps d'un débogage.
  Note du 12/11/2026 : l'instance le gardait en fait 90 jours ; gardé ainsi par
  décision de Sylvain (`log_retention_days_ai_sessions`, `tofu/pangolin_config/org.tf`).

## Alternatives écartées

- LiteLLM : 4 Gio, un Postgres de plus, paquet PyPI compromis en mars 2026.
- Une clé Anthropic par appli : ni suivi par appli, ni budget, plus de secrets.
- OpenRouter : un intermédiaire de plus qui voit tous les prompts.

## Conséquences

- Conso par appli dans Pangolin ; une clé qui fuit se remplace seule (`-replace`).
- Budgets sur 30 jours glissants : un plafond trop juste se relève par PR.
- **Mise à jour du 2026-11-13** : budgets retirés du code (1.26 ne bloquait jamais
  un budget périodique). **2026-11-22** : remis avec 1.27.0, voir le runbook.
- Pas d'embeddings (Anthropic n'en sert pas) ; si Pangolin tombe, l'IA des applis aussi.

## Liens

`docs/runbooks/passerelle-ia.md`, `tofu/pangolin_config/README.md`, fosrl/pangolin#4077.
