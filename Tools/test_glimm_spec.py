"""Glimm is described once (Tools/glimm/spec.js) and read in three places: the drawing in LumaKit, the
wardrobe and the moods in LumaCore, and the reference renderer. These tests hold the three together:
a cut the wardrobe offers that the drawing cannot draw, or a mood one side has and the other lacks,
would show as a wrong picture on a phone and nowhere else.
"""
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "Packages/LumaUI/Sources/LumaKit/GlimmArt.swift"
FIGURE = ROOT / "Packages/LumaUI/Sources/LumaKit/GlimmFigure.swift"
RIG = ROOT / "Packages/LumaUI/Sources/LumaKit/GlimmRig.swift"
CORE = ROOT / "Packages/LumaCore/Sources/LumaCore/Glimm.swift"
VOICE = ROOT / "Packages/LumaCore/Sources/LumaCore/GlimmVoice.swift"
CORE_TESTS = ROOT / "Packages/LumaCore/Tests/LumaCoreTests/GlimmTests.swift"

SLOT_TABLE = {"top": "tops", "bottom": "bottoms", "feet": "feet", "head": "heads", "accessory": "accs"}


def spec():
    text = ART.read_text(encoding="utf-8")
    start = text.index('#"""') + 4
    return json.loads(text[start:text.index('"""#', start)])


def wardrobe():
    """(id, slot, shape) for every cut in LumaCore's table."""
    text = CORE.read_text(encoding="utf-8")
    rows = re.findall(r"^\s+([a-z-]+)\|([^|\n]+)\|(top|bottom|feet|head|accessory)\|([a-z]+)\|([a-z]+)\|(\d)\s*$", text, re.M)
    return [(r[0], r[2], r[3]) for r in rows]


class GlimmSpecTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "node is needed to rebuild the description")
    def test_the_embedded_description_is_what_the_spec_gives(self):
        done = subprocess.run(["node", str(ROOT / "Tools/glimm/build.mjs"), "--check"], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_the_description_has_every_part_the_rig_reads(self):
        s = spec()
        for key in ["rig", "z", "colors", "face", "fallback", "body", "leaf", "sil", "tops", "bottoms", "feet", "heads", "accs", "held",
                    "props", "defaults", "breath", "moods", "gestures", "taps"]:
            self.assertIn(key, s)
        for slot, shape in s["fallback"].items():
            self.assertIn(shape, s[SLOT_TABLE.get(slot, {"acc": "accs"}.get(slot, slot))], f"the fallback for {slot}")

    def test_every_cut_in_the_wardrobe_can_be_drawn_and_nothing_drawn_is_missing_from_it(self):
        s = spec()
        cuts = wardrobe()
        self.assertEqual(len(cuts), 64)
        for cut, slot, shape in cuts:
            self.assertIn(shape, s[SLOT_TABLE[slot]], f"{cut}: the drawing has no {slot} called {shape}")
        for slot, table in SLOT_TABLE.items():
            known = {shape for _, where, shape in cuts if where == slot}
            self.assertEqual(set(s[table]) - known, set(), f"drawn but not in the wardrobe ({slot})")

    def test_the_moods_are_the_same_everywhere(self):
        s = spec()
        core = re.search(r"enum GlimmMood: String[^{]*\{\s*case ([^\n]+)", CORE.read_text(encoding="utf-8")).group(1)
        core_moods = {m.strip() for m in core.split(",")}
        figure = FIGURE.read_text(encoding="utf-8")
        listed = re.search(r"public static let moods = \[(.*?)\]", figure, re.S).group(1)
        kit_moods = set(re.findall(r'"([a-z]+)"', listed))
        self.assertEqual(core_moods, set(s["moods"]))
        self.assertEqual(kit_moods, set(s["moods"]))
        # Every state of the day is drawn in a mood there is.
        mapped = set(re.findall(r'case \.[a-z]+: return "([a-z]+)"', figure))
        self.assertTrue(mapped)
        self.assertLessEqual(mapped, set(s["moods"]))

    def test_what_a_mood_names_exists(self):
        s = spec()
        channels = set(s["defaults"])

        def words(pose):
            for key, value in pose.items():
                self.assertIn(key, channels, f"{key} is not a channel")
                if key == "prop" and value != "none":
                    self.assertIn(value, s["props"])
                if key == "hold" and value != "none":
                    self.assertIn(value, s["held"])

        for name, mood in s["moods"].items():
            words(mood.get("base", {}))
            words(mood.get("live", {}))
            for gesture in mood.get("gestures", []):
                self.assertIn(gesture, s["gestures"], f"{name} does a {gesture}")
            for still in mood.get("stills", []):
                if "g" in still:
                    self.assertIn(still["g"], s["gestures"], f"{name} stands in a {still['g']}")
                words(still.get("set", {}))
            for osc in mood.get("osc", []):
                self.assertIn(osc[0], channels)
        for table in ("gestures", "taps"):
            for name, gesture in s[table].items():
                self.assertGreater(gesture["dur"], 0, name)
                for at, pose in gesture["keys"]:
                    self.assertTrue(0 <= at <= 1, name)
                    words(pose)

    def test_every_touch_has_an_answer_and_words(self):
        s = spec()
        zones = set(re.findall(r'return (?:[^"\n]*\? )?"([a-z]+)"', RIG.read_text(encoding="utf-8").split("static func zone")[1]))
        zones |= set(re.findall(r'\? "([a-z]+)" : "([a-z]+)"', RIG.read_text(encoding="utf-8").split("static func zone")[1])[0])
        self.assertEqual(zones, {"leaf", "head", "cheek", "belly", "hand", "feet"})
        voice = VOICE.read_text(encoding="utf-8")
        for zone in zones:
            self.assertIn(zone, s["taps"], f"no answer to a touch on the {zone}")
            self.assertIn(f'"tap.{zone}"', voice, f"nothing to say to a touch on the {zone}")
        # A widget's tap is answered with these two.
        self.assertIn("head", s["taps"])
        self.assertIn("leaf", s["taps"])
        self.assertIn("twirl", s["gestures"], "a change of clothes is played as a twirl")
        self.assertIn("cheer", s["gestures"], "a like is answered with a cheer")

    def test_the_everyday_look_is_one_string(self):
        kit = re.search(r'public static let signature = "([^"]+)"', FIGURE.read_text(encoding="utf-8")).group(1)
        self.assertIn(f'"{kit}"', CORE_TESTS.read_text(encoding="utf-8"), "LumaCore's test pins the same look")
        s = spec()
        top, bottom, feet, head, acc = [part.split(":")[0] for part in kit.split("|")]
        self.assertIn(top, s["tops"])
        self.assertIn(bottom, s["bottoms"])
        self.assertIn(feet, s["feet"])
        self.assertEqual(head, "-")
        self.assertIn(acc, s["accs"])


if __name__ == "__main__":
    unittest.main()
