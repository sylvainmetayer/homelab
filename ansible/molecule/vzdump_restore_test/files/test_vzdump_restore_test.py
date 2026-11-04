"""Tests de vzdump_restore_test.py (rôle vzdump_restore_test), lancés par
verify.yml du scénario avec le python3 de l'hôte de test. Le déroulé complet
est joué par le verify contre le faux Proxmox ; ici, les garde-fous cas par
cas : ce qui protège les invités de production. pvesh et run sont remplacés,
aucune commande Proxmox n'est lancée. À la main : copier ce fichier à côté de
ansible/roles/vzdump_restore_test/files/vzdump_restore_test.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import http.client
import io
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import vzdump_restore_test as vz

MIB = 1024**2
CONFIG = {"backup_storage": "nas-backup", "restore_storage": "local-lvm", "max_age_hours": 48}
MARKED = {"description": f"{vz.MARKER} : copie jetable"}


def completed(stdout="", returncode=0, stderr=""):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


def argvs_of(run):
    return [" ".join(call.args[0]) for call in run.call_args_list]


class ParseConfTest(unittest.TestCase):
    def test_keeps_the_current_config_only(self):
        text = (
            "# description sur\n#plusieurs: lignes\narch: amd64\nhostname: newt\n\n"
            "net0: name=eth0,bridge=vmbr0\nsans-valeur\n"
            "[instantane]\nhostname: ancien\nnet1: x\n"
        )
        self.assertEqual(
            vz.parse_conf(text),
            {"arch": "amd64", "hostname": "newt", "net0": "name=eth0,bridge=vmbr0"},
        )

    def test_value_with_a_colon(self):
        self.assertEqual(vz.parse_conf("rootfs: local:vm-200-disk-0,size=8G"), {"rootfs": "local:vm-200-disk-0,size=8G"})

    def test_empty(self):
        self.assertEqual(vz.parse_conf(""), {})


class OptionTest(unittest.TestCase):
    def test_option(self):
        value = "name=eth0,bridge=vmbr0,ip=dhcp"
        self.assertEqual(vz.option(value, "bridge"), "vmbr0")
        self.assertIsNone(vz.option(value, "tag"))
        # Le nom entier, pas un préfixe.
        self.assertIsNone(vz.option("bridge2=x", "bridge"))
        self.assertEqual(vz.option("a=b=c", "a"), "b=c")


class RootfsPathTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = directory.name
        os.makedirs(os.path.join(self.root, "etc", "systemd"))

    def test_plain_path(self):
        self.assertEqual(vz.rootfs_path(self.root, "etc/hostname"), os.path.join(self.root, "etc", "hostname"))
        self.assertEqual(vz.rootfs_path(self.root, "/etc//hostname"), os.path.join(self.root, "etc", "hostname"))

    def test_refused_paths(self):
        for relative in ("", "/", "../etc/passwd", "etc/../../passwd"):
            with self.subTest(relative=relative), self.assertRaisesRegex(vz.TestFailure, "chemin refusé"):
                vz.rootfs_path(self.root, relative)

    def test_symlinked_parent_is_refused(self):
        # Un lien absolu de l'invité pointerait sur l'hôte une fois monté.
        os.symlink("/etc", os.path.join(self.root, "lien"))
        with self.assertRaisesRegex(vz.TestFailure, "n'est pas un dossier"):
            vz.rootfs_path(self.root, "lien/passwd")

    def test_missing_parent_is_refused(self):
        with self.assertRaisesRegex(vz.TestFailure, "n'est pas un dossier"):
            vz.rootfs_path(self.root, "absent/fichier")

    def test_parent_file_is_refused(self):
        with open(os.path.join(self.root, "fichier"), "w", encoding="ascii"):
            pass
        with self.assertRaisesRegex(vz.TestFailure, "n'est pas un dossier"):
            vz.rootfs_path(self.root, "fichier/x")


class Fixture(unittest.TestCase):
    """Un Run avec pvesh et run remplacés, leurs appels gardés."""

    def setUp(self):
        self.pvesh = self.patch("pvesh")
        self.pct = self.patch("run", return_value=completed())
        self.test = vz.Run(dict(CONFIG))
        self.test.node = "pve"

    def patch(self, name, **kwargs):
        patcher = mock.patch.object(vz, name, **kwargs)
        self.addCleanup(patcher.stop)
        return patcher.start()


class CheckTargetTest(Fixture):
    def test_free_target(self):
        self.pvesh.return_value = []
        self.test.check_target("LXC", 200, 990)
        self.pvesh.assert_called_once_with("/nodes/pve/storage/local-lvm/content", vmid=990)

    def test_out_of_range(self):
        for target in (899, 1000, 200):
            with self.subTest(target=target), self.assertRaisesRegex(vz.TestFailure, "hors de 900-999"):
                self.test.check_target("LXC", 200, target)
        self.pvesh.assert_not_called()

    def test_bounds_of_the_range_are_usable(self):
        self.pvesh.return_value = []
        self.test.check_target("LXC", 200, 900)
        self.test.check_target("LXC", 200, 999)

    def test_existing_guest_or_source(self):
        self.test.protected = {950}
        with self.assertRaisesRegex(vz.TestFailure, "déjà pris"):
            self.test.check_target("LXC", 200, 950)

    def test_orphan_volumes(self):
        self.pvesh.return_value = [{"volid": "local-lvm:vm-990-disk-0"}]
        with self.assertRaisesRegex(vz.TestFailure, "volumes orphelins de 990 .*vm-990-disk-0"):
            self.test.check_target("LXC", 200, 990)

    def test_source_equal_to_target(self):
        self.pvesh.return_value = []
        with self.assertRaisesRegex(vz.TestFailure, "le même id"):
            self.test.check_target("LXC", 990, 990)


class LatestBackupTest(Fixture):
    def setUp(self):
        super().setUp()
        self.test.now = 1_800_000_000
        self.pct.return_value = completed("/mnt/backup/vzdump-lxc-200.tar.zst\n")
        patcher = mock.patch.object(self.test, "check_log")
        self.addCleanup(patcher.stop)
        self.check_log = patcher.start()

    def item(self, hours_ago, vmid=200, size=100 * MIB):
        return {
            "vmid": vmid,
            "ctime": self.test.now - hours_ago * 3600,
            "size": size,
            "volid": f"nas-backup:backup/{vmid}-{hours_ago}",
        }

    def test_latest_of_this_guest(self):
        self.pvesh.return_value = [self.item(30), self.item(5), self.item(10), self.item(1, vmid=100)]
        backup = self.test.latest_backup("LXC", 200, 50)
        self.assertEqual(backup["volid"], "nas-backup:backup/200-5")
        self.assertEqual(backup["path"], "/mnt/backup/vzdump-lxc-200.tar.zst")
        self.assertIn("(5 h, 100 Mio)", backup["summary"])
        self.check_log.assert_called_once_with("LXC", 200, backup["path"])

    def test_no_backup(self):
        self.pvesh.return_value = [self.item(1, vmid=100)]
        with self.assertRaisesRegex(vz.TestFailure, "aucune sauvegarde sur nas-backup"):
            self.test.latest_backup("LXC", 200, 50)

    def test_too_old(self):
        self.pvesh.return_value = [self.item(49)]
        with self.assertRaisesRegex(vz.TestFailure, "plus vieille que 48 h"):
            self.test.latest_backup("LXC", 200, 50)
        self.check_log.assert_not_called()

    def test_at_the_age_limit(self):
        self.pvesh.return_value = [self.item(48)]
        self.test.latest_backup("LXC", 200, 50)

    def test_too_small(self):
        self.pvesh.return_value = [self.item(5, size=49 * MIB)]
        with self.assertRaisesRegex(vz.TestFailure, "sous 50 Mio"):
            self.test.latest_backup("LXC", 200, 50)

    def test_size_in_gib(self):
        self.pvesh.return_value = [self.item(5, size=3 * 1024 * MIB)]
        self.assertIn("3.0 Gio", self.test.latest_backup("VM", 200, 50)["summary"])


class CheckLogTest(Fixture):
    def setUp(self):
        super().setUp()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.dir = directory.name

    def write_log(self, name, text):
        with open(os.path.join(self.dir, name), "w", encoding="utf-8") as f:
            f.write(text)

    def test_good_log_for_every_archive_format(self):
        for archive in ("a.tar.zst", "a.vma.zst", "a.vma", "a.tar", "a.tar.gz", "a.vma.lzo"):
            with self.subTest(archive=archive):
                self.write_log("a.log", "INFO: Finished Backup of VM 200 (00:01:00)\n")
                self.test.check_log("LXC", 200, os.path.join(self.dir, archive))
        self.assertEqual(self.test.lines, [])

    def test_error_line(self):
        self.write_log("a.log", "ERROR: disque plein\nFinished Backup of VM 200\n")
        archive = os.path.join(self.dir, "a.tar.zst")
        with self.assertRaisesRegex(vz.TestFailure, "signale une erreur .a.log."):
            self.test.check_log("LXC", 200, archive)

    def test_finished_for_another_guest(self):
        self.write_log("a.log", "Finished Backup of VM 100\n")
        archive = os.path.join(self.dir, "a.tar.zst")
        with self.assertRaises(vz.TestFailure):
            self.test.check_log("LXC", 200, archive)

    def test_no_log_is_a_note_not_a_failure(self):
        self.test.check_log("LXC", 200, os.path.join(self.dir, "a.tar.zst"))
        self.assertIn("pas de journal", self.test.lines[0])

    def test_unknown_extension_never_reads_the_archive_as_its_log(self):
        self.write_log("a.bin", "ERROR: contenu binaire\n")
        self.test.check_log("LXC", 200, os.path.join(self.dir, "a.bin"))
        self.assertIn("pas de journal", self.test.lines[0])


class UnpluggedTest(Fixture):
    def test_every_interface_goes_link_down_without_its_address(self):
        conf = {
            "net1": "name=lan,bridge=vmbr1,hwaddr=AA:BB,ip=192.0.2.2/24",
            "net0": "bridge=vmbr0,hwaddr=AA:CC",
            "net10": "name=x",
            "hostname": "newt",
        }
        self.assertEqual(
            self.test.unplugged(conf),
            [
                "--net0", "name=eth0,bridge=vmbr0,link_down=1",
                "--net1", "name=lan,bridge=vmbr1,link_down=1",
                "--net10", "name=x,link_down=1",
            ],
        )

    def test_no_interface(self):
        self.assertEqual(self.test.unplugged({"hostname": "newt"}), [])


class AssertOfflineTest(Fixture):
    def check(self, **conf):
        with mock.patch.object(self.test, "guest_conf", return_value={**MARKED, **conf}):
            return self.test.assert_offline("lxc", 990)

    def test_clean_copy_is_returned(self):
        conf = self.check(onboot=0, rootfs="local-lvm:vm-990-disk-0", mp0="local-lvm:vm-990-disk-1")
        self.assertEqual(conf["onboot"], 0)

    def test_interface_left(self):
        with self.assertRaisesRegex(vz.TestFailure, r"interfaces réseau encore présentes \(net0, net1\)"):
            self.check(net0="x", net1="y")

    def test_onboot(self):
        for value in (1, "1"):
            with self.subTest(value=value), self.assertRaisesRegex(vz.TestFailure, "onboot actif"):
                self.check(onboot=value)

    def test_no_marker(self):
        for description in (None, "", "autre"):
            with self.subTest(description=description), self.assertRaisesRegex(vz.TestFailure, "marque"):
                self.check(description=description)

    def test_direct_access_to_the_host(self):
        for conf in (
            {"mp0": "/mnt/host,mp=/data"},
            {"scsi0": "/dev/sdb"},
            {"virtio1": "/dev/disk/by-id/x"},
            {"hostpci0": "01:00"},
            {"usb0": "host=1-1"},
            {"dev0": "/dev/net/tun"},
            {"args": "-foo"},
            {"lxc.mount.entry": "/x y"},
            {"lxc": [["lxc.idmap", "u 0 0 1"]]},
        ):
            with self.subTest(conf=conf), self.assertRaisesRegex(vz.TestFailure, "accès direct à l'hôte"):
                self.check(**conf)


LXC_SETTINGS = {
    "source": 200,
    "target": 990,
    "min_size_mb": 1,
    "restore_timeout": 10,
    "boot_timeout": 10,
    "expect_files": [],
    "expect_executables": [],
    "mask_units": [],
}


def restore_copy(case):
    """test_lxc du Run de ce cas, sauvegarde et archive remplacées."""
    for name, value in (
        ("check_target", None),
        ("latest_backup", {"volid": "nas-backup:b", "summary": "s"}),
        ("archive_conf", {"hostname": "newt", "unprivileged": "1", "net0": "name=eth0,bridge=vmbr0"}),
    ):
        patcher = mock.patch.object(case.test, name, return_value=value)
        case.addCleanup(patcher.stop)
        patcher.start()
    case.test.test_lxc(LXC_SETTINGS)


class RestoreTest(Fixture):
    """test_lxc jusqu'à la restauration : l'id est noté avant, la commande
    n'écrase rien et ne branche rien."""

    def test_failed_restore_stays_listed_for_the_cleanup(self):
        self.pct.side_effect = vz.TestFailure("pct restore : code 1")
        with self.assertRaises(vz.TestFailure):
            restore_copy(self)
        self.assertEqual(self.test.created, [990])

    def test_copy_with_an_interface_left_is_never_started(self):
        with mock.patch.object(self.test, "guest_conf", return_value={**MARKED, "net0": "x"}):
            with self.assertRaisesRegex(vz.TestFailure, "interfaces réseau encore présentes"):
                restore_copy(self)
        argvs = argvs_of(self.pct)
        self.assertTrue(argvs[0].startswith("pct restore 990 nas-backup:b "))
        self.assertIn("--net0 name=eth0,bridge=vmbr0,link_down=1", argvs[0])
        self.assertIn("--unique 1", argvs[0])
        self.assertIn("--onboot 0", argvs[0])
        self.assertIn(f"--description {vz.MARKER}", argvs[0])
        self.assertNotIn("--force", argvs[0])
        self.assertEqual(argvs[1], "pct set 990 --delete net0")
        self.assertFalse([argv for argv in argvs if argv.startswith("pct start")])


