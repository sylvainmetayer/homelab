# Passerelle IA (ia.sylvain.cloud)

Procédure, pas un incident. La passerelle IA de Pangolin relaie les appels des
applis vers Anthropic, une clé virtuelle et des budgets par appli. Tout est en
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
| 429 | Budget en tokens de la clé ou de l'organisation dépassé |
| 4xx sur le modèle | Modèle absent de `local.ai_models` (liste d'autorisation) |

Pour Claude Code : `ANTHROPIC_BASE_URL=https://ia.sylvain.cloud`,
`ANTHROPIC_API_KEY=$K`.

## Brancher une appli

1. Une entrée dans `local.ai_keys` (`ai_gateway.tf`) : description,
   `budget_tokens` (bloquant, 2 M par défaut) et `budget_usd` (suivi seul, 5
   par défaut). PR, plan, apply : une clé et ses deux budgets créés.
2. Format de l'appli :
   - Anthropic : URL de base `https://ia.sylvain.cloud`.
   - OpenAI : `https://ia.sylvain.cloud/v1`. Anthropic sert un point
     compatible OpenAI (capacité `openai_chat` du fournisseur), sortie JSON
     structurée (`response_format`) comprise.
   - Ni l'un ni l'autre (Gemini…) : la passerelle ne traduit pas.
3. Le playbook de l'hôte lit la clé dans le state :
   `(terraform_outputs.ai_gateway_keys.value | default({})).<clé> | default('')`,
   dans un `set_fact` en `no_log: true`. Le rôle ne rend la config IA que si la
   clé est non vide. Modèle d'exemple : `immich_power_tools` (`pi.yml`, rôle
   `immich`, PR #1319).
4. Merge (déploiement CI, sauf `nas.yml`, `pve.yml`, `lxc.yml` : à la main),
   puis un essai dans l'appli elle-même.

La conso par clé se lit dans l'interface de Pangolin (AI Gateway).

## Remplacer une clé (fuite)

Lire le plan affiché avant de répondre `yes` : une clé remplacée, ses budgets,
rien d'autre. Pas de fichier `-out` : un plan enregistré contient les secrets en
clair.

```bash
mise exec -- tofu -chdir=tofu/pangolin_config apply -replace='pangolin_virtual_api_key.ai["<clé>"]'
```

- Les budgets de la clé sont recréés avec elle (`replace_triggered_by`) :
  Pangolin les supprime avec l'ancienne clé.
- Redéployer ensuite l'hôte de l'appli, qui garde sinon l'ancienne clé (401).
- La clé Anthropic elle-même (`pangolin_ai_anthropic_api_key`) :
  [rotation-des-secrets.md](rotation-des-secrets.md#cle-api-anthropic-passerelle-ia).

## Journal des appels

Éteint (« AI Gateway Session Log Retention » = 0, réglage de l'organisation
dans l'interface, hors Tofu ; le libellé français est différent). Pour
déboguer : le passer à 1 jour, reproduire, lire, le remettre à 0. Il garde les
prompts et les réponses en entier, sans masquage.

## Points ouverts

- **Les budgets en dollars ne bloquent pas.** Essai du 2026-11-09 : clé
  `essai` à 1 $ en `hard`, 12 appels Opus 5.5 de 8 000 tokens passés (200),
  sans 429. Ils ne comptent que les modèles du catalogue de prix de Pangolin
  (`/v1/org/<org>/ai-catalog-models`), où les `claude-*-5-5` manquent. Les
  budgets qui bloquent sont donc en tokens (`hard`), ceux en dollars en suivi
  (`soft`), en attendant que le catalogue suive. Les tokens comptent tous les
  modèles pareil (un token d'Opus coûte cinq fois un token de Haiku) : la
  limite du workspace Anthropic reste le dernier filet.
- **Pas de filtre France/Allemagne** : Pangolin refuse les règles sur une
  ressource `inference` (`local.unruled_resources`, `rules.tf`).
