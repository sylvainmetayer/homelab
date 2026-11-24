# Passerelle IA (ia.sylvain.cloud)

Procédure, pas un incident. La passerelle IA de Pangolin relaie les appels des
applis vers Anthropic, une clé virtuelle par appli, chacune avec deux budgets (voir « Budgets »). Tout est en
Tofu : `tofu/pangolin_config/ai_gateway.tf` (détail dans le README du module).

## Tester une clé

Depuis un worktree à jour de `main`, `tofu/pangolin_config` initialisé :

```bash
K=$(mise exec -- tofu -chdir=tofu/pangolin_config output -json ai_gateway_keys | jq -r .essai)

# Format Anthropic
curl https://ia.sylvain.cloud/v1/messages -H "x-api-key: $K" \
  -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
  -d '{"model":"claude-haiku-5-5","max_tokens":50,"messages":[{"role":"user","content":"Bonjour"}]}'

# Format OpenAI (applis qui ne parlent qu'OpenAI)
curl https://ia.sylvain.cloud/v1/chat/completions -H "Authorization: Bearer $K" \
  -H 'content-type: application/json' \
  -d '{"model":"claude-haiku-5-5","max_tokens":50,"messages":[{"role":"user","content":"Bonjour"}]}'
```

- Remplacer `essai` par le nom de la clé de l'appli (`immich_power_tools`…).
- Ne jamais afficher la clé : pas d'`echo $K`, pas de `tofu output` brut dans
  un terminal partagé ou une session d'agent.
- `x-api-key` et `Authorization: Bearer` marchent tous les deux.
- La clé est `pangolin-key-<id>.<secret>` : l'output la donne déjà entière.