class BootTest(Fixture):
    """test_lxc après la restauration : ce que la copie montre une fois démarrée.
    Le verify ne joue que le cas nominal."""

    def boot(self, interfaces="lo\n", state="running\n"):
        outputs = {"/sys/class/net": interfaces, "is-system-running": state}

        def pct(argv, **_):
            return completed(next((output for key, output in outputs.items() if key in argv), ""))

        self.pct.side_effect = pct
        with mock.patch.object(self.test, "assert_offline"), mock.patch.object(self.test, "check_rootfs"):
            restore_copy(self)

    def test_running_copy_is_stopped_and_reported(self):
        self.boot()
        self.assertEqual(argvs_of(self.pct)[-1], "pct stop 990")
        self.assertIn("systemd running", self.test.lines[0])

    def test_interface_at_boot_stops_the_copy(self):
        with self.assertRaisesRegex(vz.TestFailure, r"interfaces réseau au démarrage \(eth0, lo\), arrêté"):
            self.boot(interfaces="eth0\nlo\n")
        argvs = argvs_of(self.pct)
        self.assertEqual(argvs[-1], "pct stop 990")
        self.assertFalse([argv for argv in argvs if "is-system-running" in argv])

    def test_no_lo_is_unreadable_not_offline(self):
        with self.assertRaisesRegex(vz.TestFailure, "aucune, lo absent"):
            self.boot(interfaces="")

    def test_systemd_in_another_state_fails(self):
        with self.assertRaisesRegex(vz.TestFailure, "systemd à l'état « starting »"):
            self.boot(state="starting\n")

    def test_systemd_without_a_state_fails(self):
        with self.assertRaisesRegex(vz.TestFailure, "systemd à l'état « inconnu »"):
            self.boot(state="")

    def test_rootfs_failure_never_starts_the_copy(self):
        with (
            mock.patch.object(self.test, "assert_offline"),
            mock.patch.object(self.test, "check_rootfs", side_effect=vz.TestFailure("rootfs")),
            self.assertRaisesRegex(vz.TestFailure, "rootfs"),
        ):
            restore_copy(self)
        self.assertFalse([argv for argv in argvs_of(self.pct) if argv.startswith("pct start")])


