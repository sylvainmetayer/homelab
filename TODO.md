# Idées

Pistes non engagées. Déjà fait, donc retiré : mises à jour automatiques
(rôle `security`), healthchecks (Uptime Kuma, `tofu/pangolin_config`),
starship (`andrewrothstein.starship`), state sur S3 OVH (`tofu/s3_state`),
durcissement (`devsec.hardening` plutôt que geerlingguy.security).

- Observabilité : Grafana + VictoriaLogs ([article](https://dominikbritz.com/posts/victoria-metrics-grafana/#victorialogs)), [tableau de bord borgmatic](https://grafana.com/grafana/dashboards/20736-borgmatic-logs/), [node_exporter](https://github.com/geerlingguy/ansible-role-node_exporter).
- Uptime Kuma : [AutoKuma](https://github.com/BigBoot/AutoKuma), [uptimekuma-migrator](https://github.com/Peppershade/uptimekuma-migrator).
- Tests d'hôte réels : [testinfra](https://testinfra.readthedocs.io/en/latest/modules.html#service).
- [Open WebUI](https://openwebui.com).
