# TODO

- apt unattended upgrade
- backup (restic)
  - https://tdem.in/post/restic-with-systemd/
  - https://github.com/larsks/restic-systemd-units
-  https://www.cyberciti.biz/faq/howto-adding-comments-to-ufw-firewall-rule/: Allow 443 / 80 / 22
- POC FreshRSS
- https://testinfra.readthedocs.io/en/latest/modules.html#service
- https://github.com/MeilleursAgents/terraform-provider-ansiblevault
- healthchecks
- docker logs to journalctl
- https://github.com/viczem/ansible-keepass
- https://github.com/iSchluff/terraform-provider-keepass

## Restic test

- sudo apt install restic
- restic self-update

ocyhc in 🌐 gibbs in ~
❯ export AWS_ACCESS_KEY_ID=x

ocyhc in 🌐 gibbs in ~
❯ export AWS_SECRET_ACCESS_KEY=y

ocyhc in 🌐 gibbs in ~ took 5s
❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name init
enter password for new repository:
enter password again:
created restic repository 10e623b6fe at s3:https://s3.fr-par.scw.cloud/bucket-name

Please note that knowledge of your password is required to access
the repository. Losing your password means that your data is
irrecoverably lost.

❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name --verbose backup /opt/rss/
open repository
enter password for repository:
repository 10e623b6 opened (repository version 2) successfully, password is correct
created new cache in /home/ocyhc/.cache/restic
lock repository
no parent snapshot found, will read all files
load index files
start scan on [/opt/rss/]
start backup on [/opt/rss/]
error: open /opt/rss/config/log/php/error.log: permission denied
scan finished in 2.209s: 49 files, 165.611 KiB

Files:          48 new,     0 changed,     0 unmodified
Dirs:           28 new,     0 changed,     0 unmodified
Data Blobs:     31 new
Tree Blobs:     27 new
Added to the repository: 189.625 KiB (42.673 KiB stored)

processed 48 files, 165.406 KiB in 0:03
snapshot 7090f60e saved
Warning: at least one source file could not be read

https://restic.readthedocs.io/en/stable/040_backup.html#excluding-files

database

ocyhc in 🌐 gibbs in ~ took 6s
❯ export RESTIC_PASSWORD=xyz

ocyhc in 🌐 gibbs in ~
❯ mysqldump -u rss -pxyz rss | restic -r s3:https://s3.fr-par.scw.cloud/bucket-name --verbose backup --stdin --stdin-filename $(date '+%Y-%m-%d').sql
open repository
repository 10e623b6 opened (repository version 2) successfully, password is correct
lock repository
load index files
read data from stdin
start scan on [/2022-09-01.sql]
start backup on [/2022-09-01.sql]
scan finished in 1.739s: 1 files, 0 B

Files:           1 new,     0 changed,     0 unmodified
Dirs:            0 new,     0 changed,     0 unmodified
Data Blobs:      1 new
Tree Blobs:      1 new
Added to the repository: 31.460 KiB (23.749 KiB stored)

processed 1 files, 31.152 KiB in 0:03
snapshot e953691b saved

ocyhc in 🌐 gibbs in ~ took 13s
❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name snapshots
repository 10e623b6 opened (repository version 2) successfully, password is correct
ID        Time                 Host        Tags        Paths
----------------------------------------------------------------------
7090f60e  2022-09-01 22:14:34  gibbs                   /opt/rss
f8b61389  2022-09-01 22:20:19  gibbs                   /opt/rss
e953691b  2022-09-01 22:27:18  gibbs                   /2022-09-01.sql
----------------------------------------------------------------------
3 snapshots

ocyhc in 🌐 gibbs in ~ took 8s
❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name check
using temporary cache in /tmp/restic-check-cache-4267524404
repository 10e623b6 opened (repository version 2) successfully, password is correct
created new cache in /tmp/restic-check-cache-4267524404
create exclusive lock for repository
load indexes
check all packs
check snapshots, trees and blobs
[0:00] 100.00%  3 / 3 snapshots
no errors were found

ocyhc in 🌐 gibbs in ~ took 10s
❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name snapshots
repository 10e623b6 opened (repository version 2) successfully, password is correct
ID        Time                 Host        Tags        Paths
----------------------------------------------------------------------
7090f60e  2022-09-01 22:14:34  gibbs                   /opt/rss
f8b61389  2022-09-01 22:20:19  gibbs                   /opt/rss
e953691b  2022-09-01 22:27:18  gibbs                   /2022-09-01.sql
----------------------------------------------------------------------
3 snapshots

ocyhc in 🌐 gibbs in ~ took 3s
❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name restore e953691b --target /tmp/test
repository 10e623b6 opened (repository version 2) successfully, password is correct
restoring <Snapshot e953691b of [/2022-09-01.sql] at 2022-09-01 22:27:18.255015747 +0200 CEST by ocyhc@gibbs> to /tmp/test

ocyhc in 🌐 gibbs in ~ took 7s
❯ ls !$
ls /tmp/test
2022-09-01.sql

ocyhc in 🌐 gibbs in ~
❯ head /tmp/test/2022-09-01.sql
-- MariaDB dump 10.19  Distrib 10.5.15-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: rss
-- ------------------------------------------------------
-- Server version	10.5.15-MariaDB-0+deb11u1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

ocyhc in 🌐 gibbs in ~
❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name forget --keep-last 1
repository 10e623b6 opened (repository version 2) successfully, password is correct
Applying Policy: keep 1 latest snapshots
keep 1 snapshots:
ID        Time                 Host        Tags        Reasons        Paths
------------------------------------------------------------------------------
f8b61389  2022-09-01 22:20:19  gibbs                   last snapshot  /opt/rss
------------------------------------------------------------------------------
1 snapshots

remove 1 snapshots:
ID        Time                 Host        Tags        Paths
---------------------------------------------------------------
7090f60e  2022-09-01 22:14:34  gibbs                   /opt/rss
---------------------------------------------------------------
1 snapshots

keep 1 snapshots:
ID        Time                 Host        Tags        Reasons        Paths
-------------------------------------------------------------------------------------
e953691b  2022-09-01 22:27:18  gibbs                   last snapshot  /2022-09-01.sql
-------------------------------------------------------------------------------------
1 snapshots

[0:00] 100.00%  1 / 1 files deleted

ocyhc in 🌐 gibbs in ~ took 3s
❯ restic -r s3:https://s3.fr-par.scw.cloud/bucket-name snapshots
repository 10e623b6 opened (repository version 2) successfully, password is correct
ID        Time                 Host        Tags        Paths
----------------------------------------------------------------------
f8b61389  2022-09-01 22:20:19  gibbs                   /opt/rss
e953691b  2022-09-01 22:27:18  gibbs                   /2022-09-01.sql
----------------------------------------------------------------------
2 snapshots

Gestion de garder 1 par mois / par jour / semaine / an : https://restic.readthedocs.io/en/stable/060_forget.html#removing-snapshots-according-to-a-policy