class CheckRootfsTest(Fixture):
    """check_rootfs sur un vrai dossier : son contenu vient de l'invité, et un
    lien absolu y pointerait sur l'hôte."""

    SETTINGS = {"expect_files": ["etc/newt.conf"], "expect_executables": ["usr/bin/newt"], "mask_units": ["newt.service"]}

    def setUp(self):
        super().setUp()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.rootfs = directory.name
        os.makedirs(self.path("etc/systemd/system"))
        os.makedirs(self.path("usr/bin"))
        for relative, text in (
            ("etc/hostname", "newt\n"),
            ("etc/newt.conf", ""),
            ("etc/systemd/system/newt.service", "[Unit]\n"),
            ("usr/bin/newt", ""),
        ):
            with open(self.path(relative), "w", encoding="ascii") as f:
                f.write(text)
        os.chmod(self.path("usr/bin/newt"), 0o700)
        self.pct.return_value = completed(f"mounted CT 990 in '{self.rootfs}'\n")

    def path(self, relative):
        return os.path.join(self.rootfs, relative)

    def replace_with_a_link(self, relative):
        os.unlink(self.path(relative))
        os.symlink("/etc/passwd", self.path(relative))

    def check(self, hostname="newt"):
        self.test.check_rootfs(990, hostname, self.SETTINGS)

    def test_good_rootfs_masks_the_unit_and_unmounts(self):
        self.check()
        self.assertEqual(os.readlink(self.path("etc/systemd/system/newt.service")), "/dev/null")
        self.assertEqual(os.listdir(self.path("etc/systemd/system")), ["newt.service"])
        self.assertEqual(argvs_of(self.pct), ["pct mount 990", "pct unmount 990"])

    def test_other_hostname_fails_and_still_unmounts(self):
        with self.assertRaisesRegex(vz.TestFailure, "vaut « newt », pas « autre »"):
            self.check("autre")
        self.assertEqual(argvs_of(self.pct)[-1], "pct unmount 990")

    def test_no_hostname_in_the_archive_is_not_compared(self):
        self.check("")

    def test_hostname_link_is_never_read(self):
        self.replace_with_a_link("etc/hostname")
        with self.assertRaisesRegex(vz.TestFailure, "/etc/hostname absent"):
            self.check()

    def test_missing_expected_file(self):
        os.unlink(self.path("etc/newt.conf"))
        with self.assertRaisesRegex(vz.TestFailure, "/etc/newt.conf absent"):
            self.check()

    def test_expected_file_as_a_link_is_refused(self):
        self.replace_with_a_link("etc/newt.conf")
        with self.assertRaisesRegex(vz.TestFailure, "/etc/newt.conf absent"):
            self.check()

    def test_expected_executable_without_the_bit(self):
        os.chmod(self.path("usr/bin/newt"), 0o600)
        with self.assertRaisesRegex(vz.TestFailure, "/usr/bin/newt n'est pas exécutable"):
            self.check()

    def test_mask_behind_a_link_writes_nothing_outside(self):
        outside = tempfile.TemporaryDirectory()
        self.addCleanup(outside.cleanup)
        shutil.rmtree(self.path("etc/systemd"))
        os.symlink(outside.name, self.path("etc/systemd"))
        with self.assertRaisesRegex(vz.TestFailure, "n'est pas un dossier"):
            self.check()
        self.assertEqual(os.listdir(outside.name), [])

    def test_unreadable_mount_point(self):
        self.pct.return_value = completed("autre chose\n")
        with self.assertRaisesRegex(vz.TestFailure, "point de montage introuvable"):
            self.check()


