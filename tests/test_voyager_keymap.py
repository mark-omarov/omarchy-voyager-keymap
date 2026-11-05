import importlib.machinery
import importlib.util
import json
import re
import sqlite3
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("voyager_keymap", str(ROOT / "voyager-keymap"))
spec = importlib.util.spec_from_loader("voyager_keymap", loader)
vk = importlib.util.module_from_spec(spec)
loader.exec_module(vk)


def slot(code, **extra):
    return {"code": code, "layer": None, "macro": None, "modifiers": None, "color": None, **extra}


def key(tap=None, **extra):
    return {"tap": tap, "hold": None, "doubleTap": None, "tapHold": None, "customLabel": None, **extra}


def oryx_layout(layers):
    return {
        "hashId": "AbCdE",
        "title": "Test",
        "geometry": "voyager",
        "revision": {"hashId": "Rev1", "createdAt": "2026-01-01 00:00:00 UTC", "layers": layers},
    }


def layer(title, keys, position):
    return {"title": title, "position": position, "color": None, "keys": keys + [key(slot("KC_NO"))] * (52 - len(keys))}


class Labels(unittest.TestCase):
    def setUp(self):
        base = layer("Main", [
            key(slot("KC_EQUAL"), hold=slot("KC_ESCAPE")),
            key(slot("KC_A"), hold=slot("KC_LEFT_SHIFT"), glowColor="#23CC1D"),
            key(slot("KC_ENTER"), hold=slot("MO", layer=1)),
            key(slot("KC_TAB", modifiers={"leftCtrl": True, "leftShift": True, "leftAlt": False}), glowColor="#000000"),
            key(slot("TG", layer=1), glowColor="javascript:alert(1)"),
            key(slot("KC_LBRC"), doubleTap=slot("KC_RBRC")),
            key(slot("RGB", color="#ff0000")),
            key(slot("KC_SCLN"), customLabel="<img src=https://example.invalid/x>"),
            key(slot("KC_F12")),
            key(slot("SOME_NEW_CODE")),
        ], 0)
        base["color"] = "#6957d2"
        sym = layer("Sym", [key(slot("KC_TRANSPARENT")), key(slot("KC_EXLM"))], 1)
        sym["color"] = "#0075FF"
        self.model = vk.normalize(oryx_layout([sym, base]), "oryx")
        self.main = self.model["layers"][0]["keys"]
        self.sym = self.model["layers"][1]["keys"]

    def test_orders_layers_by_position(self):
        self.assertEqual([l["title"] for l in self.model["layers"]], ["Main", "Sym"])

    def test_tap_and_hold(self):
        self.assertEqual((self.main[0]["tap"], self.main[0]["hold"]), ("=", "Esc"))
        self.assertEqual((self.main[1]["tap"], self.main[1]["hold"]), ("A", "Shift"))
        self.assertEqual(self.main[1]["kind"], "multi")

    def test_layer_details_read_naturally(self):
        self.assertIn(["Hold", "Sym layer"], self.main[2]["details"])
        self.assertIn(["Tap", "Toggle Sym"], self.main[4]["details"])

    def test_layer_keys_use_layer_names(self):
        self.assertEqual((self.main[2]["hold"], self.main[2]["layer"]), ("Sym", 1))
        self.assertEqual(self.main[4]["tap"], "toggle Sym")

    def test_kinds(self):
        self.assertEqual([self.main[i]["kind"] for i in (0, 2, 4, 5, 6, 8)],
                         ["multi", "layer", "layer", "tapdance", "led", "regular"])

    def test_momentary_layer_on_tap_reads_as_hold(self):
        cap = vk.normalize(oryx_layout([layer("Main", [key(slot("MO", layer=1))], 0), layer("Nav", [], 1)]), "oryx")["layers"][0]["keys"][0]
        self.assertEqual((cap["tap"], cap["hold"], cap["layer"]), ("", "Nav", 1))

    def test_tap_toggle_shows_both(self):
        cap = vk.normalize(oryx_layout([layer("Main", [key(slot("TT", layer=1))], 0), layer("Num", [], 1)]), "oryx")["layers"][0]["keys"][0]
        self.assertEqual((cap["tap"], cap["hold"]), ("Num", "toggle"))

    def test_modifier_combo(self):
        self.assertEqual(self.main[3]["tap"], "Ctrl+Shift+Tab")

    def test_double_tap_and_swatch(self):
        self.assertEqual(self.main[5]["double"], "]")
        self.assertEqual((self.main[6]["tap"], self.main[6]["swatch"]), ("LED color", "#ff0000"))

    def test_markup_stays_literal_and_is_clipped(self):
        label = self.main[7]["tap"]
        self.assertTrue(label.startswith("<img src="))
        self.assertLessEqual(len(label), vk.MAX_LABEL)

    def test_fallbacks(self):
        self.assertEqual(self.main[8]["tap"], "F12")
        self.assertEqual(self.main[9]["tap"], "Some New Code")

    def test_transparent_acts_as_base_key(self):
        self.assertTrue(self.sym[0]["through"])
        self.assertEqual((self.sym[0]["tap"], self.sym[0]["hold"]), ("=", "Esc"))
        self.assertNotIn("through", self.sym[1])

    def test_unassigned_keys_fall_through_above_the_base_layer(self):
        unassigned = {"tap": None, "hold": None}
        base = layer("Main", [key(slot("KC_A")), unassigned], 0)
        upper = layer("Upper", [unassigned, key(slot("KC_NO"))], 1)
        model = vk.normalize(oryx_layout([base, upper]), "oryx")
        self.assertTrue(model["layers"][0]["keys"][1]["none"])
        self.assertTrue(model["layers"][1]["keys"][0]["through"])
        self.assertEqual(model["layers"][1]["keys"][0]["tap"], "A")
        self.assertTrue(model["layers"][1]["keys"][1]["none"])

    def test_colors(self):
        self.assertEqual(self.model["layers"][1]["color"], "#0075FF")
        self.assertEqual(self.main[2]["layerColor"], "#0075FF")
        self.assertEqual(self.main[0]["glow"], "#6957d2")
        self.assertEqual(self.main[1]["glow"], "#23CC1D")
        self.assertIsNone(self.main[3]["glow"])
        self.assertIsNone(self.main[4]["glow"])

    def test_every_layer_has_52_keys(self):
        short = vk.normalize(oryx_layout([{"title": "Only", "position": 0, "keys": [key(slot("KC_A"))]}]), "oryx")
        self.assertEqual(len(short["layers"][0]["keys"]), 52)
        short["layers"][0]["keys"][1]["tap"] = "x"
        self.assertEqual(short["layers"][0]["keys"][2]["tap"], "")


