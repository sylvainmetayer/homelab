# OpenTofu: backends and state encryption

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Per-module notes live in each `tofu/<module>/README.md`; tests in `docs/conventions/tests.md`.

- All backends are S3-compatible object storage (`homelab-tf-state-sylvain` bucket at `https://s3.eu-west-par.io.cloud.ovh.net`), not native AWS — `backend "s3" { endpoints = { s3 = ... } }`.
- The states of `tofu/pangolin`, `tofu/github`, `tofu/s3_state` and `tofu/keepass_backup` are encrypted by OpenTofu (`encryption.tf`: AES-GCM, PBKDF2 key from `var.state_encryption_passphrase`, i.e. `TF_VAR_state_encryption_passphrase` from the root `secrets/secrets.sops.yaml` that mise loads). `tofu/dns` and `tofu/pangolin_config` decrypt `tofu/pangolin`'s state for their `terraform_remote_state.pangolin` (`remote_state_data_sources`) and keep their own state in clear: Ansible reads `pangolin_config`'s on S3. `ansible/inventory/hetzner.py` runs `tofu show` in `tofu/pangolin`, so it needs the same environment. Tests pass a dummy passphrase in their `variables {}` block. There is no `unencrypted` fallback any more (all three migrated on 2026-10-23): a state in clear, or encrypted with another passphrase, is refused.
