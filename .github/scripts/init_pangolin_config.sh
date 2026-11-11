#!/usr/bin/env bash
# Initialise tofu/pangolin_config sur le runner de déploiement, pour que la
# tâche Ansible commune (ansible/tasks/pangolin_config_outputs.yml) y lise les
# sorties par `tofu output -json`. Les identifiants S3 du state (compte en
# lecture seule) et la passphrase dédiée de son chiffrement viennent de
# secrets/ansible.sops.yaml, que la clé age de la CI déchiffre (SOPS_AGE_KEY).
# Rien n'est écrit sur disque ni passé en argument ; chaque valeur est masquée
# dans les journaux du run.
set -euo pipefail

extract() {
  sops -d --extract "[\"$1\"]" secrets/ansible.sops.yaml
}

AWS_ACCESS_KEY_ID="$(extract state_s3_access_key)"
AWS_SECRET_ACCESS_KEY="$(extract state_s3_secret_key)"
# init valide le bloc encryption du module, dont la clé est une variable.
TF_VAR_pangolin_config_state_passphrase="$(extract tofu_state_passphrase)"
echo "::add-mask::$AWS_ACCESS_KEY_ID"
echo "::add-mask::$AWS_SECRET_ACCESS_KEY"
echo "::add-mask::$TF_VAR_pangolin_config_state_passphrase"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_pangolin_config_state_passphrase

# Le registre peut couper une connexion : même reprise que test.yaml.
for attempt in 1 2 3; do
  tofu -chdir=tofu/pangolin_config init -input=false -lockfile=readonly -no-color && exit 0
  echo "tofu init failed (attempt $attempt), retrying in $((attempt * 10))s"
  sleep $((attempt * 10))
done
exit 1