| Réponse | Sens |
|---|---|
| 200 | La clé, le modèle et le fournisseur marchent |
| 401 `Invalid API key` | Clé incomplète (secret seul, sans `pangolin-key-<id>.`), ou clé remplacée |
| 429 | Budget en tokens de la clé ou de l'organisation atteint (`essai` l'est exprès), ou limite de débit ou de dépense côté Anthropic |
| 4xx sur le modèle | Modèle absent de `local.ai_models` (liste d'autorisation) |

Pour Claude Code : `ANTHROPIC_BASE_URL=https://ia.sylvain.cloud`,
`ANTHROPIC_API_KEY=$K`.

## Modèles d'OpenRouter

Second fournisseur, pour les essais (clé `openrouter`). Format OpenAI
seulement, avec le nom OpenRouter du modèle (liste sur openrouter.ai/models) :

```bash
K=$(mise exec -- tofu -chdir=tofu/pangolin_config output -json ai_gateway_keys | jq -r .openrouter)
curl https://ia.sylvain.cloud/v1/chat/completions -H "Authorization: Bearer $K" \
  -H 'content-type: application/json' \
  -d '{"model":"mistralai/mistral-small-3.2-24b-instruct","max_tokens":50,"messages":[{"role":"user","content":"Bonjour"}]}'
```

- Pangolin route par nom de modèle : `claude-*` va chez Anthropic, ce qui
  correspond à `local.ai_openrouter_models` (`mistralai/*`, `openai/*`,
  `google/*`, `*:free`) chez OpenRouter. Un autre éditeur : un joker de plus.
- Toute clé virtuelle peut appeler ces modèles. Les `:free` gardent souvent
  les prompts (réglages de confidentialité du compte OpenRouter) : jamais de
  données de santé, de documents ni le chat du foyer.
- Le coût en dollars de Pangolin n'est qu'une estimation pour ces modèles ;
  la limite de crédit du compte OpenRouter est le vrai plafond.
- Couper : `local.ai_openrouter_enabled = false`, plan, apply.

## Brancher une appli

1. Une entrée dans `local.ai_keys` (`ai_gateway.tf`) : description.
   PR, plan, apply : une clé créée.
2. Format de l'appli :
   - Anthropic : URL de base `https://ia.sylvain.cloud`.
   - OpenAI : `https://ia.sylvain.cloud/v1`. Anthropic sert un point
     compatible OpenAI (capacité `openai_chat` du fournisseur), sortie JSON
     structurée (`response_format`) comprise.
   - Ni l'un ni l'autre (Gemini…) : la passerelle ne traduit pas.
3. Le rôle lit la clé dans le state :
   `(terraform_outputs.ai_gateway_keys.value | default({})).<clé> | default('')`,
   dans ses `defaults` (Karakeep, Papra, comme leurs secrets OIDC) ou dans un
   `set_fact` en `no_log: true` du playbook (`immich_power_tools`, `pi.yml`).
   Le fichier qui la porte est rendu en `0600` avec `diff: false`, et la config
   IA n'est rendue que si la clé est non vide. Réglée dans l'interface de
   l'appli (Nextcloud, HealthLog) : README du rôle.
4. Merge (déploiement CI, sauf `nas.yml`, `pve.yml`, `lxc.yml` : à la main),
   puis un essai dans l'appli elle-même.

La conso par clé se lit dans l'interface de Pangolin (AI Gateway) ou par l'API (voir « Budgets »).

## Remplacer une clé (fuite)

Lire le plan affiché avant de répondre `yes` : une clé remplacée, rien
d'autre. Pas de fichier `-out` : un plan enregistré contient les secrets en
clair.

```bash
mise exec -- tofu -chdir=tofu/pangolin_config apply -replace='pangolin_virtual_api_key.ai["<clé>"]'
```

- Redéployer ensuite l'hôte de l'appli, qui garde sinon l'ancienne clé (401).
- La clé Anthropic elle-même (`pangolin_ai_anthropic_api_key`) :
  [rotation-des-secrets.md](rotation-des-secrets.md#cle-api-anthropic-passerelle-ia).
- La clé OpenRouter (`pangolin_ai_openrouter_api_key`) :
  [rotation-des-secrets.md](rotation-des-secrets.md#cle-api-openrouter-passerelle-ia).

## Budgets

Deux budgets par clé et deux pour l'organisation (`pangolin_ai_budget`,
`ai_gateway.tf`, remis le 2026-11-22 avec Pangolin 1.27.0 qui corrige
fosrl/pangolin#4077), tous `monthly`, soit une fenêtre **glissante de 30 jours**
et non le mois civil :

- en **tokens**, `hard` : au-delà, 429 ;
- en **dollars**, `soft` : suivi seul, par choix (1.27 compte pourtant le coût
  des `claude-*-5-5`).

Les montants sont dans `local.ai_keys` (`budget_tokens`, `budget_usd`) et
`local.ai_budget_total_*`. La clé `essai` est bloquée dès l'apply, exprès :
elle sert à vérifier le refus. `karakeep` est à 40 M tokens parce que son
rattrapage du 9-10/11 reste dans la fenêtre jusque vers le 10/12 ; la ramener à
5 000 000 après le 2026-12-11 (pas d'automatisme). Un budget qui bloque à tort :
relever le montant par PR. Le plafond de dépense du workspace Anthropic reste le
dernier filet.

Lire la consommation (clé d'API Pangolin, lecture) :

```bash
# <api> : hôte de l'API d'intégration (pangolin_api_url, derrière int-api-allowlist),
# pas celui du tableau de bord. Période : les 30 derniers jours, comme la fenêtre.
curl -s -H "Authorization: Bearer $PANGOLIN_API_KEY" \
  "https://<api>/v1/org/<org>/logs/ai/usage/virtual-api-keys?timeStart=$(date -u -d '30 days ago' +%FT%TZ)&timeEnd=$(date -u +%FT%TZ)"
```

## Journal des appels

Gardé 90 jours (« AI Gateway Session Log Retention », réglage de
l'organisation : `log_retention_days_ai_sessions` de
`tofu/pangolin_config/org.tf`, décision du 12/11/2026). Il garde les prompts et
les réponses en entier, sans masquage, dans la base de Pangolin et ses
sauvegardes. Pour l'éteindre : `0`, par PR.

## Points ouverts

- **Pas de filtre France/Allemagne** : Pangolin refuse les règles sur une
  ressource `inference` (`local.unruled_resources`, `rules.tf`).