class VerifyArchiveTest(Fixture):
    def test_unknown_format_is_refused(self):
        with self.assertRaisesRegex(vz.TestFailure, "format d'archive non géré"):
            self.test.verify_archive({"path": "/x/a.vma.gz"}, 10)


class DestroyTest(Fixture):
    def guests(self, *ids):
        self.pvesh.return_value = [{"vmid": i} for i in ids]

    def conf(self, conf=MARKED):
        patcher = mock.patch.object(self.test, "guest_conf", return_value=conf)
        self.addCleanup(patcher.stop)
        patcher.start()

    def test_outside_the_range_or_protected_is_never_touched(self):
        self.test.protected = {950}
        for vmid in (100, 899, 1000, 950):
            with self.subTest(vmid=vmid), self.assertRaisesRegex(vz.TestFailure, "refus de détruire"):
                self.test.destroy(vmid)
        self.pvesh.assert_not_called()
        self.pct.assert_not_called()

    def test_gone_already(self):
        self.guests(100)
        self.test.destroy(990)
        self.pct.assert_not_called()

    def test_no_marker_is_left_in_place(self):
        self.guests(990)
        self.conf({"description": "un invité de quelqu'un"})
        with self.assertRaisesRegex(vz.TestFailure, "laissé en place"):
            self.test.destroy(990)
        self.pct.assert_not_called()

    def test_stopped_copy_is_destroyed_without_purge(self):
        self.pvesh.side_effect = [[{"vmid": 990}], []]
        self.conf()
        self.pct.side_effect = [completed(), completed("status: stopped\n"), completed()]
        self.test.destroy(990)
        self.assertEqual(
            argvs_of(self.pct),
            ["pct unmount 990", "pct status 990", "pct destroy 990 --purge 0 --destroy-unreferenced-disks 0"],
        )

    def test_running_copy_is_stopped_first(self):
        self.pvesh.side_effect = [[{"vmid": 990}], []]
        self.conf()
        self.pct.side_effect = [completed(), completed("status: running\n"), completed(), completed()]
        self.test.destroy(990)
        self.assertIn("pct stop 990", argvs_of(self.pct))

    def test_still_there_after_destroy(self):
        self.guests(990)
        self.conf()
        self.pct.return_value = completed("status: stopped\n")
        with self.assertRaisesRegex(vz.TestFailure, "toujours là"):
            self.test.destroy(990)


