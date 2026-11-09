"""Tests for lib/regedit.py, lib/steam_shortcut.py, lib/ffnx.py and lib/backup.py. DROIDDECK_SRC (a DroidDeck
checkout) enables the checks against DroidDeck's own code.

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


class FfnxTest(unittest.TestCase):
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

    def set_exe(self, exe, version="SteamReRelease", channel="Stable"):
        with open(self.settings, "w", encoding="utf-8-sig") as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n<Settings xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n'
                    '  <FF7Exe>%s</FF7Exe>\n  <FF7InstalledVersion>%s</FF7InstalledVersion>\n'
                    '  <FFNxUpdateChannel>%s</FFNxUpdateChannel>\n</Settings>\n' % (exe, version, channel))

    def tool(self, *args):
        return subprocess.run([sys.executable, "-I", os.path.join(LIB, "ffnx.py")] + list(args),
                              capture_output=True, text=True)

    def run_tool(self, steam):
        return self.tool("settings", self.settings, self.drive_c, steam).returncode

    def driver(self):
        result = self.tool("driver", self.settings, self.drive_c)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.rstrip("\n").split("\t")

    def read(self):
        with open(self.toml, newline="") as f:
            return f.read()

    def touch(self, *names):
        for name in names:
            open(os.path.join(self.game, name), "w").close()

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

    def test_a_drive_of_the_prefix(self):
        dosdevices = os.path.join(self.dir.name, "dosdevices")
        os.makedirs(dosdevices)
        try:
            os.symlink(os.path.join(self.drive_c, "FINAL FANTASY VII"), os.path.join(dosdevices, "s:"))
        except OSError:
            self.skipTest("no symlinks here")
        self.set_exe(r"S:\ff7\workingdir\ff7_en.exe")
        self.assertEqual(self.run_tool("1"), 0)
        self.assertIn("enable_steam_achievements = true", self.read())

    def test_no_ffnx_yet(self):
        os.remove(self.toml)
        self.assertEqual(self.run_tool("0"), 3)
        self.assertFalse(os.path.exists(self.toml))

    def test_exists_only_checks(self):
        self.assertEqual(self.tool("exists", self.settings, self.drive_c).returncode, 0)
        self.assertEqual(self.read(), FFNX_TOML)
        os.remove(self.toml)
        self.assertEqual(self.tool("exists", self.settings, self.drive_c).returncode, 3)

    def test_other_drive(self):
        self.set_exe(r"D:\ff7.exe")
        self.assertEqual(self.run_tool("0"), 1)

    def test_driver_states(self):
        self.assertEqual(self.driver(), [self.game, "none", "Stable", "FFNx-Steam"])
        self.touch("AF3DN.P", "steam_api.dll")
        self.assertEqual(self.driver()[1], "old")
        self.touch("FFNx_steam_api.dll")
        self.assertEqual(self.driver()[1], "current")

    def test_driver_for_1998_and_canary(self):
        self.set_exe(r"C:\FINAL FANTASY VII\ff7\workingdir\ff7.exe", "Original98", "Canary")
        self.touch("AF3DN.P")
        self.assertEqual(self.driver()[1:], ["none", "Canary", "FFNx-FF7_1998"])
        self.touch("FFNx.dll")
        self.assertEqual(self.driver()[1], "old")

    def make_zip(self, entries):
        import zipfile
        path = os.path.join(self.dir.name, "FFNx-Steam-v9.zip")
        with zipfile.ZipFile(path, "w") as z:
            for name, data in entries.items():
                z.writestr(name, data)
        return path

    def test_install_keeps_settings(self):
        with open(self.toml, "w", newline="") as f:
            f.write('renderer_backend = 5\nmod_path = "mods/#Textures" # where\ngone_key = 1\n')
        self.touch("AF3DN.P", "steam_api.dll")
        archive = self.make_zip({
            "AF3DN.P": "new driver",
            "FFNx_steam_api.dll": "api",
            "shaders/": "",
            "shaders/a.bin": "shader",
            "FFNx.toml": '# FFNx config file\r\n# renderer_backend = 9\r\nrenderer_backend = 0 # backend\r\n'
                         'mod_path = "mods/Textures"\r\nnew_key = true\r\n',
        })
        result = self.tool("install", archive, self.game)
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(os.path.join(self.game, "AF3DN.P")) as f:
            self.assertEqual(f.read(), "new driver")
        self.assertTrue(os.path.isfile(os.path.join(self.game, "shaders", "a.bin")))
        self.assertEqual(self.driver()[1], "current")
        self.assertEqual(self.read(), '# FFNx config file\r\n# renderer_backend = 9\r\nrenderer_backend = 5 # backend\r\n'
                                      'mod_path = "mods/#Textures"\r\nnew_key = true\r\n')
        with open(self.toml + ".7thdroid-bak") as f:
            self.assertIn("gone_key = 1", f.read())

    def test_install_refuses_paths_outside_the_folder(self):
        archive = self.make_zip({"AF3DN.P": "x", "../escaped.txt": "x"})
        self.assertEqual(self.tool("install", archive, self.game).returncode, 1)
        self.assertFalse(os.path.exists(os.path.join(self.game, "AF3DN.P")))
        self.assertFalse(os.path.exists(os.path.join(os.path.dirname(self.game), "escaped.txt")))


class BackupTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = self.dir.name
        self.src = os.path.join(self.root, "src")
        os.makedirs(os.path.join(self.src, "sub"))
        os.makedirs(os.path.join(self.src, "temp"))
        self.write(os.path.join(self.src, "a.txt"), "new a")
        self.write(os.path.join(self.src, "sub", "b.txt"), "b")
        self.write(os.path.join(self.src, "temp", "junk"), "junk")
        self.manifest = os.path.join(self.root, "manifest.env")
        self.write(self.manifest, "BACKUP_DATE=2026-11-09 12:00\nPARTS=mods\n")
        self.tar = os.path.join(self.root, "backup.tar")

    def tearDown(self):
        self.dir.cleanup()

    def write(self, path, text):
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def read(self, path):
        with open(path, encoding="utf-8") as f:
            return f.read()

    def tool(self, *args):
        return subprocess.run([sys.executable, "-I", os.path.join(LIB, "backup.py")] + list(args),
                              capture_output=True, text=True)

    def names(self):
        import tarfile
        with tarfile.open(self.tar) as tar:
            return tar.getnames()

    def test_create_leaves_out_excludes_links_and_missing(self):
        try:
            os.symlink(os.path.join(self.src, "a.txt"), os.path.join(self.src, "link"))
        except OSError:
            pass
        result = self.tool("create", self.tar, self.manifest, "mods=%s!temp" % self.src,
                           "game/FFNx.toml=%s" % os.path.join(self.root, "missing.toml"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(self.names()), ["manifest.env", "mods", "mods/a.txt", "mods/sub", "mods/sub/b.txt"])
        self.assertFalse(os.path.exists(self.tar + ".part"))
        self.assertEqual(self.tool("manifest", self.tar).stdout, "BACKUP_DATE=2026-11-09 12:00\nPARTS=mods\n")

    def test_extract_overwrites_and_keeps_the_rest(self):
        self.tool("create", self.tar, self.manifest, "mods=%s!temp" % self.src)
        dest = os.path.join(self.root, "dest")
        os.makedirs(dest)
        self.write(os.path.join(dest, "a.txt"), "old a")
        self.write(os.path.join(dest, "mine.txt"), "mine")
        self.assertEqual(self.tool("extract", self.tar, "mods", dest).returncode, 0)
        self.assertEqual(self.read(os.path.join(dest, "a.txt")), "new a")
        self.assertEqual(self.read(os.path.join(dest, "sub", "b.txt")), "b")
        self.assertEqual(self.read(os.path.join(dest, "mine.txt")), "mine")
        self.assertEqual(self.tool("extract", self.tar, "saves", dest).returncode, 3)

    def test_extract_a_single_file(self):
        self.tool("create", self.tar, self.manifest, "game/FFNx.toml=%s" % os.path.join(self.src, "a.txt"))
        target = os.path.join(self.root, "out", "FFNx.toml")
        self.assertEqual(self.tool("extract", self.tar, "game/FFNx.toml", target).returncode, 0)
        self.assertEqual(self.read(target), "new a")

    def bad_tar(self, member):
        import io, tarfile
        with tarfile.open(self.tar, "w") as tar:
            data = b"x"
            member.size = len(data) if member.isfile() else 0
            tar.addfile(member, io.BytesIO(data) if member.isfile() else None)

    def test_extract_refuses_escapes_and_links(self):
        import tarfile
        dest = os.path.join(self.root, "dest")
        self.bad_tar(tarfile.TarInfo("saves/../escaped.txt"))
        self.assertEqual(self.tool("extract", self.tar, "saves", dest).returncode, 1)
        self.assertFalse(os.path.exists(os.path.join(self.root, "escaped.txt")))
        link = tarfile.TarInfo("saves/link")
        link.type, link.linkname = tarfile.SYMTYPE, "/etc/passwd"
        self.bad_tar(link)
        self.assertEqual(self.tool("extract", self.tar, "saves", dest).returncode, 1)
        self.assertFalse(os.path.lexists(os.path.join(dest, "link")))

    def test_settings_keep_this_installs_paths(self):
        old = os.path.join(self.root, "old.xml")
        self.write(old, '<?xml version="1.0" encoding="utf-8"?>\n<Settings>\n  <AppLanguage>de</AppLanguage>\n'
                        '  <FF7Exe>Z:\\old\\ff7_en.exe</FF7Exe>\n  <FF7InstalledVersion>Steam</FF7InstalledVersion>\n'
                        '  <LibraryLocation>Z:\\old\\mods</LibraryLocation>\n</Settings>\n')
        self.tool("create", self.tar, self.manifest, "workshop/settings.xml=%s" % old)
        current = os.path.join(self.root, "settings.xml")
        self.write(current, '<?xml version="1.0" encoding="utf-8"?>\n<Settings>\n  <AppLanguage>en</AppLanguage>\n'
                            '  <FF7Exe>C:\\FINAL FANTASY VII\\FFVII.exe</FF7Exe>\n'
                            '  <FF7InstalledVersion>SteamReRelease</FF7InstalledVersion>\n'
                            '  <LibraryLocation>C:\\7th Heaven\\mods</LibraryLocation>\n</Settings>\n')
        self.assertEqual(self.tool("settings", self.tar, current).returncode, 0)
        text = self.read(current)
        self.assertIn("<AppLanguage>de</AppLanguage>", text)
        self.assertIn("<FF7Exe>C:\\FINAL FANTASY VII\\FFVII.exe</FF7Exe>", text)
        self.assertIn("<FF7InstalledVersion>SteamReRelease</FF7InstalledVersion>", text)
        self.assertIn("<LibraryLocation>C:\\7th Heaven\\mods</LibraryLocation>", text)

    def test_ffnx_path_and_merge(self):
        drive_c = os.path.join(self.root, "drive_c")
        settings = os.path.join(self.root, "s.xml")
        self.write(settings, "<Settings><LibraryLocation>C:\\7th Heaven\\mods</LibraryLocation></Settings>")
        ffnx = [sys.executable, "-I", os.path.join(LIB, "ffnx.py")]
        result = subprocess.run(ffnx + ["path", settings, drive_c, "LibraryLocation"], capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), os.path.join(drive_c, "7th Heaven", "mods"))
        new, old = os.path.join(self.root, "new.toml"), os.path.join(self.root, "old.toml")
        self.write(new, "renderer_backend = 0\nnew_key = 1\n")
        self.write(old, "renderer_backend = 5\n")
        self.assertEqual(subprocess.run(ffnx + ["merge", new, old]).returncode, 0)
        self.assertEqual(self.read(new), "renderer_backend = 5\nnew_key = 1\n")


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
