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
            key(slot("KC_A"), hold=slot("KC_LEFT_SHIFT")),
            key(slot("KC_ENTER"), hold=slot("MO", layer=1)),
            key(slot("KC_TAB", modifiers={"leftCtrl": True, "leftShift": True, "leftAlt": False})),
            key(slot("TG", layer=1)),
            key(slot("KC_LBRC"), doubleTap=slot("KC_RBRC")),
            key(slot("RGB", color="#ff0000")),
            key(slot("KC_SCLN"), customLabel="<img src=https://example.invalid/x>"),
            key(slot("KC_F12")),
            key(slot("SOME_NEW_CODE")),
        ], 0)
        sym = layer("Sym", [key(slot("KC_TRANSPARENT")), key(slot("KC_EXLM"))], 1)
        self.model = vk.normalize(oryx_layout([sym, base]), "oryx")
        self.main = self.model["layers"][0]["keys"]
        self.sym = self.model["layers"][1]["keys"]

    def test_orders_layers_by_position(self):
        self.assertEqual([l["title"] for l in self.model["layers"]], ["Main", "Sym"])

    def test_tap_and_hold(self):
        self.assertEqual((self.main[0]["tap"], self.main[0]["hold"]), ("=", "Esc"))
        self.assertEqual((self.main[1]["tap"], self.main[1]["hold"]), ("A", "Shift"))

    def test_layer_keys_use_layer_names(self):
        self.assertEqual((self.main[2]["hold"], self.main[2]["layer"]), ("Sym", 1))
        self.assertEqual(self.main[4]["tap"], "⇄ Sym")

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

    def test_transparent_shows_base_key(self):
        self.assertTrue(self.sym[0]["transparent"])
        self.assertEqual(self.sym[0]["through"], "=")
        self.assertNotIn("through", self.sym[1])

    def test_every_layer_has_52_keys(self):
        short = vk.normalize(oryx_layout([{"title": "Only", "position": 0, "keys": [key(slot("KC_A"))]}]), "oryx")
        self.assertEqual(len(short["layers"][0]["keys"]), 52)
        short["layers"][0]["keys"][1]["tap"] = "x"
        self.assertEqual(short["layers"][0]["keys"][2]["tap"], "")


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


class Protobuf(unittest.TestCase):
    def test_decodes_status(self):
        name = b"Voyager"
        keyboard = b"\x0a" + bytes([len(name)]) + name + b"\x12\x03v42" + b"\x18\x03"
        reply = b"\x0a\x051.3.2" + b"\x12" + bytes([len(keyboard)]) + keyboard
        self.assertEqual(vk.decode_status(reply), ("Voyager", 3))

    def test_layer_zero_is_omitted_on_the_wire(self):
        keyboard = b"\x0a\x07Voyager"
        self.assertEqual(vk.decode_status(b"\x12" + bytes([len(keyboard)]) + keyboard), ("Voyager", 0))

    def test_no_keyboard(self):
        self.assertEqual(vk.decode_status(b"\x0a\x051.3.2"), ("", 0))


class OverlaySafety(unittest.TestCase):
    def test_every_text_is_plain(self):
        qml = (ROOT / "Overlay.qml").read_text()
        blocks = re.findall(r"^\s*Text \{.*?^\s*\}", qml, re.M | re.S)
        self.assertGreater(len(blocks), 0)
        for block in blocks:
            self.assertIn("textFormat: Text.PlainText", block)


if __name__ == "__main__":
    unittest.main()
