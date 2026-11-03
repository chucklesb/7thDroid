"""Tests for lib/regedit.py and lib/steam_shortcut.py. DROIDDECK_SRC (a DroidDeck checkout) enables the
checks against DroidDeck's own code.

    python3 -m unittest discover -s tests
"""
import os
import runpy
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(REPO, "lib")
SRC = os.environ.get("DROIDDECK_SRC", "")
BIN = os.path.join(SRC, "tools", "linuxfs", "overlay", "usr", "local", "bin")

USER_REG = r'''WINE REGISTRY Version 2
;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

#arch=win64

[Software\\Wine\\DllOverrides] 1700000000
#time=1d9d0a1b2c3d4e5
"d3d9"="native"
"dinput"="builtin"
"long"=hex:01,02,\
  03,04

[Software\\Wine\\Other] 1700000000
#time=1
"x"="y"
'''


class RegeditTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "user.reg")
        with open(self.path, "w") as f:
            f.write(USER_REG)

    def tearDown(self):
        self.dir.cleanup()

    def edit(self, *args):
        subprocess.run([sys.executable, "-I", os.path.join(LIB, "regedit.py"), self.path] + list(args), check=True)
        with open(self.path) as f:
            return f.read()

    def test_replaces_existing_value_in_place(self):
        text = self.edit(r"Software\Wine\DllOverrides", "DINPUT", "str:native,builtin")
        self.assertIn('"DINPUT"="native,builtin"', text)
        self.assertNotIn('"dinput"="builtin"', text)
        self.assertEqual(text.count("DllOverrides"), 1)
        self.assertLess(text.index("native,builtin"), text.index(r"[Software\\Wine\\Other]"))

    def test_replaces_multiline_value(self):
        text = self.edit(r"Software\Wine\DllOverrides", "long", "dword:1")
        self.assertIn('"long"=dword:00000001\n\n[Software', text)
        self.assertNotIn("03,04", text)

    def test_adds_value_to_existing_key(self):
        text = self.edit(r"software\wine\other", "z", "str:C:\\path")
        self.assertIn('"x"="y"\n"z"="C:\\\\path"\n', text)

    def test_adds_new_key(self):
        text = self.edit(r"Software\Microsoft\Avalon.Graphics", "DisableHWAcceleration", "dword:1")
        self.assertRegex(text, r'\n\[Software\\\\Microsoft\\\\Avalon\.Graphics\] \d+\n#time=[0-9a-f]+\n"DisableHWAcceleration"=dword:00000001\n$')
        self.assertTrue(text.startswith("WINE REGISTRY Version 2\n"))

    def test_rejects_other_files(self):
        with open(self.path, "w") as f:
            f.write("not a registry")
        result = subprocess.run([sys.executable, "-I", os.path.join(LIB, "regedit.py"), self.path, "K", "n", "str:v"],
                                capture_output=True)
        self.assertEqual(result.returncode, 1)


class ShortcutIdTest(unittest.TestCase):
    @unittest.skipUnless(os.path.isfile(os.path.join(BIN, "droiddeck-proton-run")), "DROIDDECK_SRC not set")
    def test_matches_droiddeck_proton_run(self):
        ours = runpy.run_path(os.path.join(LIB, "steam_shortcut.py"))["appid"]
        theirs = runpy.run_path(os.path.join(BIN, "droiddeck-proton-run"))["own_id"]
        exe = "/root/.local/share/7thdroid/7th Heaven.sh"
        # droiddeck-proton-run names a program after its file name without extension
        self.assertEqual(ours(exe, "7th Heaven"), theirs(exe))

    @unittest.skipUnless(os.path.isfile(os.path.join(BIN, "droiddeck-proton-run")), "DROIDDECK_SRC not set")
    def test_gameid_is_the_steam_game_id_droiddeck_gives_the_prefix(self):
        ours = runpy.run_path(os.path.join(LIB, "steam_shortcut.py"))
        run = runpy.run_path(os.path.join(BIN, "droiddeck-proton-run"))
        exe = "/root/.local/share/7thdroid/7th Heaven.sh"
        number = ours["appid"](exe, "7th Heaven")
        with tempfile.TemporaryDirectory() as root:
            target = run["Target"](number, os.path.join(root, "compatdata", str(number)), root, root, "fixed")
            env = run["environment"]({}, target, root, root)
        self.assertEqual(env["SteamGameId"], str(ours["gameid"](exe, "7th Heaven")))
        self.assertEqual(env["SteamAppId"], "0")

    @unittest.skipUnless(os.path.isfile(os.path.join(BIN, "droiddeck-proton-run")), "DROIDDECK_SRC not set")
    def test_launcher_options_set_only_the_app_id(self):
        run = runpy.run_path(os.path.join(BIN, "droiddeck-proton-run"))
        self.assertEqual(run["split_options"]("SteamAppId=39140 %command%"), ({"SteamAppId": "39140"}, []))


