# 0032. Passerelle IA de Pangolin : une clé et un budget par appli

- **Statut** : acceptée
- **Date** : 2026-11-09

## Contexte

Plusieurs applis savent appeler un modèle de langage (Immich Power Tools,
Karakeep, Papra, Nextcloud Assistant, HealthLog, Open WebUI). Une clé
Anthropic par appli, c'est autant de secrets, aucune vue de la conso par appli
et aucun plafond en dehors de la limite du compte Anthropic.

## Décision

- **Passerelle IA de Pangolin** (AI Gateway, ≥ 1.22) : ressource `inference`
  `https://ia.sylvain.cloud`, un fournisseur Anthropic, modèles autorisés
  Haiku, Sonnet, Opus 5.5, tout en Tofu (`tofu/pangolin_config/ai_gateway.tf`).
- **Une clé virtuelle par appli**, lue par Ansible dans le state
  (`ai_gateway_keys`), jamais en SOPS ; seule la clé Anthropic l'est.
- **Deux budgets par clé** : en tokens, bloquant, sur `lifetime` ; en dollars,
  en suivi seul. En 1.26.0, toute période compte 0 (fosrl/pangolin#4077) et le
  catalogue de prix ignore les modèles 5.5.
- **Format OpenAI** pour les applis qui ne parlent qu'OpenAI : le point
  compatible d'Anthropic (capacité `openai_chat`), sortie structurée comprise.
- **Pas de filtre FR/DE** : Pangolin refuse toute règle sur une ressource
  `inference` ; exception à 0002, nommée dans `local.unruled_resources`.
- **Journal des appels éteint** (prompts et réponses en clair), rallumé
  quelques heures pour déboguer.

## Alternatives écartées

- LiteLLM : 4 Gio de mémoire, une base Postgres de plus, et la compromission
  de son paquet PyPI en mars 2026.
- Une clé Anthropic par appli : pas de suivi par appli, plus de secrets.
- OpenRouter : un intermédiaire de plus qui voit tous les prompts.

## Conséquences

- Conso par appli dans Pangolin ; une clé qui fuit se remplace seule
  (`-replace`), sans toucher les autres applis.
- Budgets `lifetime` sans remise à zéro : à relever à la main quand ils
  bloquent, et à repasser en `monthly` quand #4077 sera publiée.
- Pas d'embeddings (Anthropic n'en sert pas) : pas de recherche sémantique.
- Tout dépend de Pangolin : s'il tombe, les fonctions IA des applis aussi.

## Liens

PR #1316 à #1327 ; `docs/runbooks/passerelle-ia.md` ;
`tofu/pangolin_config/README.md` ; fosrl/pangolin#4077.
