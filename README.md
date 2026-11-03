# 7thDroid

> [!WARNING]
> **THIS SOFTWARE IS EXPERIMENTAL.** It is provided "as is", without warranty of any kind, express or
> implied. The authors and contributors accept no liability for any damage, data loss, lost saves or
> other problems arising from its use. It changes files on your device, downloads and runs third-party
> software (7th Heaven, .NET, DroidDeck-Proton), and has had very little testing. Back up anything you
> care about first, and use it at your own risk. See the [license](LICENSE) for the full terms.
>
> 7thDroid is not affiliated with or endorsed by Square Enix, Valve, GOG, the Tsunamods / 7th Heaven
> team or the DroidDeck project.

Installs the [7th Heaven](https://github.com/tsunamods-codes/7th-Heaven) mod manager for FINAL FANTASY VII on
[DroidDeck](https://github.com/Droid-Deck/DroidDeck), the Android app that runs Steam and Windows games with
Valve's ARM64 Proton and FEX.

7thDroid grew out of [7thDeck](https://github.com/dotaxis/7thDeck), which is now deprecated in favour of
[MateriaForge](https://github.com/dotaxis/MateriaForge-rs). It is a new project, written only for DroidDeck.

## What it does

1. **Finds your copy of FINAL FANTASY VII.** It looks in these places:
   - Steam: the 2013 release (app 39140) and the 2026 release (app 3837340), in any Steam library.
   - The GOG release (1698970154), installed with DroidDeck's own GOG store, with Heroic (AppImage, Flatpak or Nix), or with Lutris (native or Flatpak).

   If none is found, you give it a path to one of these:
   - an installed game folder;
   - a GOG installer (`setup_final_fantasy_vii_*.exe`);
   - the 1998 CD-ROM release, as disc images (`.iso`) or folders copied from the discs.
2. **Prepares a Proton prefix of 7th Heaven's own**, made by [DroidDeck-Proton](https://github.com/Droid-Deck/DroidDeck-Proton).
   - The game files stay where they are; 7th Heaven reaches them through Wine's `Z:` drive, which is the whole Linux file system.
   - No other prefix is touched, including the one Steam made for FF7, so vanilla FF7 from Steam keeps working as before.
   - If DroidDeck-Proton isn't your default Proton, 7thDroid sets it for its own prefix only, the same way picking a game's Proton in the DroidDeck app does.
   - It installs the .NET Desktop Runtime that 7th Heaven needs, both x64 and x86: .NET 9 for the pinned 4.5.2, .NET 10 for current canary builds. After 7th Heaven is installed, it reads the version the app itself asks for and installs that too if it differs.
   - It turns off WinForms/WPF hardware acceleration, because 7th Heaven's controls vanish without that.
   - It makes Wine prefer 7th Heaven's `dinput.dll`. Without that, mods silently don't load.
3. **Installs 7th Heaven** silently into `C:\7th Heaven` in that prefix, then points it at your game.
   - You choose the build: the pinned version, the latest stable release, or the canary build.
4. **Adds shortcuts, if you want them:**
   - the DroidDeck app's Desktop page;
   - Steam, as a non-Steam game;
   - the KDE desktop's menu.

Installers run with the FEX settings DroidDeck uses for .NET programs, including full x87 precision.
Without that, the GOG installer stops with "File not fpund". 7thDroid passes these settings through `droiddeck-proton-run --verb run`, so your FEX preset in the DroidDeck app doesn't override them. Your preset is left unchanged, and it still applies when you play.

## Requirements

- DroidDeck 0.6.7 or newer, with Steam set up (open it once and let it finish downloading what it needs). 7thDroid uses the DroidDeck-Proton support that arrived in 0.6.7; on an older DroidDeck it asks you to update first.
- DroidDeck-Proton. If it's missing, 7thDroid offers to install the newest release with DroidDeck's `droiddeck-proton-extra`; that needs about 4 GB free.
- Steam closed while 7thDroid sets DroidDeck-Proton for its prefix, if that turns out to be needed (it asks).

### Good to know

- **Saves:** FF7 run through 7th Heaven keeps its saves in 7th Heaven's prefix, separate from vanilla FF7 started from Steam.
- **Game files:** 7th Heaven itself writes into the game folder on first run (for the 2026 and GOG releases, `ff7/workingdir` and its own patched `ff7_en.exe`), as it does on Windows. Steam's "Verify integrity of game files" restores the originals.
- **Disc folders you supply are never written to:** 7thDroid maps them as CD drives through small folders of links under `~/.local/share/7thdroid/cd/`.

## Installing

### The easy way: from the DroidDeck app

1. In DroidDeck, open **Desktop > Add an app > GitHub**.
2. Enter `chucklesb/7thDroid`. DroidDeck downloads the newest 7thDroid AppImage from this repository's
   releases and adds a **7thDroid** tile to the Desktop page.
3. Open the tile. 7thDroid asks its questions in on-screen windows: which copy of FF7 to use, which
   7th Heaven build, and which shortcuts to add. A file picker opens in Android's Downloads folder when
   you need to point it at an installer or disc images.
4. Open the tile again whenever you like. Once 7th Heaven is installed it offers a menu:
   **Launch 7th Heaven**, **Update or repair 7th Heaven**, **Add or redo shortcuts**, **Show the last
   log** and **Uninstall 7th Heaven**.

To update 7thDroid itself, update the tile from the Desktop page when a new release is out; your 7th
Heaven install is kept.

Uninstalling removes 7th Heaven's prefix (7th Heaven, its mods, and the FF7 saves made through it), its
launcher, its shortcuts and its downloads. Your FF7 game files are never touched.

### From a terminal

Shared Android storage is mounted `noexec`, so run the script with `bash` from a terminal such as
Konsole on DroidDeck's KDE desktop:

1. Download this repository and unpack it, for example into `/root/Storage/Download/7thDroid`
   (Android's Downloads folder).
2. Run:

```bash
bash /root/Storage/Download/7thDroid/install.sh
```

Then start 7th Heaven from the shortcuts you added, or with `bash ~/.local/share/7thdroid/"7th Heaven.sh"`.
The questions are typed answers there, so the script needs a terminal; on the Desktop page, use the
AppImage instead.

### Options

| Option | |
|---|---|
| `--version pinned\|latest\|canary` | The 7th Heaven build. If you leave it out, the script asks. |
| `--source PATH` | Use this game instead of searching. Repeat it once per disc. |
| `--game-dir DIR` | Where a GOG installer puts the game (default `~/Games/FINAL FANTASY VII`). |
| `--app-entry`, `--steam`, `--desktop` (and `--no-…`) | Add or skip each shortcut without asking. |
| `--shortcuts-only` | Only recreate the launcher and shortcuts, for example after closing Steam. |
| `--uninstall` | Remove 7th Heaven's prefix, launcher, shortcuts and downloads (not the game). |
| `--winetricks-dinput` | Also run winetricks' `dinput` verb, if a Proton build that ships protonfixes is installed (e.g. DroidDeck-Proton). |
| `--reinstall` | Run every step again. |
| `--yes` | Accept every default without asking. |
| `--dry-run` | Show what would run without changing anything. |

The log is written to `~/.local/state/7thdroid/install.log`.

## Troubleshooting

- **The Steam shortcut won't start.** The shortcut is a Linux script. If Steam tries to run it with Proton, open its Properties → Compatibility and turn off the forced compatibility tool.
- **The Steam shortcut wasn't added.** Steam has to be closed while shortcuts are written. Close Steam, then run `bash install.sh --shortcuts-only`.
- **Mods don't load.** Re-run with `--winetricks-dinput` if a Proton with protonfixes is installed, and please report it.
- **An earlier 7thDroid installed into Steam's FF7 prefix.** That prefix is left as it is. If vanilla FF7 misbehaves, delete `~/.local/share/Steam/steamapps/compatdata/39140` (or `3837340`) and Steam recreates it the next time the game starts.
- **Paths to DroidDeck's helpers changed.** Each one can be overridden: `DROIDDECK_BIN` (the folder with DroidDeck's helper scripts), `DROIDDECK_PROTON_RUN`, `DROIDDECK_PROTON_EXTRA`, `DROIDDECK_INNOEXTRACT`, `DROIDDECK_MSITOOLS`, `DROIDDECK_STEAM_SHORTCUTS`, `DROIDDECK_APPS_DIR` and `STEAM_ROOT`.

## Development

The tests run on any Linux machine against a DroidDeck checkout (`DROIDDECK_SRC`), whose own Python helpers decide Proton choices and Steam shortcuts. Stubs replace running Wine and downloading DroidDeck-Proton:

```bash
DROIDDECK_SRC=../DroidDeck bash tests/test_install.sh
```

```bash
DROIDDECK_SRC=../DroidDeck python3 -m unittest discover -s tests
```

```bash
shellcheck -x install.sh menu.sh
```

### Releases

Pushing a tag `vX.Y.Z` that matches the `VERSION` file runs `.github/workflows/release.yml`: it runs
the tests, builds `7thDroid-X.Y.Z-aarch64.AppImage` with `packaging/build-appimage.sh` (7thDroid's
scripts plus a zenity 3.44 bundled with [sharun](https://github.com/VHSgunzo/sharun), following
[pkgforge-dev's Zenity AppImage](https://github.com/pkgforge-dev/Zenity-GTK3-AppImage)), and publishes
it as a release, which is what DroidDeck's **Add an app > GitHub** installs. Without a way to push
tags, run the workflow by hand on `master` instead (**Actions > Release > Run workflow**): it does the
same and creates the tag `v<VERSION>` itself.

For a testing pre-release, set `VERSION` on a branch to a SemVer pre-release (for example `0.2.0-beta.1`)
and run the workflow by hand on that branch. It publishes a pre-release, which DroidDeck's **Add an
app > GitHub** passes over while a normal release is among the 15 newest. Install it by downloading the
AppImage and adding it with **Desktop > Add an app > AppImage**. Delete old pre-releases once the normal
release is out. `master` only publishes normal releases.

A pre-release is built as `7thDroid-Canary-<version>-aarch64.AppImage`, named **7thDroid Canary** and
with a red icon (`packaging/7thdroid-canary.png`), so its tile is told apart from the release's. Both
tiles work on the same 7th Heaven install.

## License

GPL-3.0. See [LICENSE](LICENSE).
