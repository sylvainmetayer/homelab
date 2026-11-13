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
- **Deux budgets par clé** (retirés le 2026-11-13, voir Conséquences) : tokens,
  bloquant, sur `lifetime` ; dollars, suivi seul. En 1.26.0 toute période compte 0 (fosrl/pangolin#4077) et le catalogue
  de prix ignore les modèles 5.5.
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
- Budgets `lifetime` sans remise à zéro : à relever à la main, à repasser en
  `monthly` quand #4077 sera publiée.
- **Mise à jour du 2026-11-13** : les budgets sont retirés du code, jamais
  appliqués en entier ; seule la limite du workspace Anthropic plafonne la
  dépense. À remettre (mensuels) quand une version de Pangolin contiendra #4077.
- Pas d'embeddings (Anthropic n'en sert pas) ; si Pangolin tombe, l'IA des applis aussi.

## Liens

`docs/runbooks/passerelle-ia.md`, `tofu/pangolin_config/README.md`, fosrl/pangolin#4077.