class CleanupAndExecuteTest(Fixture):
    def test_cleanup_failure_is_reported_and_the_list_emptied(self):
        self.test.created = [990, 991]
        with mock.patch.object(self.test, "destroy", side_effect=[None, vz.TestFailure("laissé")]) as destroy:
            self.test.cleanup()
        self.assertEqual([call.args[0] for call in destroy.call_args_list], [991, 990])
        self.assertEqual(self.test.created, [])
        self.assertEqual(self.test.failures, ["nettoyage de 990 : laissé"])

    def test_sigterm_during_cleanup_keeps_the_guest_for_the_final_cleanup(self):
        self.test.created = [990]
        with mock.patch.object(self.test, "destroy", side_effect=vz.Terminated("signal")), self.assertRaises(vz.Terminated):
            self.test.cleanup()
        self.assertEqual(self.test.created, [990])

    def execute(self, config, lxc=None, vm=None):
        self.test.config.update(config)
        self.pvesh.return_value = [{"vmid": 100}, {"vmid": 200}]
        with (
            mock.patch.object(self.test, "test_lxc", **(lxc or {})) as test_lxc,
            mock.patch.object(self.test, "test_vm", **(vm or {})) as test_vm,
        ):
            self.test.execute()
        return test_lxc, test_vm

    def test_sources_are_protected_even_when_not_listed(self):
        self.execute({"lxc": {"source": 300}})
        self.assertEqual(self.test.protected, {100, 200, 300})

    def test_lxc_failure_does_not_stop_the_vm_test(self):
        _, test_vm = self.execute(
            {"lxc": {"source": 200}, "vm": {"source": 100}},
            lxc={"side_effect": vz.TestFailure("LXC cassé")},
        )
        test_vm.assert_called_once()
        self.assertEqual(self.test.failures, ["LXC cassé"])

    def test_unexpected_error_is_a_failure_too(self):
        with redirect_stderr(io.StringIO()):
            self.execute({"lxc": {"source": 200}}, lxc={"side_effect": KeyError("volid")})
        self.assertIn("LXC : erreur inattendue : KeyError", self.test.failures[0])

    def test_copy_is_destroyed_before_the_vm_test(self):
        order = []
        self.test.created = [990]
        with mock.patch.object(self.test, "destroy", side_effect=lambda vmid: order.append("destroy")):
            self.execute(
                {"lxc": {"source": 200}, "vm": {"source": 100}},
                vm={"side_effect": lambda settings: order.append("vm")},
            )
        self.assertEqual(order, ["destroy", "vm"])

    def test_sigterm_is_not_swallowed(self):
        config = {"lxc": {"source": 200}, "vm": {"source": 100}}
        lxc = {"side_effect": vz.Terminated("x")}
        with self.assertRaises(vz.Terminated):
            self.execute(config, lxc=lxc)


