#!/usr/bin/env python3
"""Select the Molecule scenarios and OpenTofu modules a change has to run
(Tests workflow, .github/workflows/test.yaml).

Usage:
  select_tests.py --all            every scenario and every tested module
  select_tests.py < changed.txt    only what the changed files (one per line) reach

Prints {"scenarios": [...], "modules": [...]} on stdout; why each suite was
selected goes to stderr as ::notice:: lines.

What a suite depends on is read from the tree, not listed by hand:
- a scenario: its own directory, the roles it applies (roles:, role:,
  include_role/import_role in any of its files, followed through each role's
  meta dependencies and include_role/import_role, transitively), the files it
  reaches with a relative path (`../../host_vars/pi/...`, `../security/...`,
  `playbook_dir ~ '/../../flip.yml'`), a host_vars path counting for the whole
  host directory and another scenario's path for that whole scenario;
- a module: its own directory and every path its .tf and tests read through
  `${path.module}`/`${path.root}` (file(), fileset(), templatefile()), an
  interpolation standing for one path segment.
A file nothing classifies selects everything: a missed test costs more than a
full run. The weekly full run (schedule) catches what this misses.
"""
import functools
import json
import posixpath
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]

# Changed, they can change any suite's result.
EVERYTHING = [
    ".github/workflows/test.yaml",
    ".github/scripts/select_tests.py",
]
# Every Molecule scenario runs them, or the environment they run in.
ALL_SCENARIOS = [
    "ansible/molecule/_shared/**",
    ".config/molecule/**",
    "ansible/group_vars/**",
    "ansible/requirements.yml",
    "pyproject.toml",
    "uv.lock",
]
# The OpenTofu version of the tofu jobs is read from mise.toml.
ALL_MODULES = ["mise.toml"]

# A playbook is not run by Molecule: each converge.yml reproduces it for one
# host, with that host's host_vars. A change to the playbook reruns the
# scenarios loading those host_vars. A playbook with no host of its own (None)
# reruns the scenarios applying one of its roles (00-setup.yaml:
# ssh_login_notify; backup.yaml, pc-nas.yml and test.yaml apply none). A
# playbook missing here reruns everything.
PLAYBOOK_HOSTS = {
    "ansible/docker.yml": "docker",
    "ansible/pi.yml": "pi",
    "ansible/flip.yml": "flip",
    "ansible/pangolin.yaml": "pangolin",
    "ansible/nas.yml": "nas",
    "ansible/lxc.yml": "newt-lxc",
    "ansible/pve.yml": "pve",
    "ansible/00-setup.yaml": None,
    "ansible/backup.yaml": None,
    "ansible/pc-nas.yml": None,
    "ansible/test.yaml": None,
}

# Read by no scenario as a whole (Molecule loads neither ansible.cfg, nor the
# inventory, nor the real secrets): only the suites that reach them by path.
PATH_ONLY = [
    "ansible/ansible.cfg",
    "ansible/inventory/**",
    "ansible/known_hosts",
    "ansible/secrets.sops.yaml",
    "ansible/tasks/**",
    "keys/**",
]

# No test reads them, unless a suite reaches one by path.
NO_TEST = [
    "docs/**",
    "**/*.md",
    ".github/**",
    ".claude/**",
    ".vscode/**",
    "compose/**",
    ".gitignore",
    ".gitleaks.toml",
    ".hadolint.yaml",
    ".sops.yaml",
    ".sopsrc",
    "renovate.json",
    "secrets.sops.yaml",
    "secrets-rotation.yaml",
]

ROLE_INCLUDE_KEYS = {
    "include_role", "import_role",
    "ansible.builtin.include_role", "ansible.builtin.import_role",
}
# A relative path written in a scenario: ../../host_vars/pi/variables.yaml.
RELATIVE_PATH_RE = re.compile(r"(?:\.\./)+[A-Za-z0-9_./-]+")
# fileset("${path.module}/..", "*/backend.tf"): the base and its pattern.
FILESET_RE = re.compile(r'fileset\(\s*"(\$\{path\.(?:module|root)\}[^"]*)"\s*,\s*"([^"]*)"\s*\)')
# "${path.module}/../../ansible/${playbook}" anywhere else (file(), templatefile()...).
MODULE_PATH_RE = re.compile(r'"(\$\{path\.(?:module|root)\}[^"]*)"')
LOCAL_SOURCE_RE = re.compile(r'source\s*=\s*"(\.\.?/[^"]+)"')
INTERPOLATION_RE = re.compile(r"\$\{[^}]*\}")


@functools.lru_cache(maxsize=None)
def glob_regex(pattern):
    """`**` crosses directories, `*` stays within one path segment."""
    out = []
    i = 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def matches(path, patterns):
    return any(glob_regex(p).match(path) for p in patterns)


class _Loader(yaml.SafeLoader):
    """safe_load that tolerates the Ansible tags (!unsafe, !vault)."""


_Loader.add_multi_constructor("!", lambda loader, suffix, node: None)


