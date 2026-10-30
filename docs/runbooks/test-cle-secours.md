---
# Date du dernier test réussi (AAAA-MM-JJ), lue par
# .github/scripts/check_secret_rotation.py : le workflow Secrets rotation
# passe le moniteur « Rotation des secrets » à « down » au-delà de 100 jours.
# Valeur initiale : l'ajout de la clé (f7be1d86), pas un test connu.
dernier_test: 2026-10-23
---

# Tester la clé age `secours` (chaque trimestre)

Procédure, pas un incident. La clé `secours` est la clé age hors ligne qui
ouvre les deux fichiers SOPS quand `perso` et `pro` sont perdues
([perte-cle-ou-poste.md](perte-cle-ou-poste.md)). Elle ne sert jamais
autrement : rien ne dirait qu'elle est abîmée, illisible, ou que les
fichiers ne sont plus chiffrés pour elle, avant le jour où on en a besoin.

Deux contrôles :

- **automatique** (workflow Lint, chaque PR) :
  `.github/scripts/check_age_recipients.py` compare les destinataires age
  inscrits en clair dans chaque `secrets.sops.yaml` à la règle de
  `.sops.yaml` qui le désigne, et exige `secours` dans chaque règle. Un
  fichier rechiffré sans elle, ou pour une clé de trop, fait échouer le
  Lint. Il ne prouve pas que la clé privée existe encore ni qu'elle ouvre
  quoi que ce soit ;
- **manuel** (ce runbook, chaque trimestre) : déchiffrer les deux fichiers
  avec la clé `secours` seule. Le workflow Secrets rotation (chaque lundi)
  passe le moniteur « Rotation des secrets » à « down » quand
  `dernier_test`, en tête de ce fichier, a plus de 100 jours.

## Le test

1. Sortir la clé de sa cachette hors ligne et la monter sur le poste, par
   exemple une clé USB en `/run/media/sylvain/SECOURS/secours.key`. Ne
   jamais la copier sur le disque du poste.
