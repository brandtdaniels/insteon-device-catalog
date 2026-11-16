"""Tests for scripts/ingest.py, the lane that turns a device observation into a reviewed draft.

Run from the repository's root: python3 -I -m unittest discover -s tests
"""

import contextlib
import copy
import hashlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

import ingest  # noqa: E402
from ingest_lib import observation  # noqa: E402

ROOT = SCRIPTS.parent
FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures" / "ingest"
OBSERVATIONS = FIXTURES / "observations"

# Ways to write an address, a host, an account or a path that must never reach the catalog.
# Each is an invented value in the shape the scan rejects.
LEAKS = {
    "dotted address": "2F.9A.C1",
    "bare address": "2F9AC1",
    "upper-case letter address": "FACADE",
    "IPv4 address": "192.168.7.20",
    "IPv6 address": "fe80::1:2:3:4",
    "MAC address": "a4:5e:60:11:22:33",
    "URL": "https://hub.example.test/status",
    "host name": "hub.example.com",
    "email address": "someone@example.test",
    "home path": "/Users/someone/notes.txt",
    "Linux path": "/home/someone/notes",
    "Windows path": "C:\\Users\\someone",
}

PLAIN_TEXT = [
    "Fresh battery, device on the bench.",
    "Seen on a device running firmware 0x34, key 0x00001A.",
    "Tested at 12:30 with a decade of use.",
    "I/O Module 2450 (I/O Linc)",
    "It reported 2A 00.",
]


def bench(name):
    return json.loads((OBSERVATIONS / name).read_text())


def write_json(directory, name, data):
    path = pathlib.Path(directory) / name
    path.write_text(json.dumps(data, indent=2))

    return path


def run_cli(*arguments):
    """The exit status, standard output and standard error of ingest.main."""
    out, err = io.StringIO(), io.StringIO()

    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        status = ingest.main([str(argument) for argument in arguments])

    return status, out.getvalue(), err.getvalue()


class VendoredSchemaTests(unittest.TestCase):
    SWIFT_SCHEMA = ROOT.parent / "swift-insteon" / "Packages" / "InsteonCLI" / "Schemas" / "insteon-observation-1.schema.json"

    def test_the_vendored_schema_is_the_one_the_format_was_agreed_on(self):
        digest = hashlib.sha256(observation.SCHEMA_PATH.read_bytes()).hexdigest()

        self.assertEqual("4f3e2fbd346f1fcd72c30d00b9fc269535affe511fa47fe3ef5fb2a3340d34ac", digest)

    @unittest.skipUnless(SWIFT_SCHEMA.exists(), "the swift package is not next to this checkout")
    def test_the_vendored_schema_matches_the_swift_packages_copy(self):
        self.assertEqual(self.SWIFT_SCHEMA.read_bytes(), observation.SCHEMA_PATH.read_bytes())


class CheckTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = directory.name

    def errors_for(self, data, models=()):
        return observation.check(data, models)

    def test_every_bench_file_is_valid(self):
        for path in sorted(OBSERVATIONS.glob("*.json")):
            with self.subTest(path.name):
                self.assertEqual([], self.errors_for(json.loads(path.read_text()), models={"2457D2", "2450", "2635-222"}))

    def test_a_file_where_nothing_answered_is_valid(self):
        data = bench("silent-sensor.json")

        self.assertIsNone(data["device"]["firmware"])
        self.assertEqual([], self.errors_for(data))

    def test_malformed_json_is_rejected_without_quoting_the_file(self):
        path = pathlib.Path(self.directory) / "broken.json"
        path.write_text('{"format": "insteon-observation/1", 2F9AC1')

        data, errors = observation.load(path)

        self.assertIsNone(data)
        self.assertEqual(1, len(errors))
        self.assertIn("not valid JSON", errors[0])
        self.assertNotIn("2F9AC1", errors[0])

    def test_a_file_that_is_not_an_object_is_rejected(self):
        path = write_json(self.directory, "list.json", [1, 2])

        _, errors = observation.load(path)

        self.assertEqual(["the file must hold one JSON object"], errors)

    def test_a_newer_format_version_is_rejected_not_guessed_at(self):
        data = bench("io-module-2450.json")
        data["format"] = "insteon-observation/2"

        self.assertEqual(["unsupported format version; this tool reads insteon-observation/1"], self.errors_for(data))

    def test_a_file_of_another_format_is_rejected(self):
        self.assertEqual(["not an insteon-observation/1 file"], self.errors_for({"format": "something-else"}))
        self.assertEqual(["not an insteon-observation/1 file"], self.errors_for({}))

    def test_a_missing_field_is_named(self):
        data = bench("io-module-2450.json")
        del data["observedOn"]

        self.assertEqual(["$: 'observedOn' is a required property"], self.errors_for(data))

    def test_a_field_the_format_does_not_have_is_rejected_without_quoting_it(self):
        data = bench("io-module-2450.json")
        data["hubAddress"] = "value"

        errors = self.errors_for(data)

        self.assertEqual(1, len(errors))
        self.assertNotIn("hubAddress", errors[0])

    def test_a_malformed_product_key_is_rejected_without_quoting_it(self):
        data = bench("io-module-2450.json")
        data["productKey"] = "0xZZZZZZ"

        errors = self.errors_for(data)

        self.assertEqual(1, len(errors))
        self.assertIn("$.productKey", errors[0])
        self.assertNotIn("ZZZZZZ", errors[0])

    def test_identity_bytes_must_be_written_as_the_catalog_writes_them(self):
        for field, value in (("category", "7"), ("subcategory", "0x7"), ("firmware", "0x3b")):
            with self.subTest(field):
                data = bench("io-module-2450.json")
                data["device"][field] = value

                errors = self.errors_for(data)

                self.assertEqual(1, len(errors))
                self.assertIn(f"$.device.{field}", errors[0])

    def test_an_engine_must_be_one_the_protocol_has(self):
        data = bench("io-module-2450.json")
        data["device"]["engine"] = "i4"

        self.assertEqual(1, len(self.errors_for(data)))

    def test_a_date_that_does_not_exist_is_rejected(self):
        data = bench("io-module-2450.json")
        data["observedOn"] = "2026-13-45"

        errors = self.errors_for(data)

        self.assertEqual(["$.observedOn: not a calendar date"], errors)

    def test_the_free_text_has_a_length_limit(self):
        data = bench("example-invented-product.json")
        data["note"] = "a" * 281
        data["checks"][0]["detail"] = "b" * 201

        self.assertEqual(2, len(self.errors_for(data)))

    def test_a_file_cannot_hold_more_than_sixteen_checks(self):
        data = bench("io-module-2450.json")
        data["checks"] = data["checks"] * 4

        self.assertEqual(["$.checks: more than 16 checks"], self.errors_for(data))

    def test_an_address_host_or_path_in_a_note_is_rejected_without_being_quoted(self):
        for name, leak in LEAKS.items():
            with self.subTest(name):
                data = bench("example-invented-product.json")
                data["note"] = f"On the bench next to {leak} today."

                errors = self.errors_for(data)

                self.assertEqual(1, len(errors), errors)
                self.assertTrue(errors[0].startswith("$.note: contains what looks like "), errors)
                self.assertNotIn(leak, " ".join(errors))

    def test_a_leak_in_a_check_detail_is_rejected_and_the_check_is_named(self):
        data = bench("example-invented-product.json")
        data["checks"][2]["detail"] = "Answered by 2F.9A.C1."

        errors = self.errors_for(data)

        self.assertEqual(1, len(errors))
        self.assertTrue(errors[0].startswith("$.checks[2].detail: "))
        self.assertNotIn("2F.9A.C1", errors[0])

    def test_a_leak_in_the_tool_or_catalog_fields_is_rejected(self):
        data = bench("example-invented-product.json")
        data["tool"]["version"] = "10.0.0.7"
        data["catalog"]["version"] = "user@example.test"

        self.assertEqual(2, len(self.errors_for(data)))

    def test_plain_text_passes_the_scan(self):
        for text in PLAIN_TEXT:
            with self.subTest(text):
                data = bench("example-invented-product.json")
                data["note"] = text

                self.assertEqual([], self.errors_for(data))

    def test_a_serial_number_like_token_in_a_note_is_rejected(self):
        data = bench("example-invented-product.json")
        data["note"] = "Label reads SN12345678 on the back."

        errors = self.errors_for(data)

        self.assertEqual(1, len(errors))
        self.assertNotIn("SN12345678", errors[0])

    def test_the_identity_the_product_key_and_the_flag_bytes_are_not_scanned(self):
        data = bench("example-invented-product.json")

        self.assertEqual("0x00001A", data["productKey"])
        self.assertEqual([], self.errors_for(data))

    def test_a_model_name_that_holds_a_catalog_model_is_not_an_address(self):
        data = bench("dimmer-plug-2457D2.json")

        self.assertEqual(1, len(self.errors_for(data)))
        self.assertEqual([], self.errors_for(data, models={"2457D2"}))

    def test_an_address_in_the_model_name_is_rejected_even_with_models_known(self):
        data = bench("dimmer-plug-2457D2.json")
        data["device"]["model"] = "Dimmer Plug 2457D2 at 2F9AC1"

        self.assertEqual(1, len(self.errors_for(data, models={"2457D2"})))


class CheckCommandTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = directory.name

    def test_valid_files_exit_zero_and_are_named_by_content_not_by_file_name(self):
        path = pathlib.Path(self.directory) / "2F.9A.C1.json"
        path.write_text((OBSERVATIONS / "io-module-2450.json").read_text())

        status, out, _ = run_cli("check", path)

        self.assertEqual(0, status)
        self.assertIn("valid", out)
        self.assertNotIn("2F.9A.C1", out)

    def test_an_invalid_file_exits_one_and_says_what_to_fix(self):
        data = bench("example-invented-product.json")
        data["note"] = "At 192.168.7.20 today."
        path = write_json(self.directory, "bad.json", data)

        status, out, _ = run_cli("check", path)

        self.assertEqual(1, status)
        self.assertIn("$.note: contains what looks like an IP address", out)
        self.assertNotIn("192.168.7.20", out)

    def test_one_bad_file_among_several_fails_the_run_and_the_rest_are_still_checked(self):
        bad = write_json(self.directory, "bad.json", {"format": "other"})

        status, out, _ = run_cli("check", OBSERVATIONS / "io-module-2450.json", bad, OBSERVATIONS / "silent-sensor.json")

        self.assertEqual(1, status)
        self.assertEqual(2, out.count(": valid"))

    def test_a_missing_file_is_reported_not_raised(self):
        status, out, _ = run_cli("check", pathlib.Path(self.directory) / "absent.json")

        self.assertEqual(1, status)
        self.assertIn("cannot read the file", out)

    def test_the_command_runs_in_isolated_mode_as_the_workflow_runs_it(self):
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPTS / "ingest.py"), "check", str(OBSERVATIONS / "io-module-2450.json")],
            capture_output=True,
            text=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("valid", result.stdout)


if __name__ == "__main__":
    unittest.main()
