#!/usr/bin/env python3
"""Exercise extracted upgrade argv with real, isolated, offline Linux APT.

Never source the provisioning scripts. No package downloads/installations occur.
The deliberately synthetic metadata represents an ABI transition, not a released
Raspberry Pi kernel or evidence that any particular vulnerability is patched.
"""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test/fixtures/kernel-upgrade"
SOURCES = (
    ("build_sdcard.sh", 0),
    ("home.admin/config.scripts/blitz.release.sh", 0),
    ("home.admin/config.scripts/blitz.release.sh", 1),
    ("home.admin/_bootstrap.sh", 0),
)
META = "linux-image-rpi-test"
NEW = "linux-image-test-new"


def upgrade_argv(target):
    source, index = target
    text = (ROOT / source).read_text().replace("\\\n", " ")
    commands = []
    for line in text.splitlines():
        if not re.match(r"^\s*(?:sudo\s+)?apt-get\s+upgrade\b", line):
            continue
        args = shlex.split(line, comments=True)
        if args[:1] == ["sudo"]:
            args = args[1:]
        if args[:2] == ["apt-get", "upgrade"]:
            commands.append(args)
    expected = 2 if source.endswith("blitz.release.sh") else 1
    if len(commands) != expected:
        raise AssertionError(f"Expected {expected} system upgrades in {source}: {commands}")
    return commands[index]


class KernelUpgradeSolver(unittest.TestCase):
    def solve(self, argv, *, conflict=False, held=False):
        with tempfile.TemporaryDirectory(prefix="raspiblitz-apt-") as directory:
            root = Path(directory)
            for name in ("lists/partial", "cache/archives/partial", "repo", "etc/empty"):
                (root / name).mkdir(parents=True)
            status = (FIXTURES / "status").read_text()
            if held:
                status = status.replace("Status: install ok installed", "Status: hold ok installed", 1)
            (root / "status").write_text(status)
            packages = (FIXTURES / "Packages").read_text()
            if conflict:
                packages = packages.replace(
                    f"Package: {NEW}\n", f"Package: {NEW}\nConflicts: keep-me\n"
                )
            (root / "repo/Packages").write_text(packages)
            sources = root / "etc/sources.list"
            sources.write_text(f"deb [trusted=yes] file:{root}/repo ./\n")
            # Explicitly isolate all mutable APT state and host sources/pinning.
            options = []
            for key, value in {
                "Dir::State": root,
                "Dir::State::status": root / "status",
                "Dir::State::lists": root / "lists",
                "Dir::State::extended_states": root / "extended_states",
                "Dir::Cache": root / "cache",
                "Dir::Cache::pkgcache": "",
                "Dir::Cache::srcpkgcache": "",
                "Dir::Log": root,
                "Dir::Etc": root / "etc",
                "Dir::Etc::sourcelist": sources,
                "Dir::Etc::sourceparts": root / "etc/empty",
                "Dir::Etc::preferences": root / "etc/preferences",
                "Dir::Etc::preferencesparts": root / "etc/empty",
                "APT::Architecture": subprocess.check_output(
                    ["dpkg", "--print-architecture"], text=True
                ).strip(),
                "APT::Get::List-Cleanup": "false",
                "Acquire::Languages": "none",
                "Debug::NoLocking": "true",
            }.items():
                options.extend(["-o", f"{key}={value}"])
            config = root / "apt.conf"
            config.write_text(f'Dir::Etc::parts "{root}/etc/empty";\nDir::Etc::main "{root}/etc/missing";\n')
            env = dict(os.environ, LC_ALL="C", APT_CONFIG=str(config))
            subprocess.run(["apt-get", *options, "update"], env=env,
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            # The release command's absolute source override is replaced by the
            # fixture source through later options; production repository selection
            # is intentionally not part of this solver regression.
            result = subprocess.run([*argv, "--simulate", *options], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            self.assertEqual(result.returncode, 0, result.stdout)
            print("$", shlex.join(argv), "[isolated --simulate]", flush=True)
            print(result.stdout, flush=True)
            self.assertNotRegex(result.stdout, r"(?m)^Remv ")
            self.assertNotRegex(result.stdout, r"(?m)^Inst linux-image-test-old ")
            self.assertRegex(result.stdout, r"(?m)^Inst ordinary-update \[1\.0\] \(2\.0")
            return result.stdout

    def test_baseline_holds_new_abi(self):
        for source in SOURCES:
            with self.subTest(source=source):
                argv = [arg for arg in upgrade_argv(source) if arg != "--with-new-pkgs"]
                output = self.solve(argv)
                self.assertNotRegex(output, rf"(?m)^Inst ({META}|{NEW}) ")
                self.assertIn(META, output)

    def test_production_consumes_new_abi(self):
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.solve(upgrade_argv(source))
                self.assertRegex(output, rf"(?m)^Inst {META} \[1\.0\] \(2\.0")
                self.assertRegex(output, rf"(?m)^Inst {NEW} \(2\.0")

    def test_no_removals_for_conflicting_dependency(self):
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.solve(upgrade_argv(source), conflict=True)
                self.assertNotRegex(output, rf"(?m)^Inst ({META}|{NEW}) ")

    def test_respects_package_hold(self):
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.solve(upgrade_argv(source), held=True)
                self.assertNotRegex(output, rf"(?m)^Inst ({META}|{NEW}) ")


if __name__ == "__main__":
    unittest.main(verbosity=2)
