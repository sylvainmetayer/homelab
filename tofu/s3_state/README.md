# tofu/s3_state

Le bucket S3 OVH (Object Storage, `eu-west-par`) qui contient les states de
tous les autres modules (`homelab-tf-state-sylvain`, versionné, SSE-OMK), et les
deux utilisateurs S3 qui y accèdent. Séparé des autres modules : un module ne
doit pas gérer le bucket qui contient son propre state. Backends, clés de state
et chiffrement : [docs/conventions/opentofu.md](../../docs/conventions/opentofu.md).

## Ce qu'il crée

- Le bucket (`storage.tf`), versionné : une version précédente d'un state se
  retrouve dans les versions de l'objet.
- `tf_state` (`user.tf`) : l'utilisateur dont les clés S3 sont les `AWS_*` du
  SOPS racine, lues par le backend de **tous** les modules. Ses clés ont été
  renouvelées le 23/10/2026 (nouvelle ressource, bascule de SOPS, suppression
  de l'ancienne dans un second apply : le backend de ce module écrit son state
  avec ces clés-là).
- `ansible_state_reader` (`user_ansible.tf`) : lit le seul state de
  `tofu/pangolin_config` pour Ansible (`state_s3_access_key` et
  `state_s3_secret_key` de `secrets/ansible.sops.yaml`, déchiffrées par la CI de
  déploiement) ; il ne peut ni écrire ni lire les autres states.

## À savoir

- **Son propre state** est dans le bucket qu'il gère (`homelab/s3_state.tfstate`),
  chiffré (`encryption.tf`, AES-GCM, phrase `state_encryption_passphrase` du SOPS
  racine) : il contient les clés S3 des deux utilisateurs. Un bucket détruit
  emporte donc le state qui permettrait de le recréer : rien ne l'empêche
  aujourd'hui (pas de `prevent_destroy`), lire le plan avant tout apply.
- Initialisation, plan, apply : depuis `tofu/s3_state`, sous `mise exec --`
  (l'environnement SOPS) ; Sylvain applique. Les clés OVH du provider viennent
  de `secrets.tf` (SOPS).
- Tests : `tests/s3_state.tftest.hcl` (`mise run tofu-test`).
