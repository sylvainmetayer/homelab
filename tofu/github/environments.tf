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
#
# L'environnement relecture-chemins-publics (relecteur obligatoire, attendu
# par path-bypass-review.yaml) a été retiré le 2026-10-29 : une montée d'image
# de tofu/pangolin_config/path_bypass_images.json ne fusionne jamais seule, et
# la note que Renovate pose dans sa PR (dernière règle de renovate.json) dit
# quoi relire avant le merge à la main.
locals {
  environments = {
    # deploy-docker-app.yaml et ping.yaml : la clé age de la CI (tout
    # ansible/secrets.sops.yaml), la clé SSH de déploiement (ssh_key.tf) et
    # les identifiants du client OLM de la CI (pangolin_client.ci_runner de
    # tofu/pangolin_config). Sans relecteur : le déploiement au merge reste
    # automatique.
    production = {
      SOPS_AGE_KEY    = local.sops_age_key
      SSH_PRIVATE_KEY = tls_private_key.ci_deploy.private_key_openssh
      OLM_ID          = data.terraform_remote_state.pangolin_config.outputs.ci_olm_id
      OLM_SECRET      = data.terraform_remote_state.pangolin_config.outputs.ci_olm_secret
    }

    # restore-test.yaml et borg-check.yaml (issue #444) : pas `production`,
    # ils ne doivent lire ni la clé age ni la clé de déploiement.
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
    #     provider ne sait pas en créer) et rangé dans ansible/secrets.sops.yaml
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
    # d'ansible/secrets.sops.yaml, écriture seule sur le topic github, rôle
    # ntfy), celui de tout ce que publie la CI, jamais le `scripts` des
    # hôtes : un jeton fuité d'ici ne peut publier que sur ce topic, et sa
    # rotation ne touche ni docker, ni pi, ni flip. renovate-digest.yaml lit
    # l'API GitHub avec le GITHUB_TOKEN du job.
    ntfy-github = {
      NTFY_GITHUB_TOKEN = data.sops_file.secrets.data["ntfy_github_token"]
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

# tofu/pangolin's state is encrypted: encryption.tf decrypts it for this
# data source (remote_state_data_sources). Sorties du sous-compte en lecture
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
