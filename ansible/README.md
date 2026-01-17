#!/usr/bin/env bash

```shell
./setup.sh
pipenv shell
ansible-playbook 00-setup.yaml
sops exec-env secrets.sops.yaml 'ansible-playbook 01-services.yaml --extra-vars "ansible_become_pass=$password"'

```

# Raspberry

Flash image with Raspberry Image Manager, configure user in settings. Open port 80/443 in router.

SSH access is only accessible on local network.

```shell
pipenv shell
ansible-playbook 00-setup.yaml
sops exec-env secrets.sops.yaml 'ansible-playbook 02-photos.yaml --extra-vars "ansible_become_pass=$password"'
```

https://rclone.org/commands/rclone_copy/

# Manual commands

```shell
sudo loginctl enable-linger $USER
```