class Macros(unittest.TestCase):
    def test_macro_on_transparent_code_is_a_macro(self):
        steps = [slot("KC_DOT"), slot("KC_DOT"), slot("KC_DOT"), slot("KC_TRANSPARENT")]
        base = layer("Main", [key(slot("KC_A"))], 0)
        sym = layer("Sym", [key(slot("KC_TRANSPARENT", macro={"keys": steps}))], 1)
        cap = vk.normalize(oryx_layout([base, sym]), "oryx")["layers"][1]["keys"][0]
        self.assertTrue(cap["macro"])
        self.assertFalse(cap["transparent"])
        self.assertEqual(cap["tap"], "...")
        self.assertEqual(cap["details"], [["Tap", "Types ..."]])

    def test_macro_with_modifiers(self):
        steps = [slot("KC_C", modifiers={"leftCtrl": True}), slot("KC_V", modifiers={"leftCtrl": True})]
        self.assertEqual(vk.macro_text({"keys": steps}, None), "Ctrl+C Ctrl+V")


class LayoutRef(unittest.TestCase):
    def test_url_forms(self):
        self.assertEqual(vk.parse_layout_ref("https://configure.zsa.io/voyager/layouts/YpBxw/latest/0"), ("YpBxw", "latest"))
        self.assertEqual(vk.parse_layout_ref("https://configure.zsa.io/voyager/layouts/YpBxw/aB3dE/2"), ("YpBxw", "aB3dE"))
        self.assertEqual(vk.parse_layout_ref("YpBxw"), ("YpBxw", "latest"))

    def test_rejects_garbage(self):
        with self.assertRaises(ValueError):
            vk.parse_layout_ref("not a layout; rm -rf ~")