def yaml_documents(path):
    try:
        return list(yaml.load_all(path.read_text(), Loader=_Loader))
    except (yaml.YAMLError, UnicodeDecodeError):
        return [None]


def role_names(node, found):
    """Roles a YAML document applies or includes."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key in ROLE_INCLUDE_KEYS:
                if isinstance(value, dict) and isinstance(value.get("name"), str):
                    found.add(value["name"])
                elif isinstance(value, str):
                    found.update(re.findall(r"(?:^|\s)name=(\S+)", value))
            elif key == "role" and isinstance(value, str):
                found.add(value)
            elif key in ("roles", "dependencies") and isinstance(value, list):
                found.update(v for v in value if isinstance(v, str))
                # `- name: x` is accepted as well as `- role: x`.
                found.update(
                    v["name"] for v in value
                    if isinstance(v, dict) and "role" not in v and isinstance(v.get("name"), str)
                )
            role_names(value, found)
    elif isinstance(node, list):
        for item in node:
            role_names(item, found)
    return found


def yaml_files(directory):
    return sorted(p for p in directory.rglob("*") if p.is_file() and p.suffix in (".yml", ".yaml"))


class Tree:
    def __init__(self, root=ROOT):
        self.root = root
        molecule = root / "ansible" / "molecule"
        self.scenarios = sorted(p.parent.name for p in molecule.glob("*/molecule.yml"))
        self.modules = sorted(
            p.parent.relative_to(root).as_posix()
            for p in root.glob("tofu/*/tests") if p.is_dir() and not (p / ".disabled").exists()
        )
        self.roles = {p.name for p in (root / "ansible" / "roles").iterdir() if p.is_dir()} \
            if (root / "ansible" / "roles").is_dir() else set()
        self.role_uses = {role: self._role_refs(root / "ansible" / "roles" / role) - {role} for role in self.roles}
        direct = {s: self._scenario_deps(s) for s in self.scenarios}
        self.scenario_roles = {}
        self.scenario_patterns = {s: self._close_scenario(s, direct) for s in self.scenarios}
        self.module_patterns = {m: self._module_patterns(m) for m in self.modules}

    # Roles missing from the tree are kept, never filtered against
    # self.roles: a change deleting a role that something still applies must
    # select what applies it (its changed paths are ansible/roles/<role>/...).
    def _role_refs(self, directory):
        found = set()
        for path in yaml_files(directory):
            for doc in yaml_documents(path):
                role_names(doc, found)
        return found

    def role_closure(self, roles):
        seen = set()
        pending = list(roles)
        while pending:
            role = pending.pop()
            if role in seen:
                continue
            seen.add(role)
            pending.extend(self.role_uses.get(role, ()))
        return seen

    def _scenario_deps(self, scenario):
        """(patterns, roles, other scenarios) a scenario reaches directly."""
        directory = self.root / "ansible" / "molecule" / scenario
        patterns = {f"ansible/molecule/{scenario}/**"}
        roles = {scenario}
        others = set()
        for path in sorted(p for p in directory.rglob("*") if p.is_file()):
            if path.suffix in (".yml", ".yaml"):
                for doc in yaml_documents(path):
                    role_names(doc, roles)
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            for ref in RELATIVE_PATH_RE.findall(text):
                # Relative to the file (include_tasks) or to the scenario
                # (playbook_dir, vars_files, molecule.yml's playbooks).
                for base in {path.parent, directory}:
                    rel = posixpath.normpath(posixpath.join(base.relative_to(self.root).as_posix(), ref.rstrip("/.")))
                    if rel.startswith("../"):
                        continue
                    parts = rel.split("/")
                    if parts[:2] == ["ansible", "molecule"] and len(parts) > 2 and parts[2] in self.scenarios:
                        if parts[2] != scenario:
                            others.add(parts[2])
                    elif parts[:2] == ["ansible", "host_vars"] and len(parts) > 2:
                        patterns.add(f"ansible/host_vars/{parts[2]}/**")
                    elif parts[:2] == ["ansible", "roles"] and len(parts) > 2:
                        roles.add(parts[2])
                    elif (self.root / rel).is_dir():
                        patterns.add(f"{rel}/**")
                    else:
                        # A file, or a path this very change deletes: the
                        # suite still reading it must run (and fail).
                        patterns.update({rel, f"{rel}/**"})
        return patterns, roles, others

    def _close_scenario(self, scenario, direct):
        patterns, roles, seen = set(), set(), set()
        pending = [scenario]
        while pending:
            current = pending.pop()
            if current in seen:
                continue
            seen.add(current)
            p, r, others = direct[current]
            patterns |= p
            roles |= r
            pending.extend(others)
        self.scenario_roles[scenario] = roles
        patterns |= {f"ansible/roles/{role}/**" for role in self.role_closure(roles)}
        return patterns

    def _module_patterns(self, module):
        directory = self.root / module
        patterns = {f"{module}/**"}
        for path in sorted(directory.rglob("*")):
            if ".terraform" in path.parts or path.suffix not in (".tf", ".hcl") or not path.is_file():
                continue
            text = path.read_text()
            filesets = list(FILESET_RE.finditer(text))
            refs = [f"{m.group(1)}/{m.group(2)}" for m in filesets]
            spans = [m.span(1) for m in filesets]
            refs += [
                m.group(1) for m in MODULE_PATH_RE.finditer(text)
                if not any(start <= m.start(1) < end for start, end in spans)
            ]
            for ref in refs:
                ref = INTERPOLATION_RE.sub("*", ref.replace("${path.module}", module).replace("${path.root}", module))
                patterns.add(self._normalised(ref))
            for ref in LOCAL_SOURCE_RE.findall(text):
                rel = posixpath.normpath(posixpath.join(path.parent.relative_to(self.root).as_posix(), ref))
                patterns.add(f"{rel}/**")
        patterns |= self._dynamic_module_reads(module)
        # A bare "*" is a whole path built from data (`${pin.compose}`), not
        # one segment: _dynamic_module_reads reads it from that data instead.
        return {p for p in patterns if not p.startswith("../") and p != "*"}

    def _normalised(self, ref):
        rel = posixpath.normpath(ref)
        if "*" not in rel and (self.root / rel).is_dir():
            return f"{rel}/**"
        return rel

    def playbook_scenarios(self, playbook, host):
        if host is not None:
            host_vars = f"ansible/host_vars/{host}/**"
            return [s for s, p in self.scenario_patterns.items() if host_vars in p]
        path = self.root / playbook
        roles = set()
        if path.is_file():
            for doc in yaml_documents(path):
                role_names(doc, roles)
        return [s for s, r in self.scenario_roles.items() if r & roles]

    def _dynamic_module_reads(self, module):
        """Paths a test builds from data: pangolin_config's
        path_bypasses_follow_their_image reads each compose listed in
        path_bypass_images.json (`${pin.compose}`, a whole path, not a segment)."""
        if module != "tofu/pangolin_config":
            return set()
        pins = self.root / module / "path_bypass_images.json"
        if not pins.is_file():
            return set()
        return {pin["compose"] for pin in json.loads(pins.read_text()).values() if "compose" in pin}


def select(changed, tree):
    """Return (scenarios, modules, reasons)."""
    scenarios, modules, reasons = set(), set(), []
    every_scenario, every_module = set(tree.scenarios), set(tree.modules)

    def pick(kind, names, path):
        target = scenarios if kind == "scenario" else modules
        new = set(names) - target
        target.update(new)
        if new:
            reasons.append(f"{path} -> {kind}s {', '.join(sorted(new))}")

    for path in changed:
        if matches(path, EVERYTHING):
            reasons.append(f"{path} -> everything")
            return every_scenario, every_module, reasons

        docs = path.startswith("docs/") or path.endswith(".md")
        classified = False
        if matches(path, ALL_SCENARIOS):
            pick("scenario", every_scenario, path)
            classified = True
        if matches(path, ALL_MODULES):
            pick("module", every_module, path)
            classified = True

        # A README under a role or a module is still documentation: only an
        # explicit path (a test reading that very file) selects a suite for it.
        def reached(patterns):
            if docs:
                patterns = [p for p in patterns if not p.endswith("/**")]
            return matches(path, patterns)

        hit_scenarios = [s for s, p in tree.scenario_patterns.items() if reached(p)]
        hit_modules = [m for m, p in tree.module_patterns.items() if reached(p)]
        pick("scenario", hit_scenarios, path)
        pick("module", hit_modules, path)
        classified = classified or bool(hit_scenarios or hit_modules)

        if path in PLAYBOOK_HOSTS:
            pick("scenario", tree.playbook_scenarios(path, PLAYBOOK_HOSTS[path]), path)
            classified = True
        elif re.fullmatch(r"ansible/[^/]+\.ya?ml", path) and not matches(path, PATH_ONLY + ALL_SCENARIOS):
            reasons.append(f"{path} -> everything (playbook missing from PLAYBOOK_HOSTS)")
            return every_scenario, every_module, reasons

        # Their own scenario or module, when there is one, was matched above;
        # a role, scenario, host_vars or module with no test selects nothing.
        if re.match(r"(ansible/(roles|molecule|host_vars)|tofu)/[^/]+/", path):
            classified = True
        if classified or docs or matches(path, PATH_ONLY + NO_TEST):
            continue
        reasons.append(f"{path} -> everything (not classified)")
        return every_scenario, every_module, reasons
    return scenarios, modules, reasons


def main(argv=None, stdin=sys.stdin):
    argv = sys.argv[1:] if argv is None else argv
    tree = Tree()
    if argv == ["--all"]:
        scenarios, modules, reasons = set(tree.scenarios), set(tree.modules), ["--all -> everything"]
    elif not argv:
        changed = [line.strip() for line in stdin if line.strip()]
        scenarios, modules, reasons = select(changed, tree)
    else:
        sys.exit("usage: select_tests.py [--all] < changed-files.txt")
    for reason in reasons:
        print(f"::notice::{reason}", file=sys.stderr)
    print(json.dumps({"scenarios": sorted(scenarios), "modules": sorted(modules)}))


if __name__ == "__main__":
    main()