class RunCommandTest(unittest.TestCase):
    """run() avec de vrais processus : sh seulement."""

    def run_quietly(self, *args, **kwargs):
        with redirect_stdout(io.StringIO()) as out:
            result = vz.run(*args, **kwargs)
        return result, out.getvalue()

    def test_output_goes_to_the_journal(self):
        result, out = self.run_quietly(["sh", "-c", "echo sortie; echo erreur >&2"])
        self.assertEqual(result.stdout, "sortie\n")
        self.assertIn("sortie", out)
        self.assertIn("erreur", out)

    def test_quiet_keeps_stdout_out_of_the_journal(self):
        result, out = self.run_quietly(["sh", "-c", "echo sortie"], quiet=True)
        self.assertEqual(result.stdout, "sortie\n")
        self.assertNotIn("sortie\n", out.split("\n", 1)[1])

    def test_failure_cites_the_last_line(self):
        with redirect_stdout(io.StringIO()), self.assertRaisesRegex(vz.TestFailure, r"code 3 \(dernière\)"):
            vz.run(["sh", "-c", "echo première >&2; echo dernière >&2; exit 3"])

    def test_check_false_returns_the_code(self):
        result, _ = self.run_quietly(["sh", "-c", "exit 3"], check=False)
        self.assertEqual(result.returncode, 3)

    def test_missing_binary(self):
        with redirect_stdout(io.StringIO()), self.assertRaises(vz.TestFailure):
            vz.run(["/nonexistent/binaire"])

    def test_timeout_stops_the_child(self):
        started = time.monotonic()
        with redirect_stdout(io.StringIO()), self.assertRaisesRegex(vz.TestFailure, "plus de 0.2 s"):
            vz.run(["sleep", "30"], timeout=0.2)
        self.assertLess(time.monotonic() - started, 20)

    def test_exception_stops_the_child_with_sigterm(self):
        # pct restore relaie SIGTERM à sa tâche détachée, qui annule et nettoie :
        # un SIGKILL d'emblée la laisserait finir seule.
        real = subprocess.Popen.communicate

        def interrupted(proc, timeout):
            if timeout == vz.STOP_GRACE:
                return real(proc, timeout=timeout)
            proc.stdout.readline()  # le trap de l'enfant est posé
            raise vz.Terminated("signal")

        with tempfile.TemporaryDirectory() as directory:
            marker = os.path.join(directory, "sigterm")
            # Boucle bornée : sans stop(), le test échoue au lieu de bloquer sur l'enfant.
            script = f"trap 'touch {marker}; exit 0' TERM; echo pret; for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 1; done"
            with (
                mock.patch.object(subprocess.Popen, "communicate", autospec=True, side_effect=interrupted),
                redirect_stdout(io.StringIO()),
                self.assertRaises(vz.Terminated),
            ):
                vz.run(["sh", "-c", script])
            self.assertTrue(os.path.exists(marker))

    def test_child_ignoring_sigterm_is_killed_after_the_grace(self):
        script = "trap '' TERM; echo pret; exec sleep 30"
        with (
            subprocess.Popen(["sh", "-c", script], stdout=subprocess.PIPE, text=True) as proc,
            mock.patch.object(vz, "STOP_GRACE", 0.2),
        ):
            proc.stdout.readline()
            vz.stop(proc)
        self.assertEqual(proc.returncode, -signal.SIGKILL)

    def test_pvesh_reads_json(self):
        with mock.patch.object(vz, "run", return_value=completed('[{"vmid": 1}]')) as run:
            self.assertEqual(vz.pvesh("/x", type="vm"), [{"vmid": 1}])
        self.assertEqual(run.call_args.args[0], ["pvesh", "get", "/x", "--output-format", "json", "--type", "vm"])

    def test_pvesh_empty_output(self):
        with mock.patch.object(vz, "run", return_value=completed("")):
            self.assertIsNone(vz.pvesh("/x"))