class KeymappCache(unittest.TestCase):
    def test_picks_newest_voyager_revision(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "keymapp.sqlite3"
            with sqlite3.connect(db) as conn:
                conn.execute("create table revision (revisionId text, data text)")
                for rev, created, geometry in (("old", "2025", "voyager"), ("new", "2026", "voyager"), ("moon", "2027", "moonlander")):
                    layout = oryx_layout([layer("Main", [key(slot("KC_A"))], 0)])
                    layout["geometry"] = geometry
                    layout["revision"]["hashId"] = rev
                    layout["revision"]["createdAt"] = created
                    conn.execute("insert into revision values (?, ?)", (rev, json.dumps({"layout": layout})))
            model = vk.from_keymapp(db)
        self.assertEqual((model["revisionId"], model["source"]), ("new", "keymapp"))


class RawHid(unittest.TestCase):
    def test_matrix_covers_every_key_once(self):
        self.assertEqual(len(vk.MATRIX), 52)
        self.assertEqual(len(set(vk.MATRIX)), 52)

    def test_key_events_map_to_layout_positions(self):
        self.assertEqual(vk.parse_report(bytes([6, 1, 0, 0xFE])), {"key": 0, "down": True})
        self.assertEqual(vk.parse_report(bytes([7, 5, 6, 0xFE])), {"key": 31, "down": False})
        self.assertEqual(vk.parse_report(bytes([6, 6, 11, 0xFE])), {"key": 51, "down": True})

    def test_layer_and_unknown_events(self):
        self.assertEqual(vk.parse_report(bytes([5, 3, 0xFE])), {"layer": 3})
        self.assertIsNone(vk.parse_report(bytes([6, 0, 0, 0xFE])))
        self.assertIsNone(vk.parse_report(bytes([4])))
        self.assertIsNone(vk.parse_report(b""))

    def test_finds_only_the_zsa_raw_hid_interface(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, hid_id, descriptor in (
                ("hidraw1", "0003:00003297:00001977", bytes([0x05, 0x01, 0x09])),
                ("hidraw2", "0003:0000046D:0000C52B", bytes([0x06, 0x60, 0xFF])),
                ("hidraw3", "0003:00003297:00001977", bytes([0x06, 0x60, 0xFF, 0x09])),
            ):
                device = root / name / "device"
                device.mkdir(parents=True)
                (device / "uevent").write_text(f"DRIVER=hid-generic\nHID_ID={hid_id}\n")
                (device / "report_descriptor").write_bytes(descriptor)
            self.assertEqual(vk.find_raw_hid(root), Path("/dev/hidraw3"))


class Practice(unittest.TestCase):
    def test_key_spec_normalizes_and_rejects_injection(self):
        self.assertEqual(vk.key_spec("super +  shift + k"), "SUPER + SHIFT + K")
        for bad in ('K") os.execute("rm', "SUPER + K; reboot", "", "SUPER +"):
            with self.assertRaises(ValueError):
                vk.key_spec(bad)

    def test_submap_binds_exit_close_move_and_catchall(self):
        name, lua = vk.practice_submap("SUPER + SHIFT + ALT + K", "SUPER + SHIFT + K", "SUPER + SHIFT + CTRL + K")
        self.assertTrue(name.startswith("voyager-practice-"))
        self.assertIn('hl.bind("SUPER + SHIFT + ALT + K", hl.dsp.submap("reset"))', lua)
        self.assertIn('hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("omarchy-shell shell hide ' + vk.PLUGIN_ID + '"))', lua)
        self.assertIn('hl.bind("catchall", function() end)', lua)
        self.assertEqual(name, vk.practice_submap("SUPER + SHIFT + ALT + K", "SUPER + SHIFT + K", "SUPER + SHIFT + CTRL + K")[0])
        self.assertNotEqual(name, vk.practice_submap("SUPER + P", "SUPER + SHIFT + K", "SUPER + SHIFT + CTRL + K")[0])


class OverlaySafety(unittest.TestCase):
    def test_every_text_is_plain(self):
        qml = (ROOT / "Overlay.qml").read_text()
        blocks = re.findall(r"^\s*Text \{.*?^\s*\}", qml, re.M | re.S)
        self.assertGreater(len(blocks), 0)
        for block in blocks:
            self.assertIn("textFormat: Text.PlainText", block)


if __name__ == "__main__":
    unittest.main()