class ShortcutFileTest(unittest.TestCase):
    @unittest.skipUnless(os.path.isfile(os.path.join(BIN, "droiddeck-steam-shortcuts")), "DROIDDECK_SRC not set")
    def test_has_follows_add_and_remove(self):
        tool = os.path.join(BIN, "droiddeck-steam-shortcuts")
        script = os.path.join(LIB, "steam_shortcut.py")
        exe = "/root/.local/share/7thdroid/7th Heaven.sh"
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "userdata", "12345", "config"))

            def call(*args):
                return subprocess.run([sys.executable, script] + list(args), capture_output=True).returncode

            self.assertEqual(call("has", tool, root, exe), 1)
            self.assertEqual(call("add", tool, root, "7th Heaven", exe, os.path.dirname(exe)), 0)
            self.assertEqual(call("has", tool, root, exe), 0)
            self.assertEqual(call("has", tool, root, "/somewhere/else.sh"), 1)
            self.assertEqual(call("remove", tool, root, exe), 0)
            self.assertEqual(call("has", tool, root, exe), 1)


FFNX_TOML = '''#[RENDERING BACKEND]
# - 0: Auto
#~~~~~~~~~~~~~~~~~~~~~~~~~~~
renderer_backend = 0\r
fullscreen = false

# enable_steam_achievements = true
enable_steam_achievements = false # Steam Compatibility
'''


class FfnxTomlTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.drive_c = os.path.join(self.dir.name, "drive_c")
        self.game = os.path.join(self.drive_c, "FINAL FANTASY VII", "ff7", "workingdir")
        os.makedirs(self.game)
        self.settings = os.path.join(self.dir.name, "settings.xml")
        self.set_exe(r"C:\FINAL FANTASY VII\ff7\workingdir\ff7_en.exe")
        self.toml = os.path.join(self.game, "FFNx.toml")
        with open(self.toml, "w", newline="") as f:
            f.write(FFNX_TOML)

    def tearDown(self):
        self.dir.cleanup()

    def set_exe(self, exe):
        with open(self.settings, "w", encoding="utf-8-sig") as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n<Settings xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n'
                    '  <FF7Exe>%s</FF7Exe>\n</Settings>\n' % exe)

    def run_tool(self, steam):
        return subprocess.run([sys.executable, "-I", os.path.join(LIB, "ffnx_toml.py"), self.settings, self.drive_c, steam]).returncode

    def read(self):
        with open(self.toml, newline="") as f:
            return f.read()

    def test_plain_launch(self):
        self.assertEqual(self.run_tool("0"), 0)
        text = self.read()
        self.assertIn("renderer_backend = 3\r\n", text)
        self.assertIn("enable_steam_achievements = false # Steam Compatibility\n", text)
        self.assertIn("# - 0: Auto\n", text)
        self.assertIn("# enable_steam_achievements = true\n", text)
        self.assertEqual(text.replace("= 3", "= 0"), FFNX_TOML)

    def test_steam_launch(self):
        self.assertEqual(self.run_tool("1"), 0)
        self.assertIn("enable_steam_achievements = true # Steam Compatibility\n", self.read())
        self.assertEqual(self.run_tool("0"), 0)
        self.assertIn("enable_steam_achievements = false # Steam Compatibility\n", self.read())

    def test_keeps_a_chosen_backend(self):
        with open(self.toml, "w") as f:
            f.write("renderer_backend = 5\n")
        self.assertEqual(self.run_tool("0"), 0)
        self.assertEqual(self.read(), "renderer_backend = 5\n")

    def test_z_drive(self):
        self.set_exe("Z:" + self.game.replace("/", "\\") + "\\ff7_en.exe")
        self.assertEqual(self.run_tool("1"), 0)
        self.assertIn("enable_steam_achievements = true", self.read())

    def test_no_ffnx_yet(self):
        os.remove(self.toml)
        self.assertEqual(self.run_tool("0"), 3)
        self.assertFalse(os.path.exists(self.toml))

    def test_other_drive(self):
        self.set_exe(r"D:\ff7.exe")
        self.assertEqual(self.run_tool("0"), 1)


class WarningTest(unittest.TestCase):
    def test_installer_warning_is_the_readme_warning(self):
        import re
        with open(os.path.join(REPO, "README.md"), encoding="utf-8") as f:
            quote = []
            for line in f:
                if not line.startswith(">"):
                    if quote:
                        break
                    continue
                quote.append(line[1:].strip())
        text = "\n".join(line for line in quote if line != "[!WARNING]")
        paragraphs = [" ".join(p.split("\n")).strip() for p in text.split("\n\n")]
        readme = [re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", p.replace("**", "")) for p in paragraphs if p]
        with open(os.path.join(REPO, "assets", "WARNING.txt"), encoding="utf-8") as f:
            ours = [p.strip() for p in f.read().split("\n\n") if p.strip()]
        self.assertEqual(ours, readme)


if __name__ == "__main__":
    unittest.main()
