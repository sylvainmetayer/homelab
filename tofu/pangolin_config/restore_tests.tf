# ---------------------------------------------------------------------------
# Weekly borgmatic restore test, one push monitor per host.
#
# The `Backup <app>` monitors only say that borgmatic managed to write. The
# restore test (ansible/roles/borgmatic/files/borgmatic-restore-test.py) reads
# the latest archive of every configuration back - database dumps plus a random
# sample of files - and pushes `up` or `down` with the failing configurations.
# See issue #444.
#
# One monitor per host rather than one shared: each host runs its own test, and
# a host whose timer stopped must go DOWN on its own instead of being kept UP
# by the others. The keys are the inventory host names: each playbook reads
# `uptime_restore_test_urls.value[inventory_hostname]`, and the borgmatic role
# warns when a host has no entry.
# ---------------------------------------------------------------------------

locals {
  restore_test_hosts = toset(["docker", "flip", "pangolin", "pi"])
}

resource "uptimekuma_monitor_push" "restore_test" {
  for_each = local.restore_test_hosts

  name = "Restore test ${each.key}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  # The test runs weekly (borgmatic_restore_test_schedule, plus up to an hour
  # of RandomizedDelaySec and up to 4 h waiting for a running backup): a day of
  # margin. Uptime Kuma caps intervals at 24 days, hence weekly, not monthly.
  interval = 60 * 60 * 24 * 8

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_restore_test_urls" {
  description = "Restore test - URL de push par hôte (clé = nom d'inventaire)"
  value = {
    for host, monitor in uptimekuma_monitor_push.restore_test :
    host => "${local.uptimekuma_endpoint}/api/push/${monitor.push_token}"
  }
  sensitive = true
}
