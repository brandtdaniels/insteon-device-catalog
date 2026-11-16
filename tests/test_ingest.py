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
from ingest_lib import drafting, observation  # noqa: E402

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


def profile(model, identities, engines=None):
    """A product profile with only what drafting reads."""
    result = {"model": model, "name": f"Invented {model}", "identities": identities}

    if engines is not None:
        result["engines"] = engines

    return result


def observed(*firmware, note="Seen on a device running firmware 0x00: invented."):
    return {"status": "observed", "note": note, "firmware": list(firmware)}


def bench_catalog():
    """Profiles in the states the four bench files meet: already observed, partly observed and unmarked."""
    return {
        "2457D2": profile(
            "2457D2",
            [
                {
                    "category": "0x01",
                    "subcategory": "0x0E",
                    "productKey": "0x00004B",
                    "productKeyVerification": {"status": "inferred", "note": "Read from a shared identity."},
                    "verification": observed("0x3B"),
                }
            ],
            [
                {"engine": "i2cs", "category": "0x01", "subcategory": "0x0E", "firmware": {"only": ["0x41"]}},
                {"engine": "i2", "category": "0x01", "subcategory": "0x0E", "firmware": {"only": ["0x3B"]}, "verification": observed("0x3B")},
            ],
        ),
        "2450": profile(
            "2450",
            [{"category": "0x07", "subcategory": "0x00", "productKey": "0x00001A", "verification": observed("0x41")}],
            [{"engine": "i2cs", "category": "0x07", "subcategory": "0x00", "firmware": {"only": ["0x40", "0x41"]}}],
        ),
        "2635-222": profile(
            "2635-222",
            [{"category": "0x02", "subcategory": "0x37"}],
            [{"engine": "i2cs", "category": "0x02", "subcategory": "0x37"}],
        ),
    }


def observation_with(**device):
    """The invented example observation with the device's fields replaced."""
    data = bench("example-invented-product.json")
    data["device"].update(device)
    data["checks"] = [
        {"name": "Get Insteon Engine Version", "outcome": "answered", "detail": "x"},
        {"name": "ID Request", "outcome": "answered", "detail": "x"},
        {"name": "Product Data Request", "outcome": "answered", "detail": "x"},
    ]
    data["productKey"] = "0x00001A"
    del data["operatingFlags"]

    return data


