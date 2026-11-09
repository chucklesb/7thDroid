"""Tests for lib/regedit.py, lib/steam_shortcut.py, lib/ffnx.py, lib/backup.py, lib/redact.py and
lib/logs.py. DROIDDECK_SRC (a DroidDeck checkout) enables the checks against DroidDeck's own code.

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

    def test_launcher_ff7exe_means_its_workingdir(self):
        # 7thDroid writes FFVII.exe (the 2026 release's launcher); 7th Heaven switches FF7Exe to
        # ff7/workingdir only on the next Play, and FFNx lives there all along.
        self.set_exe(r"C:\FINAL FANTASY VII\FFVII.exe")
        self.touch("AF3DN.P", "steam_api.dll")
        self.assertEqual(self.driver()[:2], [self.game, "old"])
        self.assertEqual(self.tool("exists", self.settings, self.drive_c).returncode, 0)
        self.assertEqual(self.run_tool("1"), 0)
        self.assertIn("enable_steam_achievements = true", self.read())

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


def load_lib(name):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, os.path.join(LIB, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RedactTest(unittest.TestCase):
    """DroidDeck's LogRedactorTest, LogRedactorStreamTest and SecretScrubTest cases (commit 7c89c14a),
    against the port in lib/redact.py."""

    def setUp(self):
        self.r = load_lib("redact")
        self.dir = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.dir.cleanup()

    def file(self, name, data):
        path = os.path.join(self.dir.name, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode("utf-8"))
        return path

    def share_file(self, path):
        out = []
        self.r.scrub_for_share(self.r.file_chunks(path), out.append)
        return "".join(out)

    def test_labelled_jwt(self):
        out = self.r.redact("Using JWT 25484942796017334")
        self.assertNotIn("25484942796017334", out)
        self.assertIn("<redacted:jwt>", out)

    def test_secret_pair_keeps_its_key(self):
        out = self.r.redact("GET /x?sessionid=abcdef123456 200")
        self.assertNotIn("abcdef123456", out)
        self.assertIn("sessionid=", out)

    def test_plain_values_survive(self):
        self.assertEqual(self.r.redact("language key=english"), "language key=english")
        self.assertEqual(self.r.redact("[2026-09-27 10:03:05] Startup"), "[2026-09-27 10:03:05] Startup")

    def test_steam_ids_are_masked(self):
        self.assertEqual(self.r.redact("user 76561198012341234"), "user 76561********1234")
        self.assertEqual(self.r.redact("id [U:1:52075506]"), "id [U:1:****5506]")

    def test_webapi_key_but_not_depot_chunk(self):
        key, chunk = "0123456789abcdef0123456789abcdef", "0123456789abcdef0123456789abcdef01234567"
        self.assertNotIn(key, self.r.redact("key " + key))
        self.assertIn(chunk, self.r.redact("chunk " + chunk))

    def test_email(self):
        self.assertEqual(self.r.redact("login someone@example.com ok"), "login <redacted:email> ok")

    def test_hidl_loader_diagnostics_are_kept(self):
        library = "android.hardware.graphics.mapper@4.0.so"
        for line in ('dlopen failed: library "%s" not found' % library,
                     'dlopen failed: library "/vendor/lib64/hw/%s" not found' % library,
                     'library "/system/lib64/%s" not found: needed by app' % library):
            self.assertEqual(self.r.redact(line), line)
            self.assertEqual(self.r.redact_for_share(line), line)

    def test_privacy_rules_override_the_hidl_exception(self):
        library = "android.hardware.graphics.mapper@4.0.so"
        self.assertEqual(self.r.redact("token=" + library), "token=<redacted:token>")
        self.assertEqual(self.r.redact("username=" + library), "username=<redacted:account>")
        self.assertEqual(self.r.redact('{"password":"%s"}' % library), '{"password":"<redacted:token>"}')
        self.assertEqual(self.r.redact_for_share('{"password":"don\'t-use-%s"}' % library), '{"password":"<redacted:token>"}')
        mixed = ('dlopen failed: library "%s" not found; token=abcdef123456; contact=alice!%s; '
                 '{"password":"library \\"%s\\" not found"}' % (library, library, library))
        expected = ('dlopen failed: library "%s" not found; token=<redacted:token>; contact=alice!<redacted:email>; '
                    '{"password":"<redacted:token>"}' % library)
        self.assertEqual(self.r.redact(mixed), expected)
        self.assertEqual(self.r.redact_for_share(mixed), expected)

    def test_hidl_names_elsewhere_are_redacted(self):
        library = "android.hardware.graphics.mapper@4.0.so"
        self.assertEqual(self.r.redact(library), "<redacted:email>")
        self.assertEqual(self.r.redact("/vendor/lib64/hw/" + library), "/vendor/lib64/hw/<redacted:email>")
        for punctuation in "!#~/=":
            self.assertEqual(self.r.redact_for_share("contact=alice" + punctuation + library), "contact=alice" + punctuation + "<redacted:email>")
        for line, expected in ((library + ".evil", "<redacted:email>"), ("someone@company.so", "<redacted:email>"),
                               ("not" + library, "<redacted:email>"), (library + "_debug", "<redacted:email>_debug"),
                               (library + ".1", "<redacted:email>.1"), (library + "@attacker", "<redacted:email>@attacker"),
                               ("android.hardware.graphics.mapper@4.0.software", "<redacted:email>")):
            self.assertEqual(self.r.redact(line), expected)
        for line in ('not_library "%s" not found' % library, 'library "%s" not found_suffix' % library,
                     'library "/home/user/%s" not found' % library, 'library "relative/%s" not found' % library,
                     'library "/vendor/invalid!/%s" not found' % library,
                     'library "/vendor/' + "a/" * 2050 + library + '" not found'):
            self.assertEqual(self.r.redact(line), line.replace(library, "<redacted:email>"))

    def test_mac_addresses(self):
        for line, expected in (("  mac 02:ab:cd:ef:12:34", "  mac <redacted:mac>"),
                               ("controller A2-B3-C4-D5-E6-F7 connected", "controller <redacted:mac> connected"),
                               ("mac=02:ab:cd:ef:12:34, peer=a2:b3:c4:d5:e6:f7", "mac=<redacted:mac>, peer=<redacted:mac>"),
                               ("MAC:02:ab:cd:ef:12:34", "MAC:<redacted:mac>"),
                               ("MacAddress:A2-B3-C4-D5-E6-F7", "MacAddress:<redacted:mac>"),
                               ('{"mac_address":"02:ab:cd:ef:12:34"}', '{"mac_address":"<redacted:mac>"}')):
            self.assertEqual(self.r.redact(line), expected)
        line = "[12:34:56] server ab:cd:ef:12:34:56:78:90 partial=ab:cd:ef:12:34 mixed=ab:cd-ef:12:34:56"
        self.assertEqual(self.r.redact(line), line)

    def test_device_identifiers(self):
        for label in ("Serial number", "serial_number", "serialNumber", "serial", "device_serial", "Controller Serial", "ANDROID_ID", "build.serial"):
            self.assertEqual(self.r.redact(label + ": controller-123456"), label + ": <redacted:serial>")
        self.assertEqual(self.r.redact("Serial number: 12345678901234567 connected"), "Serial number: <redacted:serial> connected")
        self.assertEqual(self.r.redact('{"serial_number":"controller 123456","result":0}'), '{"serial_number":"<redacted:serial>","result":0}')
        self.assertEqual(self.r.redact("device_serial = 'controller 123456'"), "device_serial = '<redacted:serial>'")
        line = "serial port initialized; serial_number_count=2; controller=12345678901234567"
        self.assertEqual(self.r.redact(line), line)

    def test_redacting_twice_changes_nothing(self):
        for line in ("Using JWT 25484942796017334", "token=abcdefghijklmnop sessionid=qrstuvwxyz123",
                     "user 76561198012341234 [U:1:52075506]", "external address 2607:f8b0:4005:80a::200e",
                     "OnLoginStateChange someaccount 2 1 0 0", "mac 02:ab:cd:ef:12:34 controller A2-B3-C4-D5-E6-F7",
                     "MAC:02:ab:cd:ef:12:34", "Serial number: 12345678901234567", '{"ANDROID_ID":"0123456789abcdef"}'):
            once = self.r.redact(line)
            self.assertEqual(self.r.redact(once), once)

    def test_login_state_lines(self):
        for account in ("someone.masked@example.com", "maskeduser42"):
            line = "[2026-10-07 21:14:03] SteamUI: INFO: Login: OnLoginStateChange %s 2 1 0 0" % account
            expected = "[2026-10-07 21:14:03] SteamUI: INFO: Login: OnLoginStateChange <redacted:account> 2 1 0 0"
            self.assertEqual(self.r.redact(line), expected)
            self.assertEqual(self.r.redact_for_share(line), expected)
        line = "SteamUI: INFO: Login: OnLoginStateChange  0 1 0 0"
        self.assertEqual(self.r.redact(line), line)

    def test_account_fields(self):
        for line in ('\t"AccountName"\t\t"maskeduser42"', "account_name=maskeduser42 remember=1",
                     '{"login":"maskeduser42","persist":1}', "auth: login=maskeduser42&remember=1",
                     "accountName: maskeduser42", '{"username": "masked user 42"}',
                     "[Clubs] {Main} Club membership subscription created: |accountId=maskeduser42"):
            out = self.r.redact_for_share(line)
            self.assertNotIn("maskeduser42", out)
            self.assertNotIn("masked user", out)
            self.assertIn("<redacted:account>", out)
            self.assertEqual(self.r.redact_for_share(out), out)
        for line in ("login refresh pending", "Login: state 5"):
            self.assertEqual(self.r.redact(line), line)

    def test_lan_addresses_leave_public_ones_stay(self):
        self.assertEqual(self.r.redact_for_share("I/LinuxNetworkLink: resolver: 192.168.1.1 10.0.0.138 8.8.8.8"),
                         "I/LinuxNetworkLink: resolver: <lan-address> <lan-address> 8.8.8.8")
        self.assertEqual(self.r.redact_for_share("gateway 172.16.4.20:53 link 169.254.10.2 lan 172.31.255.254"),
                         "gateway <lan-address>:53 link <lan-address> lan <lan-address>")
        for line in ("connecting to CM 162.254.193.47:27017", "public 172.32.0.1 and 11.0.0.1 and 193.168.1.1",
                     "Windows 10.0.19041.1 build 10.0.19045", "Proton 10.0-3, driver 25.1.0.4"):
            self.assertEqual(self.r.redact_for_share(line), line)

    def test_oversized_input_is_withheld(self):
        line = "x" * self.r.MAX_LINE_LENGTH + "sessionid=abcdef123456"
        self.assertEqual(self.r.redact(line), self.r.OVERSIZED_LINE)
        self.assertEqual(self.r.redact_for_share(line), self.r.OVERSIZED_LINE)

    def test_learned_accounts(self):
        users = self.file("loginusers.vdf", "\n".join('"AccountName" "probe_account_%d"' % i for i in range(40)) + '\n"PersonaName" "Player.+[40]"\n')
        self.r.learn_accounts(users)
        self.assertEqual(self.r.redact("owner=probe_account_39 persona=Player.+[40]"), "owner=<redacted:account> persona=<redacted:account>")
        self.assertEqual(self.r.redact("owner=probe_account_390"), "owner=probe_account_390")

    def test_oversized_learning_keeps_known_values(self):
        users = self.file("known.vdf", '"AccountName" "previous_player"')
        oversized = self.file("oversized.vdf", b"\0" * (self.r.MAX_LEARN_INPUT_BYTES + 1))
        self.assertTrue(self.r.learn_accounts(users))
        self.assertFalse(self.r.learn_accounts(oversized))
        self.assertEqual(self.r.redact("previous_player"), "<redacted:account>")
        link = self.file("net", "addr 203.0.113.40 24\n")
        self.assertTrue(self.r.learn_own_addresses(link))
        self.assertFalse(self.r.learn_own_addresses(oversized))
        self.assertEqual(self.r.redact("203.0.113.40"), "<redacted:ip>")

    def test_learned_addresses_keep_others(self):
        link = self.file("droiddeck-net", "\n".join("addr 203.0.113.%d 24" % i for i in range(1, 41)))
        self.r.learn_own_addresses(link)
        self.assertEqual(self.r.redact("local=203.0.113.40 server=203.0.113.200"), "local=<redacted:ip> server=203.0.113.200")

    def test_learned_from_both_steam_clients(self):
        root = self.dir.name
        self.file("root/.local/share/Steam/config/loginusers.vdf", '"users" { "7656" { "AccountName" "armplayer" "PersonaName" "Arm Persona" } }')
        self.r.learn_from_runtime(root)
        self.assertEqual(self.r.redact("hi armplayer and Arm Persona"), "hi <redacted:account> and <redacted:account>")
        self.file("root/.droiddeck-x64/.local/share/Steam/config/loginusers.vdf", '"users" { "7656" { "AccountName" "x64player" } }')
        self.r.learn_from_runtime(root)
        self.assertEqual(self.r.redact("armplayer x64player"), "<redacted:account> <redacted:account>")

    def test_learned_account_ids(self):
        # 7thDroid's addition: the account IDs of loginusers.vdf's SteamIDs, as Steam's logs write them.
        root = self.dir.name
        self.file("root/.local/share/Steam/config/loginusers.vdf",
                  '"users" { "76561198012341234" { "AccountName" "armplayer" } }')
        self.r.learn_from_runtime(root)
        account_id = str(76561198012341234 - 76561197960265728)
        for line, want in (
                ("Flushed store 'userlocal' to '/root/.local/share/Steam/userdata/%s/config/localconfig.vdf'",
                 "Flushed store 'userlocal' to '/root/.local/share/Steam/userdata/%s/config/localconfig.vdf'"),
                ("[AppID 3837340] AutoCloud force-restoring files for user %s in root",
                 "[AppID 3837340] AutoCloud force-restoring files for user %s in root"),
                ("Account ID: %s", "Account ID: %s")):
            self.assertEqual(self.r.redact(line % account_id), want % self.r.masked(account_id))
        self.assertNotIn(account_id, self.r.masked(account_id))
        self.assertEqual(self.r.redact("id 1%s and %s9" % (account_id, account_id)),
                         "id 1%s and %s9" % (account_id, account_id))
        self.assertEqual(self.r.redact("[U:1:%s]" % account_id), "[U:1:%s]" % self.r.masked(account_id))

    def test_secret_scrub(self):
        share = self.r.secret_scrub
        for line in ("0024:trace:seh:dispatch_exception code=406d1388 flags=0 addr=00006FFFFFC0A6E8",
                     "0024:warn:seh:dispatch_exception code=c0000005 flags=0 addr=0000000140012345",
                     "0030:trace:seh:handle_syscall_fault code=80000003 flags=0",
                     "exception code=0xC0000005 at 0x140012345", "client_id=abc code=c0000005",
                     "exit code=1337", "status code=ERR_TIMEOUT", "code 403"):
            self.assertEqual(share(line), line)
        self.assertEqual(share("redirect client_id=34a02cf8 redirect_uri=x state=1 code=AUTHCODE123"),
                         "redirect client_id=34a02cf8 redirect_uri=x state=1 code=<redacted:token>")
        self.assertEqual(share("GET /on_login_success?code=AUTHCODE123&scope="), "GET /on_login_success?code=<redacted:token>&scope=")
        self.assertEqual(share("exchange_code=0123456789abcdef"), "exchange_code=<redacted:token>")
        self.assertEqual(share("authorizationCode=ABCD1234XYZ"), "authorizationCode=<redacted:token>")
        once = share("client_id=1 code=AUTHCODE123 ?code=XYZW1234567")
        self.assertNotIn("AUTHCODE123", once)
        self.assertEqual(share(once), once)

    def test_stream_withholds_utf16_nul_and_bad_utf8(self):
        token = "synthetic_private_value"
        for data in (("sessionid=" + token).encode("utf-16-le"), ("sessionid=" + token).encode("utf-16-be"),
                     ("sessionid=" + token).encode("utf-16"),
                     ("." * 9000 + "\0sessionid=" + token).encode("utf-8"),
                     ("sessionid=" + token + " ").encode("utf-8") + b"\xc3\x28"):
            out = self.share_file(self.file("x.log", data))
            self.assertNotIn(token, out.replace("\0", ""))
            self.assertIn("withheld", out)

    def test_stream_long_lines_and_line_endings(self):
        path = self.file("long.log", "sessionid=synthetic_private_value " + "." * (128 * 64 * 1024) + "\nready=1 token=another_private_value\n")
        out = self.share_file(path)
        self.assertLess(len(out), 1024)
        self.assertIn("ready=1 token=<redacted:token>", out)
        self.assertNotIn("private_value", out)
        path = self.file("unicode.log", "hazır=✓ token=synthetic_private_value\r\n\rstatus=ok\nson")
        self.assertEqual(self.share_file(path), "hazır=✓ token=<redacted:token>\n\nstatus=ok\nson\n")
        path = self.file("lines.log", "x" * (self.r.MAX_LINE_LENGTH + 1) + "\nprivate-prefix\0private-suffix\nafter sessionid=abcdef123456\n")
        self.assertEqual(self.share_file(path), self.r.OVERSIZED_LINE + "\n<unsupported or oversized line withheld>\nafter sessionid=<redacted:token>\n")
        line = "x " * (self.r.MAX_LINE_LENGTH // 2)
        self.assertEqual(self.share_file(self.file("max.log", line + "\r\n")), line + "\n")


class LogsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def write(self, rel, data):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode("utf-8"))
        return path

    def test_bundle(self):
        import tarfile
        self.write("session/main.log", "start\naccess_token=abcdef123456\n")
        self.write("session/steam/steam.log", "OnLoginStateChange someone 2 1 0 0\n")
        self.write("session/core.bin", b"\x7fELF\0\0\0")
        big = self.write("big.log", "early secret line\n" + ("x" * 99 + "\n") * 90000 + "last line\n")
        out = os.path.join(self.root, "logs.tar")
        env = dict(os.environ, REDACT_ROOT=os.path.join(self.root, "nothing"))
        result = subprocess.run([sys.executable, "-I", os.path.join(LIB, "logs.py"), "bundle", out,
                                 "droiddeck/session=" + os.path.join(self.root, "session"), "game/big.log=" + big,
                                 "missing=" + os.path.join(self.root, "missing")], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        with tarfile.open(out) as tar:
            names = tar.getnames()
            read = lambda n: tar.extractfile(n).read().decode()
            self.assertEqual(sorted(names), ["droiddeck/session/main.log", "droiddeck/session/steam/steam.log", "game/big.log", "index.txt"])
            self.assertEqual(read("droiddeck/session/main.log"), "start\naccess_token=<redacted:token>\n")
            self.assertIn("<redacted:account>", read("droiddeck/session/steam/steam.log"))
            tail = read("game/big.log")
            self.assertTrue(tail.startswith("<7thDroid: the first "))
            self.assertTrue(tail.endswith("last line\n"))
            self.assertNotIn("early secret", tail)
            index = read("index.txt")
            self.assertIn("droiddeck/session/core.bin\t7\tleft out: binary", index)
            self.assertIn("game/big.log\t", index)
        self.assertFalse(os.path.exists(out + ".part"))


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
