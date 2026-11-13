# Environnements Actions du dépôt homelab : un par usage, chacun ne portant
# que les secrets de son workflow. Un job reçoit tous les secrets de son
# environnement et rien d'autre : séparer les environnements, c'est borner
# ce qu'une action compromise ou un script fautif peut lire. Tous ne sont
# lisibles que depuis main (politique de branche `main`) : une branche de
# PR, même poussée par un collaborateur ou une action compromise, n'en voit
# aucun. Aucun n'a de relecteur.
#
# Un environnement = une entrée de local.environments (nom GitHub → secrets,
# nom du secret → valeur). Les trois ressources (environnement, politique de
# branche, secrets) en sortent par for_each. Renommer une clé détruit
# l'environnement et ses secrets sur GitHub (l'API les désigne par leur nom) :
# l'ajouter, oui ; la renommer, seulement en le voulant, avec les workflows
# qui la citent.
locals {
  environments = {
    # deploy-docker-app.yaml : la clé age de la CI (tout
    # secrets/ansible.sops.yaml), la clé SSH de déploiement (ssh_key.tf) et
    # les identifiants du client OLM de la CI (pangolin_client.ci_runner de
    # tofu/pangolin_config). Sans relecteur : le déploiement au merge reste
    # automatique.
    production = {
      SOPS_AGE_KEY    = local.sops_age_key
      SSH_PRIVATE_KEY = tls_private_key.ci_deploy.private_key_openssh
      OLM_ID          = data.terraform_remote_state.pangolin_config.outputs.ci_olm_id
      OLM_SECRET      = data.terraform_remote_state.pangolin_config.outputs.ci_olm_secret
    }

    # restore-test.yaml (issue #444) : pas `production`, il ne doit lire ni
    # la clé age ni la clé de déploiement.
    #   - la clé du sous-compte Storage Box en lecture seule de tofu/pangolin
    #     (storage_box.tf), jamais celle du compte principal, qui peut tout
    #     supprimer, ni celle d'un hôte ;
    #   - user@host, le préfixe de chaque URL de dépôt que le workflow bâtit ;
    #   - la passphrase borg, la même pour tous les dépôts ;
    #   - l'URL push du moniteur `Restore test` de tofu/pangolin_config.
    restore-test = {
      RESTORE_TEST_SSH_KEY         = data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_ssh_private_key
      RESTORE_TEST_STORAGE_BOX     = "${data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_username}@${data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_server}"
      RESTORE_TEST_BORG_PASSPHRASE = data.sops_file.secrets.data["backup_passphrase"]
      RESTORE_TEST_PUSH_URL        = data.terraform_remote_state.pangolin_config.outputs.uptime_restore_test_url
    }

    # storage-box-quota.yaml :
    #   - un jeton d'API Hetzner Console du projet, permission **Read**
    #     seulement, créé à la main (Console → Security → API tokens : le
    #     provider ne sait pas en créer) et rangé dans secrets/ansible.sops.yaml
    #     sous `hcloud_readonly_token`. Jamais le HCLOUD_TOKEN de tofu/pangolin,
    #     en lecture-écriture : dans un job de CI, il pourrait supprimer la
    #     Storage Box et Pangolin ;
    #   - l'URL push du moniteur `Storage Box` de tofu/pangolin_config.
    storage-box-quota = {
      STORAGE_BOX_QUOTA_HCLOUD_TOKEN = data.sops_file.secrets.data["hcloud_readonly_token"]
      STORAGE_BOX_QUOTA_PUSH_URL     = data.terraform_remote_state.pangolin_config.outputs.uptime_storage_box_quota_url
    }

    # secrets-rotation.yaml : la seule URL push du moniteur `Rotation des
    # secrets`. Pas de clé age : les noms des clés SOPS qu'il lit sont en
    # clair.
    secrets-rotation = {
      SECRETS_ROTATION_PUSH_URL = data.terraform_remote_state.pangolin_config.outputs.uptime_secrets_rotation_url
    }

    # Le job `notify` de trivy.yaml et renovate-digest.yaml : le seul jeton
    # du producteur ntfy `github` (clé ntfy_github_token
    # de secrets/ansible.sops.yaml, écriture seule sur le topic github, rôle
    # ntfy), celui de tout ce que publie la CI, jamais le `scripts` des
    # hôtes : un jeton fuité d'ici ne peut publier que sur ce topic, et sa
    # rotation ne touche ni docker, ni pi, ni flip. renovate-digest.yaml lit
    # l'API GitHub avec le GITHUB_TOKEN du job.
    ntfy-github = {
      NTFY_GITHUB_TOKEN = data.sops_file.secrets.data["ntfy_github_token"]
    }

    # plan-pangolin-config.yaml (ADR 0035), plan de dérive nocturne de
    # tofu/pangolin_config, jamais d'apply : pas de clé age, les valeurs sont
    # posées ici une à une.
    #   - le client OLM `ci-plan` (pangolin_client.ci_plan), pas `ci_runner` du
    #     déploiement : son tunnel est lié à vpn-flip, qui change la route ;
    #   - le compte S3 du state en lecture seule et la passphrase dédiée du
    #     state, de secrets/ansible.sops.yaml (le plan tourne avec -lock=false) ;
    #   - les variables du module, un seul JSON (var.drift_plan_vars, tirées de
    #     secrets/secrets.sops.yaml par mise.toml) : les jetons Pangolin
    #     (organisation et root), Uptime Kuma, Pocket ID, Telegram, ntfy et
    #     Anthropic du module, en lecture-écriture (à remplacer par des jetons à
    #     droits limités quand ils existent : suite de l'ADR) ;
    #   - le jeton ntfy du producteur `github`, comme `ntfy-github`, et l'URL
    #     push du moniteur « Plan nocturne pangolin_config ».
    tofu-drift = {
      DRIFT_PLAN_OLM_ID              = data.terraform_remote_state.pangolin_config.outputs.ci_plan_olm_id
      DRIFT_PLAN_OLM_SECRET          = data.terraform_remote_state.pangolin_config.outputs.ci_plan_olm_secret
      DRIFT_PLAN_STATE_S3_ACCESS_KEY = data.sops_file.secrets.data["state_s3_access_key"]
      DRIFT_PLAN_STATE_S3_SECRET_KEY = data.sops_file.secrets.data["state_s3_secret_key"]
      DRIFT_PLAN_STATE_PASSPHRASE    = data.sops_file.secrets.data["tofu_state_passphrase"]
      DRIFT_PLAN_TF_VARS             = jsonencode(var.drift_plan_vars)
      DRIFT_PLAN_NTFY_TOKEN          = data.sops_file.secrets.data["ntfy_github_token"]
      DRIFT_PLAN_PUSH_URL            = data.terraform_remote_state.pangolin_config.outputs.uptime_plan_nocturne_url
    }
  }

  # "<environnement>/<secret>" → environnement, nom et valeur.
  environment_secrets = merge([
    for env, secrets in local.environments : {
      for name, value in secrets : "${env}/${name}" => {
        environment = env
        name        = name
        value       = value
      }
    }
  ]...)
}

resource "github_repository_environment" "this" {
  for_each = local.environments

  repository  = var.github_repository
  environment = each.key

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main" {
  for_each = local.environments

  repository     = var.github_repository
  environment    = github_repository_environment.this[each.key].environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "this" {
  for_each = local.environment_secrets

  repository  = var.github_repository
  environment = github_repository_environment.this[each.value.environment].environment
  secret_name = each.value.name
  value       = each.value.value
}

# L'état de tofu/pangolin est chiffré : encryption.tf le déchiffre pour
# cette source (remote_state_data_sources). Sorties du sous-compte en lecture
# seule du test de restauration (storage_box.tf).
data "terraform_remote_state" "pangolin" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net"
    }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "homelab/pangolin.tfstate"
    region                      = "eu-west-par"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}

# État de tofu/pangolin_config (même backend S3, autre clé) : identifiants du
# client OLM de la CI et URL push des moniteurs, plutôt que de dupliquer ici
# le provider pangolin.
data "terraform_remote_state" "pangolin_config" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net"
    }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "homelab/pangolin_config.tfstate"
    region                      = "eu-west-par"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}
