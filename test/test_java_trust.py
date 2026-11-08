#!/usr/bin/env python3
"""Unit controls plus opt-in real keytool tests using public certificates only.

JAVA_TRUST_PUBLIC_LISTING is a keytool -list -rfc public inventory, not a keystore.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / "home.admin/config.scripts/blitz.trust.java.py"
spec = importlib.util.spec_from_file_location("java_trust", HELPER)
assert spec is not None and spec.loader is not None
fix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fix)


class UnitTests(unittest.TestCase):
    def test_parser_refuses_unparseable_and_inconsistent_counts(self):
        for text in ("", "Your keystore contains 1 entries\n", "Alias name: missing header"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                fix.inventory(text)

    def test_empty_store(self):
        self.assertEqual(fix.inventory("Your keystore contains 0 entries\n"), {})

    def test_incident_in_private_entry_aborts_without_deleting(self):
        entries = {"private": ("PrivateKeyEntry", (next(iter(fix.DENIED)),))}
        with patch.object(fix, "inventory", return_value=entries), patch.object(fix, "keytool") as tool:
            with self.assertRaisesRegex(RuntimeError, "private-key entry"):
                fix.mutate_stage(Path("unused"), True)
            self.assertEqual(tool.call_count, 1)

    def test_concurrent_inventory_change_aborts_before_deleting(self):
        entries = {"bad": ("trustedCertEntry", (next(iter(fix.DENIED)),))}
        with patch.object(fix, "inventory", side_effect=[entries, {}]), patch.object(fix, "keytool") as tool:
            with self.assertRaisesRegex(RuntimeError, "changed during"):
                fix.mutate_stage(Path("unused"), True)
            self.assertEqual(tool.call_count, 2)

    def test_unrelated_change_fails_postcondition(self):
        entries = {"good": ("trustedCertEntry", ("0" * 64,))}
        with patch.object(fix, "inventory", side_effect=[entries, {}]), patch.object(fix, "keytool"):
            with self.assertRaisesRegex(RuntimeError, "unrelated public entries"):
                fix.mutate_stage(Path("unused"), True)


@unittest.skipUnless(os.environ.get("JAVA_TRUST_PUBLIC_LISTING"), "opt-in public certificate inventory required")
class RealKeytoolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text = Path(os.environ["JAVA_TRUST_PUBLIC_LISTING"]).read_text()
        fix.inventory(text)
        cls.certs = {}
        for pem in fix.PEM.findall(text):
            digest = fix.hashlib.sha256(fix.ssl.PEM_cert_to_DER_cert(pem)).hexdigest()
            cls.certs[digest] = pem
        assert fix.DENIED <= cls.certs.keys()
        cls.good = next(pem for digest, pem in cls.certs.items() if digest not in fix.DENIED)

    def setUp(self):
        # tempfile obeys TMPDIR, keeping all probes under Hermes scratch.
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = Path(self.tmp.name) / "public-only.jks"

    def add(self, alias, pem):
        cert = Path(self.tmp.name) / "cert.pem"
        cert.write_text(pem)
        fix.keytool(self.store, "-importcert", "-noprompt", "-storetype", "JKS", "-alias", alias, "-file", str(cert))

    def listing(self):
        return fix.inventory(fix.keytool(self.store, "-list", "-rfc"))

    def test_exact_identities_preserve_custom_anchors_distrust_and_alias_collision(self):
        self.add("debian:custom-with-no-source-file.pem", self.good)
        self.add("custom import with spaces", self.good)
        # A lookalike incident alias with a different certificate must survive.
        self.add("debian:emsign_ecc_root_ca_-_g3.pem", self.good)
        for i, digest in enumerate(sorted(fix.DENIED)):
            self.add(f"renamed incident {i}", self.certs[digest])
        before = self.listing()
        with self.assertRaisesRegex(RuntimeError, "still trusts 2"):
            fix.remediate(self.store)
        fix.remediate(self.store, True)
        after = self.listing()
        self.assertEqual(after, {a: v for a, v in before.items() if not a.startswith("renamed incident")})
        # No other anchor is added, so previously distrusted/absent roots stay absent.
        self.assertEqual(len(after), 3)
        saved = self.store.read_bytes()
        fix.remediate(self.store, True)
        fix.remediate(self.store)
        self.assertEqual(saved, self.store.read_bytes())

    def test_wrong_password_refuses_without_changing_store(self):
        self.add("local", self.good)
        fix.keytool(self.store, "-storepasswd", "-new", "not-the-default")
        saved = self.store.read_bytes()
        with self.assertRaisesRegex(RuntimeError, "keytool failed"):
            fix.remediate(self.store, True)
        self.assertEqual(saved, self.store.read_bytes())

    def test_parse_rejects_duplicate_alias_and_missing_entry_type(self):
        self.add("local", self.good)
        text = fix.keytool(self.store, "-list", "-rfc")
        for malformed in (text.replace("Entry type: trustedCertEntry", "Entry type: SecretKeyEntry"),
                          text.replace("Entry type: trustedCertEntry", "no type"),
                          text + "\nAlias name: local\nEntry type: trustedCertEntry\n" + self.good):
            with self.subTest(), self.assertRaises(RuntimeError):
                fix.inventory(malformed)


if __name__ == "__main__":
    unittest.main()