class NotifyTest(unittest.TestCase):
    NTFY = {"ntfy": {"topic": "t", "url": "http://ntfy.invalid"}}
    # Pas de schéma : urllib lève un ValueError qui cite l'URL entière.
    BAD_URL = "kuma.invalid/api/push/jeton-du-moniteur"

    real_urlopen = staticmethod(vz.urllib.request.urlopen)

    def notify(self, env, failures=(), lines=("ligne",), urlopen=None, config=None):
        err = io.StringIO()
        with (
            mock.patch.dict(os.environ, {vz.NTFY_TOKEN_VARIABLE: "", vz.PUSH_URL_VARIABLE: "", **env}),
            mock.patch.object(vz.urllib.request, "urlopen", **(urlopen or {})) as opened,
            redirect_stdout(io.StringIO()),
            redirect_stderr(err),
        ):
            problems = vz.notify(config or self.NTFY, list(failures), list(lines))
        return problems, opened, err.getvalue()

    def test_nothing_configured_sends_nothing(self):
        problems, opened, err = self.notify({})
        self.assertEqual(problems, 0)
        opened.assert_not_called()
        self.assertIn("vide", err)

    def test_success_is_quiet_on_ntfy(self):
        _, opened, _ = self.notify({vz.NTFY_TOKEN_VARIABLE: "jeton"})
        body = json.loads(opened.call_args.args[0].data)
        self.assertEqual((body["priority"], body["title"]), (2, "Test de restauration vzdump : OK"))

    def test_failure_is_high_on_ntfy_and_down_on_kuma(self):
        env = {vz.NTFY_TOKEN_VARIABLE: "jeton", vz.PUSH_URL_VARIABLE: "http://kuma.invalid/p"}
        _, opened, _ = self.notify(env, failures=["cassé"])
        body = json.loads(opened.call_args_list[0].args[0].data)
        self.assertEqual(body["priority"], 4)
        self.assertEqual(body["message"], "ÉCHEC : cassé\nligne")
        self.assertIn("status=down", opened.call_args_list[1].args[0])

    def test_push_message_is_truncated(self):
        _, opened, _ = self.notify({vz.PUSH_URL_VARIABLE: "http://kuma.invalid/p?a=1"}, lines=["x" * 300])
        url = opened.call_args.args[0]
        self.assertIn("p?a=1&status=up&msg=" + "x" * 250 + "&ping=", url)

    def test_malformed_url_counts_as_a_problem_and_is_not_shown(self):
        problems, _, err = self.notify(
            {vz.PUSH_URL_VARIABLE: self.BAD_URL},
            urlopen={"side_effect": self.real_urlopen},
        )
        self.assertEqual(problems, 1)
        self.assertNotIn("jeton", err)

    def test_url_with_a_space_does_not_crash_and_is_not_shown(self):
        # http.client.InvalidURL n'est ni une OSError ni un ValueError.
        problems, _, err = self.notify(
            {vz.PUSH_URL_VARIABLE: "http://kuma.invalid/api/push/jeton du moniteur"},
            urlopen={"side_effect": self.real_urlopen},
        )
        self.assertEqual(problems, 1)
        self.assertIn("InvalidURL", err)
        self.assertNotIn("jeton", err)

    def test_truncated_push_response_does_not_crash(self):
        problems, _, err = self.notify(
            {vz.PUSH_URL_VARIABLE: "http://kuma.invalid/p"},
            urlopen={"side_effect": http.client.IncompleteRead(b"")},
        )
        self.assertEqual(problems, 1)
        self.assertIn("IncompleteRead", err)

    def test_malformed_ntfy_url_does_not_crash_nor_stop_the_push(self):
        for url in ("ntfy.invalid/jeton", "http://ntfy.invalid/jeton du sujet"):
            with self.subTest(url=url):
                problems, _, err = self.notify(
                    {vz.NTFY_TOKEN_VARIABLE: "jeton", vz.PUSH_URL_VARIABLE: "kuma.invalid/p"},
                    urlopen={"side_effect": self.real_urlopen},
                    config={"ntfy": {"topic": "t", "url": url}},
                )
                self.assertEqual(problems, 2)
                self.assertNotIn("jeton", err)

    def test_incomplete_ntfy_settings_do_not_crash(self):
        for settings in ({"url": "http://ntfy.invalid"}, {"topic": "t"}, {"topic": "t", "url": None}, "chaine"):
            with self.subTest(settings=settings):
                problems, _, err = self.notify({vz.NTFY_TOKEN_VARIABLE: "jeton"}, config={"ntfy": settings})
                self.assertEqual(problems, 1)
                self.assertIn("envoi à ntfy en échec", err)

    def test_token_in_a_refused_header_is_not_shown(self):
        # http.client cite la valeur refusée de l'en-tête dans son ValueError.
        problems, _, err = self.notify(
            {vz.NTFY_TOKEN_VARIABLE: "jeton\nmultiligne"},
            urlopen={"side_effect": self.real_urlopen},
        )
        self.assertEqual(problems, 1)
        self.assertNotIn("jeton", err)

    def test_ntfy_error_cites_its_class_only(self):
        problems, _, err = self.notify(
            {vz.NTFY_TOKEN_VARIABLE: "jeton"},
            urlopen={"side_effect": OSError("http://ntfy.invalid/jeton")},
        )
        self.assertEqual(problems, 1)
        self.assertIn("OSError", err)
        self.assertNotIn("ntfy.invalid/jeton", err)


