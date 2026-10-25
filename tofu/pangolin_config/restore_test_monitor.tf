# Test de restauration des dépôts borg, le 1er et le 15 du mois
# (.github/workflows/restore-test.yaml, issue #444). Un seul moniteur pour
# tous les dépôts : le dernier job du workflow y pousse « up » si chaque
# dépôt s'est restauré, « down » sinon ; le détail par app se lit dans le run.
#
# 20 jours : deux runs sont espacés de 17 jours au plus, plus la marge d'un
# run en retard ou relancé. Pas mensuel : le provider plafonne un push à
# 24 jours. Sans push, l'alerte part aussi si GitHub a désactivé le workflow
# planifié (60 jours sans activité sur un dépôt public).
resource "uptimekuma_monitor_push" "restore_test" {
  name = "Restore test"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24 * 20

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

# Lu par tofu/github (secret RESTORE_TEST_PUSH_URL de l'environnement
# restore-test).
output "uptime_restore_test_url" {
  description = "URL push du test de restauration des dépôts borg"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.restore_test.push_token}"
  sensitive   = true
}
