# Passerelle IA (ia.sylvain.cloud)

Procédure, pas un incident. La passerelle IA de Pangolin relaie les appels des
applis vers Anthropic, une clé virtuelle par appli (sans budget pour l'instant). Tout est en
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
| 429 | Limite de débit ou de dépense côté Anthropic (pas de budget de passerelle) |
| 4xx sur le modèle | Modèle absent de `local.ai_models` (liste d'autorisation) |

Pour Claude Code : `ANTHROPIC_BASE_URL=https://ia.sylvain.cloud`,
`ANTHROPIC_API_KEY=$K`.

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

La conso par clé se lit dans l'interface de Pangolin (AI Gateway).

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

## Journal des appels

Gardé 90 jours (« AI Gateway Session Log Retention », réglage de
l'organisation : `log_retention_days_ai_sessions` de
`tofu/pangolin_config/org.tf`, décision du 12/11/2026). Il garde les prompts et
les réponses en entier, sans masquage, dans la base de Pangolin et ses
sauvegardes. Pour l'éteindre : `0`, par PR.

## Points ouverts

- **Aucun budget de passerelle** (retirés le 2026-11-13) : les budgets en
  dollars ne comptent que les modèles du catalogue de prix de Pangolin, où les
  `claude-*-5-5` manquaient (essai du 2026-11-09 : 12 appels Opus à 1 $ `hard`
  sans 429), et les budgets périodiques en tokens ne bloquent jamais en
  1.26.0 (fosrl/pangolin#4077, corrigé en amont mais pas publié). Seul filet :
  la limite de dépense du workspace Anthropic. À remettre (mensuels) quand une
  version de Pangolin contient #4077 : blocs `pangolin_ai_budget` dans
  l'historique git de `ai_gateway.tf`.
- **Pas de filtre France/Allemagne** : Pangolin refuse les règles sur une
  ressource `inference` (`local.unruled_resources`, `rules.tf`).