class MainTest(unittest.TestCase):
    def setUp(self):
        config = tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8")
        self.addCleanup(config.close)
        json.dump(CONFIG, config)
        config.flush()
        self.argv = ["--config", config.name]

    def main(self, execute=None, problems=0, acquire=None):
        with (
            mock.patch.object(vz, "acquire", **(acquire or {})),
            mock.patch.object(vz.signal, "signal"),
            mock.patch.object(vz.Run, "execute", **(execute or {})) as run_execute,
            mock.patch.object(vz.Run, "cleanup") as cleanup,
            mock.patch.object(vz, "notify", return_value=problems) as notify,
            redirect_stderr(io.StringIO()),
        ):
            code = vz.main(self.argv)
        return code, run_execute, cleanup, notify

    def test_clean_run(self):
        code, _, cleanup, _ = self.main()
        self.assertEqual(code, 0)
        cleanup.assert_called_once()

    def test_notification_problem_is_exit_2(self):
        self.assertEqual(self.main(problems=1)[0], 2)

    def test_terminated_is_reported_and_cleaned_up(self):
        code, _, cleanup, notify = self.main(execute={"side_effect": vz.Terminated("interrompu par le signal 15")})
        self.assertEqual(code, 1)
        cleanup.assert_called_once()
        self.assertEqual(notify.call_args.args[1], ["interrompu par le signal 15"])

    def test_vzdump_running_skips_the_test_and_reports(self):
        failure = vz.TestFailure("vzdump tourne : verrou déjà pris")
        code, run_execute, _, notify = self.main(acquire={"side_effect": failure})
        self.assertEqual(code, 1)
        run_execute.assert_not_called()
        self.assertEqual(notify.call_args.args[1], [str(failure)])

    def test_unexpected_error_is_reported(self):
        code, _, cleanup, notify = self.main(execute={"side_effect": RuntimeError("x")})
        self.assertEqual(code, 1)
        cleanup.assert_called_once()
        self.assertIn("erreur inattendue : RuntimeError: x", notify.call_args.args[1][0])

    def test_both_locks_are_held_during_the_test(self):
        events = []

        def acquire(path, _what):
            handle = mock.MagicMock()
            handle.close.side_effect = lambda: events.append("close")
            events.append(path)
            return handle

        self.main(acquire={"side_effect": acquire}, execute={"side_effect": lambda: events.append("execute")})
        self.assertEqual(events, [vz.LOCK_PATH, vz.VZDUMP_LOCK_PATH, "execute", "close", "close"])

    def test_sigterm_interrupts_the_test_but_not_its_cleanup(self):
        self.addCleanup(signal.signal, signal.SIGTERM, signal.getsignal(signal.SIGTERM))
        # Sans le gestionnaire de main(), le signal ne tue pas ce test : il échoue.
        signal.signal(signal.SIGTERM, lambda *_: None)

        def sigterm(*_):
            os.kill(os.getpid(), signal.SIGTERM)

        with (
            mock.patch.object(vz, "acquire"),
            mock.patch.object(vz.Run, "execute", side_effect=sigterm),
            mock.patch.object(vz.Run, "cleanup", side_effect=sigterm) as cleanup,
            mock.patch.object(vz, "notify", return_value=0) as notify,
        ):
            code = vz.main(self.argv)
        self.assertEqual(code, 1)
        cleanup.assert_called_once()
        self.assertIn("interrompu par le signal", notify.call_args.args[1][0])

    def test_lock_is_exclusive(self):
        with tempfile.NamedTemporaryFile() as lock:
            held = vz.acquire(lock.name, "premier")
            self.addCleanup(held.close)
            with self.assertRaisesRegex(vz.TestFailure, "second : verrou"):
                vz.acquire(lock.name, "second")


if __name__ == "__main__":
    unittest.main()
