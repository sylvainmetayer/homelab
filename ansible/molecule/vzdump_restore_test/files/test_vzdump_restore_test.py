"""Tests de vzdump_restore_test.py (rôle vzdump_restore_test), lancés par
verify.yml du scénario avec le python3 de l'hôte de test. Le déroulé complet
est joué par le verify contre le faux Proxmox ; ici, les garde-fous cas par
cas : ce qui protège les invités de production. pvesh et run sont remplacés,
aucune commande Proxmox n'est lancée. À la main : copier ce fichier à côté de
ansible/roles/vzdump_restore_test/files/vzdump_restore_test.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import io
import json
import os
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
        self.run = self.patch("run", return_value=completed())
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
        self.run.return_value = completed("/mnt/backup/vzdump-lxc-200.tar.zst\n")
        self.check_log = mock.patch.object(self.test, "check_log").start()
        self.addCleanup(mock.patch.stopall)

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


class RestoreTest(Fixture):
    """test_lxc jusqu'à la restauration : l'id est noté avant, la commande
    n'écrase rien et ne branche rien."""

    SETTINGS = {
        "source": 200,
        "target": 990,
        "min_size_mb": 1,
        "restore_timeout": 10,
        "boot_timeout": 10,
        "expect_files": [],
        "expect_executables": [],
        "mask_units": [],
    }

    def restore(self):
        for name, value in (
            ("check_target", None),
            ("latest_backup", {"volid": "nas-backup:b", "summary": "s"}),
            ("archive_conf", {"hostname": "newt", "unprivileged": "1", "net0": "name=eth0,bridge=vmbr0"}),
        ):
            patcher = mock.patch.object(self.test, name, return_value=value)
            self.addCleanup(patcher.stop)
            patcher.start()
        self.test.test_lxc(self.SETTINGS)

    def test_failed_restore_stays_listed_for_the_cleanup(self):
        self.run.side_effect = vz.TestFailure("pct restore : code 1")
        with self.assertRaises(vz.TestFailure):
            self.restore()
        self.assertEqual(self.test.created, [990])

    def test_copy_with_an_interface_left_is_never_started(self):
        with mock.patch.object(self.test, "guest_conf", return_value={**MARKED, "net0": "x"}):
            with self.assertRaisesRegex(vz.TestFailure, "interfaces réseau encore présentes"):
                self.restore()
        argvs = argvs_of(self.run)
        self.assertTrue(argvs[0].startswith("pct restore 990 nas-backup:b "))
        self.assertIn("--net0 name=eth0,bridge=vmbr0,link_down=1", argvs[0])
        self.assertIn("--unique 1", argvs[0])
        self.assertIn("--onboot 0", argvs[0])
        self.assertIn(f"--description {vz.MARKER}", argvs[0])
        self.assertNotIn("--force", argvs[0])
        self.assertEqual(argvs[1], "pct set 990 --delete net0")
        self.assertFalse([argv for argv in argvs if argv.startswith("pct start")])


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
        self.run.assert_not_called()

    def test_gone_already(self):
        self.guests(100)
        self.test.destroy(990)
        self.run.assert_not_called()

    def test_no_marker_is_left_in_place(self):
        self.guests(990)
        self.conf({"description": "un invité de quelqu'un"})
        with self.assertRaisesRegex(vz.TestFailure, "laissé en place"):
            self.test.destroy(990)
        self.run.assert_not_called()

    def test_stopped_copy_is_destroyed_without_purge(self):
        self.pvesh.side_effect = [[{"vmid": 990}], []]
        self.conf()
        self.run.side_effect = [completed(), completed("status: stopped\n"), completed()]
        self.test.destroy(990)
        self.assertEqual(
            argvs_of(self.run),
            ["pct unmount 990", "pct status 990", "pct destroy 990 --purge 0 --destroy-unreferenced-disks 0"],
        )

    def test_running_copy_is_stopped_first(self):
        self.pvesh.side_effect = [[{"vmid": 990}], []]
        self.conf()
        self.run.side_effect = [completed(), completed("status: running\n"), completed(), completed()]
        self.test.destroy(990)
        self.assertIn("pct stop 990", argvs_of(self.run))

    def test_still_there_after_destroy(self):
        self.guests(990)
        self.conf()
        self.run.return_value = completed("status: stopped\n")
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

    def notify(self, env, failures=(), lines=("ligne",), urlopen=None):
        err = io.StringIO()
        with (
            mock.patch.dict(os.environ, {vz.NTFY_TOKEN_VARIABLE: "", vz.PUSH_URL_VARIABLE: "", **env}),
            mock.patch.object(vz.urllib.request, "urlopen", **(urlopen or {})) as opened,
            redirect_stdout(io.StringIO()),
            redirect_stderr(err),
        ):
            problems = vz.notify(self.NTFY, list(failures), list(lines))
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
            urlopen={"side_effect": vz.urllib.request.urlopen},
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

    def test_lock_is_exclusive(self):
        with tempfile.NamedTemporaryFile() as lock:
            held = vz.acquire(lock.name, "premier")
            self.addCleanup(held.close)
            with self.assertRaisesRegex(vz.TestFailure, "second : verrou"):
                vz.acquire(lock.name, "second")


if __name__ == "__main__":
    unittest.main()