def invented_catalog(identity=None, engines=None):
    entry = {"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A"}
    entry.update(identity or {})
    entry = {key: value for key, value in entry.items() if value is not None}
    engine_entries = [{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F"}] if engines is None else engines

    return {"9999": profile("9999", [entry], engine_entries)}


def draft(data, catalog):
    return drafting.draft_observation(data, catalog)


def codes(result):
    return [item["code"] for item in result["disagreements"]]


def changed(result):
    return [(change["entry"], change["field"], change["effect"]) for change in result["changes"]]


class BenchFileDraftTests(unittest.TestCase):
    def test_an_observation_the_catalog_already_records_changes_nothing(self):
        result = draft(bench("dimmer-plug-2457D2.json"), bench_catalog())

        self.assertEqual("no-change", result["outcome"])
        self.assertEqual([], result["changes"])
        self.assertEqual([], result["disagreements"])
        self.assertEqual(["identity 0x01/0x0E", "engine i2 0x01/0x0E"], [item["target"] for item in result["unchanged"]])
        self.assertEqual({"model": "2457D2", "identity": {"category": "0x01", "subcategory": "0x0E"}}, result["matched"])

    def test_a_silent_product_data_request_is_skipped_and_never_a_claim(self):
        result = draft(bench("dimmer-plug-2457D2.json"), bench_catalog())

        self.assertEqual([{"check": "Product Data Request", "reason": "outcome was silent; says nothing about the device"}], result["skipped"])

    def test_operating_flag_bytes_are_listed_and_compared_with_nothing(self):
        result = draft(bench("dimmer-plug-2457D2.json"), bench_catalog())

        self.assertEqual(1, len(result["reportOnly"]))
        self.assertIn("20 03 03", result["reportOnly"][0]["detail"])

    def test_an_engine_the_catalog_has_not_seen_observed_is_marked_when_the_identity_is_already_recorded(self):
        result = draft(bench("io-module-2450.json"), bench_catalog())

        self.assertEqual("drafted", result["outcome"])
        self.assertEqual([("engine", "verification", "marked observed on firmware 0x41")], changed(result))
        self.assertEqual(
            {
                "status": "observed",
                "note": "Seen on a device running firmware 0x41: Get Insteon Engine Version answered with i2CS.",
                "firmware": ["0x41"],
            },
            result["changes"][0]["after"],
        )
        self.assertIsNone(result["changes"][0]["before"])

    def test_a_product_that_reports_no_key_is_marked_and_the_note_says_so(self):
        result = draft(bench("on-off-plug-2635-222.json"), bench_catalog())

        self.assertEqual("drafted", result["outcome"])
        self.assertEqual(
            [("identity", "verification", "marked observed on firmware 0x48"), ("engine", "verification", "marked observed on firmware 0x48")],
            changed(result),
        )
        self.assertEqual(
            "Seen on a device running firmware 0x48: ID Request answered with category 0x02, subcategory 0x37 and firmware 0x48. "
            "Product Data Request answered and reported no product key.",
            result["changes"][0]["after"]["note"],
        )
        self.assertEqual([], result["disagreements"])

    def test_a_file_where_nothing_answered_writes_nothing_and_says_why(self):
        result = draft(bench("silent-sensor.json"), bench_catalog())

        self.assertEqual("no-change", result["outcome"])
        self.assertEqual([], result["changes"])
        self.assertEqual([], result["disagreements"])
        self.assertEqual(["Get Insteon Engine Version", "ID Request"], [item["check"] for item in result["skipped"]])
        self.assertEqual(1, len(result["warnings"]))
        self.assertIn("says nothing about the device", result["warnings"][0])


class IdentityDraftTests(unittest.TestCase):
    def test_an_unmarked_identity_is_marked_with_a_templated_note_and_the_firmware(self):
        result = draft(observation_with(), invented_catalog({"productKey": "0x00001A"}))

        identity = next(change for change in result["changes"] if change["entry"] == "identity" and change["field"] == "verification")

        self.assertEqual(
            {
                "status": "observed",
                "note": "Seen on a device running firmware 0x41: ID Request answered with category 0x7E, subcategory 0x7F and firmware 0x41.",
                "firmware": ["0x41"],
            },
            identity["after"],
        )
        self.assertEqual("devices/9999.json", identity["file"])
        self.assertEqual({"category": "0x7E", "subcategory": "0x7F"}, identity["selector"])

    def test_an_older_note_follows_the_new_sentence_when_a_documented_value_is_marked(self):
        catalog = invented_catalog({"verification": {"status": "inferred", "note": "Read from a similar product."}})

        result = draft(observation_with(), catalog)

        identity = next(change for change in result["changes"] if change["entry"] == "identity" and change["field"] == "verification")

        self.assertTrue(identity["after"]["note"].endswith(" Read from a similar product."))
        self.assertTrue(identity["after"]["note"].startswith("Seen on a device running firmware 0x41: "))
        self.assertEqual("observed", identity["after"]["status"])

    def test_an_identity_observed_on_this_firmware_is_not_marked_again(self):
        result = draft(observation_with(), invented_catalog({"verification": observed("0x41")}))

        self.assertEqual([], [change for change in result["changes"] if change["entry"] == "identity" and change["field"] == "verification"])
        self.assertIn("identity 0x7E/0x7F", [item["target"] for item in result["unchanged"]])

    def test_a_different_firmware_is_added_to_the_observed_record_and_the_note_is_kept(self):
        before = observed("0x3B", note="Seen on a device running firmware 0x3B: kept as written.")

        result = draft(observation_with(), invented_catalog({"verification": before}))

        identity = next(change for change in result["changes"] if change["entry"] == "identity" and change["field"] == "verification")

        self.assertEqual("added firmware 0x41 to the observed record", identity["effect"])
        self.assertEqual({"status": "observed", "note": before["note"], "firmware": ["0x3B", "0x41"]}, identity["after"])
        self.assertEqual(before, identity["before"])

    def test_a_conflicting_identity_is_never_overwritten(self):
        catalog = invented_catalog({"verification": {"status": "conflicting", "note": "Two documents disagree."}})

        result = draft(observation_with(), catalog)

        self.assertEqual([], [change for change in result["changes"] if change["entry"] == "identity" and change["field"] == "verification"])
        self.assertEqual(["conflicting-not-overwritten"], codes(result))

    def test_a_device_the_catalog_does_not_know_is_reported_and_nothing_is_written(self):
        result = draft(observation_with(category="0x70"), invented_catalog())

        self.assertEqual("needs-human", result["outcome"])
        self.assertEqual(["unknown-device"], codes(result))
        self.assertEqual([], result["changes"])
        self.assertIsNone(result["matched"])
        self.assertIn("0x70", result["disagreements"][0]["detail"])

    def test_a_firmware_no_identity_covers_is_reported_and_nothing_is_written(self):
        catalog = invented_catalog({"firmware": {"from": "0x30", "through": "0x40"}})

        result = draft(observation_with(), catalog)

        self.assertEqual(["firmware-not-covered"], codes(result))
        self.assertEqual([], result["changes"])

    def test_the_identity_is_matched_by_firmware_among_profiles_sharing_a_category(self):
        catalog = {
            "1111": profile("1111", [{"category": "0x7E", "subcategory": "0x7F", "firmware": {"from": "0x00", "through": "0x40"}}]),
            "2222": profile("2222", [{"category": "0x7E", "subcategory": "0x7F", "firmware": {"from": "0x41", "through": "0xFF"}}]),
        }

        result = draft(observation_with(), catalog)

        self.assertEqual("2222", result["matched"]["model"])

    def test_a_file_that_names_another_product_than_the_match_is_warned_about(self):
        result = draft(observation_with(model="Some Other Product 1234"), invented_catalog())

        self.assertEqual(1, len([warning for warning in result["warnings"] if "different product" in warning]))
        self.assertNotIn("Some Other Product", json.dumps(result))


class EngineDraftTests(unittest.TestCase):
    def test_an_engine_the_entry_gives_is_marked_observed(self):
        result = draft(observation_with(), invented_catalog())

        engine = next(change for change in result["changes"] if change["entry"] == "engine")

        self.assertEqual({"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F"}, engine["selector"])
        self.assertEqual("Seen on a device running firmware 0x41: Get Insteon Engine Version answered with i2CS.", engine["after"]["note"])

    def test_a_different_engine_is_a_disagreement_and_writes_nothing(self):
        result = draft(observation_with(engine="i2"), invented_catalog())

        self.assertEqual(["engine-differs"], codes(result))
        self.assertEqual([], [change for change in result["changes"] if change["entry"] == "engine"])
        self.assertIn("i2CS", result["disagreements"][0]["detail"])

    def test_a_firmware_no_engine_entry_covers_is_a_disagreement_and_writes_nothing(self):
        engines = [{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F", "firmware": {"only": ["0x42"]}}]

        result = draft(observation_with(), invented_catalog(engines=engines))

        self.assertEqual(["firmware-not-covered"], codes(result))
        self.assertEqual([], [change for change in result["changes"] if change["entry"] == "engine"])

    def test_a_profile_with_no_engine_entries_is_reported_the_same_way(self):
        result = draft(observation_with(), invented_catalog(engines=[]))

        self.assertEqual(["firmware-not-covered"], codes(result))

    def test_an_engine_already_observed_on_this_firmware_is_not_marked_again(self):
        engines = [{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F", "verification": observed("0x41")}]

        result = draft(observation_with(), invented_catalog(engines=engines))

        self.assertEqual([], [change for change in result["changes"] if change["entry"] == "engine"])

    def test_a_check_that_was_not_answered_is_not_read_even_if_the_device_fields_are_filled(self):
        data = observation_with()
        data["checks"][0]["outcome"] = "silent"

        result = draft(data, invented_catalog())

        self.assertEqual([], [change for change in result["changes"] if change["entry"] == "engine"])
        self.assertIn("Get Insteon Engine Version", [item["check"] for item in result["skipped"]])


class ProductKeyDraftTests(unittest.TestCase):
    def test_a_key_equal_to_the_catalogs_is_marked_observed_on_the_key(self):
        result = draft(observation_with(), invented_catalog({"productKey": "0x00001A"}))

        key = next(change for change in result["changes"] if change["field"] == "productKeyVerification")

        self.assertEqual("identity", key["entry"])
        self.assertEqual("Seen on a device running firmware 0x41: Product Data Request reported product key 0x00001A.", key["after"]["note"])

    def test_a_different_key_is_a_disagreement_and_writes_nothing(self):
        data = observation_with()
        data["productKey"] = "0x000050"

        result = draft(data, invented_catalog({"productKey": "0x00001A"}))

        self.assertEqual(["key-differs"], codes(result))
        self.assertEqual([], [change for change in result["changes"] if change["field"] == "productKeyVerification"])
        self.assertIn("0x000050", result["disagreements"][0]["detail"])

    def test_a_key_for_an_identity_without_one_is_reported_not_added(self):
        result = draft(observation_with(), invented_catalog({"productKey": None}))

        self.assertEqual(["key-not-in-catalog"], codes(result))

    def test_no_key_reported_against_a_catalog_key_is_a_disagreement(self):
        data = observation_with()
        data["productKey"] = "none"

        result = draft(data, invented_catalog({"productKey": "0x00001A"}))

        self.assertEqual(["key-not-reported"], codes(result))

    def test_no_key_reported_against_a_catalog_that_says_none_is_marked(self):
        data = observation_with()
        data["productKey"] = "none"

        result = draft(data, invented_catalog({"productKey": "none"}))

        key = next(change for change in result["changes"] if change["field"] == "productKeyVerification")

        self.assertEqual("Seen on a device running firmware 0x41: Product Data Request answered and reported no product key.", key["after"]["note"])

    def test_a_silent_request_leaves_the_key_alone(self):
        data = observation_with()
        del data["productKey"]
        data["checks"][2]["outcome"] = "silent"

        result = draft(data, invented_catalog({"productKey": "0x00001A"}))

        self.assertEqual([], [change for change in result["changes"] if change["field"] == "productKeyVerification"])
        self.assertEqual([], result["disagreements"])


class ContributorTextTests(unittest.TestCase):
    def test_the_contributors_note_and_details_never_reach_a_change_or_the_report(self):
        data = observation_with()
        data["note"] = "Zebra pattern marker note."
        data["checks"][1]["detail"] = "Zebra pattern marker detail."

        result = draft(data, invented_catalog({"productKey": "0x00001A"}))

        self.assertNotIn("Zebra", json.dumps(result))


class DraftAllTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = pathlib.Path(directory.name)

    def write(self, name, data):
        return write_json(self.directory, name, data)

    def test_the_same_observation_twice_changes_things_once(self):
        first = self.write("a.json", observation_with())
        second = self.write("b.json", observation_with())

        report, _ = drafting.draft_files([first, second], invented_catalog(), models={"9999"})

        self.assertEqual(["drafted", "no-change"], [item["outcome"] for item in report["observations"]])

    def test_two_firmware_versions_of_one_product_are_added_in_order(self):
        first = self.write("a.json", observation_with(firmware="0x41"))
        second = self.write("b.json", observation_with(firmware="0x42"))

        report, _ = drafting.draft_files([first, second], invented_catalog({"verification": observed("0x40")}), models={"9999"})

        self.assertEqual(["0x40", "0x41"], report["observations"][0]["changes"][0]["after"]["firmware"])
        self.assertEqual(["0x40", "0x41", "0x42"], report["observations"][1]["changes"][0]["after"]["firmware"])

    def test_a_rejected_file_is_reported_with_its_errors_and_the_others_still_draft(self):
        bad = observation_with()
        bad["note"] = "Next to 2F.9A.C1."
        paths = [self.write("bad.json", bad), self.write("ok.json", observation_with())]

        report, notes = drafting.draft_files(paths, invented_catalog(), models={"9999"})

        self.assertEqual(["rejected", "drafted"], [item["outcome"] for item in report["observations"]])
        self.assertEqual("rejected", report["outcome"])
        self.assertEqual(1, len(report["observations"][0]["errors"]))
        self.assertNotIn("2F.9A.C1", json.dumps(report))
        self.assertEqual([None, "Fresh battery, device on the bench."], notes)

    def test_observations_are_named_by_position_and_content_never_by_file_name(self):
        path = self.write("2F.9A.C1.json", observation_with())

        report, _ = drafting.draft_files([path], invented_catalog(), models={"9999"})

        self.assertRegex(report["observations"][0]["input"], r"^observation 1 \([0-9a-f]{8}\)$")
        self.assertNotIn("2F.9A.C1", json.dumps(report))

    def test_the_report_names_its_format_and_lane(self):
        report, _ = drafting.draft_files([self.write("a.json", observation_with())], invented_catalog(), models={"9999"})

        self.assertEqual("insteon-catalog-ingest-report/1", report["format"])
        self.assertEqual("observation", report["lane"])

    def test_drafting_does_not_change_the_catalog_it_is_given(self):
        catalog = invented_catalog()
        snapshot = copy.deepcopy(catalog)

        drafting.draft_files([self.write("a.json", observation_with())], catalog, models={"9999"})

        self.assertEqual(snapshot, catalog)


class ReportTextTests(unittest.TestCase):
    def test_the_markdown_lists_each_section_and_shows_the_note_only_to_the_maintainer(self):
        data = observation_with(engine="i2")
        data["note"] = "Bench note for the maintainer."
        report, notes = self.report_for(data)

        text = drafting.render_markdown(report, notes)

        self.assertIn("Bench note for the maintainer.", text)
        self.assertIn("Needs a maintainer decision", text)
        self.assertIn("engine-differs", text)
        self.assertNotIn("Bench note", json.dumps(report))

    def test_the_markdown_for_a_clean_observation_says_what_would_change(self):
        report, notes = self.report_for(observation_with())

        text = drafting.render_markdown(report, notes)

        self.assertIn("Proposed changes", text)
        self.assertIn("devices/9999.json", text)

    def report_for(self, data):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = write_json(directory.name, "a.json", data)

        return drafting.draft_files([path], invented_catalog({"productKey": "0x00001A"}), models={"9999"})


class DraftCommandTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = pathlib.Path(directory.name)

    def test_a_clean_draft_exits_zero_and_writes_the_report_and_the_markdown(self):
        report_path = self.directory / "report.json"
        markdown_path = self.directory / "report.md"

        status, _, _ = run_cli("draft", OBSERVATIONS / "silent-sensor.json", "--report", report_path, "--md", markdown_path)

        self.assertEqual(0, status)
        self.assertEqual("insteon-catalog-ingest-report/1", json.loads(report_path.read_text())["format"])
        self.assertIn("says nothing about the device", markdown_path.read_text())

    def test_without_output_paths_the_markdown_goes_to_standard_output(self):
        status, out, _ = run_cli("draft", OBSERVATIONS / "silent-sensor.json")

        self.assertEqual(0, status)
        self.assertIn("Observation report", out)

    def test_a_rejected_file_exits_one(self):
        path = write_json(self.directory, "bad.json", {"format": "other"})

        status, _, _ = run_cli("draft", path)

        self.assertEqual(1, status)

    def test_a_disagreement_exits_two(self):
        data = observation_with(category="0x70")
        path = write_json(self.directory, "unknown.json", data)

        status, out, _ = run_cli("draft", path)

        self.assertEqual(2, status)
        self.assertIn("unknown-device", out)

    def test_the_report_never_holds_the_input_file_name(self):
        path = write_json(self.directory, "2F.9A.C1.json", observation_with(category="0x70"))
        report_path = self.directory / "report.json"

        run_cli("draft", path, "--report", report_path)

        self.assertNotIn("2F.9A.C1", report_path.read_text())

    def test_every_real_bench_file_drafts_against_the_real_catalog_without_error(self):
        paths = sorted(OBSERVATIONS.glob("*.json"))
        paths.remove(OBSERVATIONS / "example-invented-product.json")

        status, _, _ = run_cli("draft", *paths)

        self.assertIn(status, (0, 2))


if __name__ == "__main__":
    unittest.main()