2. Depuis la racine du dépôt (à jour de `main`, sur une branche) :

   ```bash
   mise run test-cle-secours /run/media/sylvain/SECOURS/secours.key
   ```

   Le script (`.github/scripts/secours_key_check.py`) fait les étapes
   manuelles ci-dessous, dans l'ordre, et n'affiche que des lignes `ok` /
   `ÉCHEC` : la clé publique (`age-keygen -y`) est celle de la ligne
   `# secours` de `.sops.yaml` ; chaque fichier SOPS se déchiffre avec cette
   clé seule (environnement vide, `HOME` temporaire vide, sortie jetée) ; la
   contre-épreuve (`SOPS_AGE_KEY_FILE=/dev/null`) échoue sur « Failed to
   get the data key » (un autre échec ne prouve pas l'isolement). Un fichier
   de clé à plusieurs identités est refusé. Tout `ok` : il
   met `dernier_test` (en tête de ce fichier) à la date du jour. La clé
   n'est passée que par son chemin à `age-keygen` et à `sops`, jamais
   copiée ni affichée.

   `mise run` déchiffre d'abord `secrets.sops.yaml` pour son environnement
   (`_.file` de `mise.toml`) : si `perso` et `pro` sont perdues, il échoue
   avant le script. Le lancer alors sans mise, avec les binaires installés
   par mise (les vrais, pas les shims ; versions de `mise.toml`) :

   ```bash
   I=~/.local/share/mise/installs
   python3 -I .github/scripts/secours_key_check.py \
     --sops "$I/sops/<version>/sops" --age-keygen "$I/age/<version>/age/age-keygen" \
     /run/media/sylvain/SECOURS/secours.key
   ```

3. Démonter et ranger la clé.
4. Tout `ok` : committer `dernier_test`, PR, merge. Le moniteur repasse
   « up » au prochain lundi (ou relancer le workflow Secrets rotation à la
   main). Un `ÉCHEC` : `dernier_test` n'est pas touché, voir « En cas
   d'échec ».

### À la main (si le script ne tourne pas)

1. Vérifier que c'est bien la clé `secours` : sa clé publique doit être
   celle de la ligne `# secours` de `.sops.yaml` (comparée par `grep`, une
   clé post-quantique fait ~2 000 caractères) :

   ```bash
   KEY=/run/media/sylvain/SECOURS/secours.key
   PUB=$(mise exec -- age-keygen -y "$KEY")
   [ -n "$PUB" ] && grep -F -- "$PUB" .sops.yaml | grep -q '# secours' && echo ok || echo ÉCHEC
   ```

2. Déchiffrer les deux fichiers avec **cette clé seule**. sops additionne
   toutes les clés qu'il trouve : `SOPS_AGE_KEY_FILE` s'ajoute à
   `SOPS_AGE_KEY`, à `~/.config/sops/age/keys.txt` (présent sur le poste)
   et à `~/.ssh/id_ed25519`, il ne les remplace pas (`.sopsrc` n'est lu
   que par l'extension d'éditeur, pas par sops). Sans isolement, le test réussirait avec la clé
   `perso` et ne prouverait rien. D'où `env -i` (ni `SOPS_AGE_KEY` ni
   l'environnement de mise) et un `HOME` vide (pas de `keys.txt`) :

   ```bash
   SOPS=$(mise which sops)
   EMPTY=$(mktemp -d)
   for f in secrets.sops.yaml ansible/secrets.sops.yaml; do
     env -i PATH=/usr/bin:/bin HOME="$EMPTY" SOPS_AGE_KEY_FILE="$KEY" \
       "$SOPS" decrypt "$f" > /dev/null && echo "ok $f" || echo "ÉCHEC $f"
   done
   rmdir "$EMPTY"
   ```

   Rien ne s'affiche des secrets : la sortie va à `/dev/null`. Contre-épreuve
   (pour se convaincre de l'isolement ; le script la fait à chaque fois) :
   la même boucle avec `SOPS_AGE_KEY_FILE=/dev/null` doit afficher deux
   `ÉCHEC` (« Failed to get the data key »), alors que, sans `env -i` ni
   `HOME` vide, elle affiche deux `ok` grâce à `keys.txt` (vérifié le
   2026-10-28).
3. Deux `ok` : mettre `dernier_test` (en tête de ce fichier) à la date du
   jour à la main.

## En cas d'échec

- **`age-keygen -y` échoue, ou affiche une autre clé** : la clé est
  abîmée, ou ce n'est pas la bonne. Chercher l'autre copie, s'il y en a
  une. Sinon, en faire une nouvelle (ci-dessous) : tant qu'elle n'est pas
  posée, `perso` et `pro` sont les seules clés.
- **la clé publique est la bonne, mais `ÉCHEC`** : un fichier n'est plus
  chiffré pour elle. Le Lint (`check_age_recipients.py`) aurait dû
  l'attraper : regarder `python -I .github/scripts/check_age_recipients.py`.
  Rechiffrer avec une clé qui ouvre encore (`perso`) :
  `sops updatekeys <fichier>`, PR, puis refaire le test.

### Remplacer la clé `secours`

1. Sur un poste de confiance, sans réseau si possible :
   `age-keygen -pq -o /run/media/sylvain/SECOURS/secours.key` (clé
   post-quantique `age1pq1…` ; sa clé publique, ~2 000 caractères :
   `age-keygen -y` sur le fichier). Faire la deuxième copie hors ligne
   (papier, seconde clé USB) tout de suite.
2. Remplacer la ligne `# secours` dans les **deux** règles de `.sops.yaml`,
   puis, consigne en tête de `.sops.yaml` :

   ```bash
   sops updatekeys secrets.sops.yaml
   sops updatekeys ansible/secrets.sops.yaml
   sops rotate -i secrets.sops.yaml
   sops rotate -i ansible/secrets.sops.yaml
   ```

3. PR, merge, puis le test ci-dessus avec la nouvelle clé, et
   `dernier_test` à la date du jour.

L'ancienne clé ouvre toujours les versions de l'historique git : si elle a
pu être lue par un tiers (et pas seulement perdue), c'est le cas « clé
volée » de [perte-cle-ou-poste.md](perte-cle-ou-poste.md).
