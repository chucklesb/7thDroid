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
   - For an installed Steam or GOG game, or a game folder you name, it offers to copy the game (3–4 GB) into the prefix and point 7th Heaven at the copy (`C:\FINAL FANTASY VII`), so the original game files are never changed. Without the copy, the game files stay where they are, and 7th Heaven reaches them through Wine's `Z:` drive, which is the whole Linux file system.
   - No other prefix is touched, including the one Steam made for FF7, so vanilla FF7 from Steam keeps working as before.
   - If DroidDeck-Proton isn't your default Proton, 7thDroid sets it for its own prefix only, the same way picking a game's Proton in the DroidDeck app does.
   - It installs the .NET 10 Desktop Runtime that 7th Heaven needs, both x64 and x86, in their newest patch.
   - It turns off WinForms/WPF hardware acceleration, because 7th Heaven's controls vanish without that.
   - It makes Wine prefer 7th Heaven's `dinput.dll`. Without that, mods silently don't load.
3. **Installs 7th Heaven** silently into `C:\7th Heaven` in that prefix, then points it at your game.
   - You choose the build: the newest stable release, or the canary (development) build.
4. **For a Steam copy of FF7, adds 7th Heaven to Steam** as a non-Steam game. That entry is how
   **Launch 7th Heaven with Steam** starts it. If Steam is running during the install, the entry is
   added the first time you choose that instead.

7thDroid asks all its questions first; once it starts preparing the prefix, it runs without stopping
(only a GOG or CD installer that has to run shows its own windows).

Installers run with the FEX settings DroidDeck uses for .NET programs, including full x87 precision.
Without that, the GOG installer stops with "File not fpund". 7thDroid passes these settings through `droiddeck-proton-run --verb run`, so your FEX preset in the DroidDeck app doesn't override them. Your preset is left unchanged, and it still applies when you play.

## Requirements

- DroidDeck 0.6.7 or newer, with Steam set up (open it once and let it finish downloading what it needs). 7thDroid uses the DroidDeck-Proton support that arrived in 0.6.7; on an older DroidDeck it asks you to update first.
- DroidDeck-Proton. If it's missing, 7thDroid offers to install the newest release with DroidDeck's `droiddeck-proton-extra`; that needs about 4 GB free.
- Steam closed while 7thDroid sets DroidDeck-Proton for its prefix, if that turns out to be needed (it asks).

### Good to know

- **Saves:** FF7 run through 7th Heaven keeps its saves in 7th Heaven's prefix, separate from vanilla FF7 started from Steam.
- **Game files:** 7th Heaven itself writes into the game folder on first run (for the 2026 and GOG releases, `ff7/workingdir` and its own patched `ff7_en.exe`), as it does on Windows. With the copy in 7th Heaven's prefix (offered during install), that's the copy, and the original game stays untouched. Without it, Steam's "Verify integrity of game files" restores the originals. The copy is part of the prefix, so uninstalling removes it.
- **Disc folders you supply are never written to:** 7thDroid maps them as CD drives through small folders of links under `~/.local/share/7thdroid/cd/`.
- **Launch from 7thDroid's menu.** Just before each launch, the menu sets two of FFNx's options (7th Heaven's Game Driver settings):
  - **Graphics API:** Direct3D 11 in place of Auto, since it's the most compatible under DroidDeck. A different API you choose in 7th Heaven is kept.
  - **Steam Compatibility:** on for **Launch 7th Heaven with Steam**, off for **Launch 7th Heaven**.

  7th Heaven installs FFNx, with its default settings, the first time you play, so these apply from the second launch on. 7th Heaven also resets them when it updates FFNx, and the menu sets them again on the next launch.
- **FFNx updates:** 7th Heaven 4.6 and newer need FFNx 1.25 or newer, but updating 7th Heaven doesn't update the FFNx already in the game folder. When that FFNx is too old, 7thDroid installs the newest one from 7th Heaven's FFNx update channel, during **Update or repair 7th Heaven** or just before a launch. Your FFNx settings are kept, and the old `FFNx.toml` is saved beside the new one as `FFNx.toml.7thdroid-bak`.
- **Backups:** **Back up 7th Heaven** saves your FF7 saves, 7th Heaven's settings and profiles, your FFNx settings and controls, and, if you want, your mods, as one `.tar` file in Android's Documents folder (`Documents/7thDroid Backups`). That folder outlives uninstalling 7th Heaven and reinstalling DroidDeck, and you can copy it to a PC.
  - 7thDroid also offers a backup before **Update or repair** and before uninstalling, and offers to restore one after a fresh install.
  - **Restore a backup** puts everything back into the current install, keeping its game and mod-library locations. Saves from a different FF7 release are left out unless you ask for them, since they don't always carry over.
  - FFNx settings restored before FFNx is installed apply after your first play, like 7thDroid's other FFNx settings.
  - Backups are never deleted automatically; remove old ones in Android's Documents folder.
- **Logs:** **Save logs** (in the menu even before 7th Heaven is installed) gathers, in one `.tar` in `Documents/7thDroid Logs`:
  - DroidDeck's session logs (it keeps the last three sessions, desktop and Steam alike), and its recent tool and store logs;
  - 7thDroid's install logs (the last three runs) and launch logs (the last two launches);
  - 7th Heaven's `applog.txt`, its settings and its installer log;
  - `FFNx.log`, `FFNx.toml` and `AppLoader.log` from the game folder;
  - an `info.txt` with the versions and setup.

  Every file goes through the same redaction as DroidDeck's own Share logs. It removes tokens, passwords, Steam Guard codes, account names, emails, Steam IDs, device serials and network addresses, and leaves out binary files. Still, look through it before you share it. The launch log needs a launcher written by this version: run **Update or repair** once after updating 7thDroid.
- **Steam achievements (Steam copies only):** choose **Launch 7th Heaven with Steam**. The menu offers it once you've played FF7 through 7th Heaven once, because FFNx, which carries the Steam Compatibility setting, is installed at that first play. 7th Heaven starts as FF7's Steam app (39140 or 3837340) through its entry in Steam, so FF7 can use the Steam API. Starting that entry from Steam's library works too, but only the menu sets Steam Compatibility for you. Steam Cloud doesn't sync these saves, because they're kept in 7th Heaven's prefix.

## Installing

### The easy way: from the DroidDeck app

1. In DroidDeck, open **Desktop > Add an app > GitHub**.
2. Enter `chucklesb/7thDroid`. DroidDeck downloads the newest 7thDroid AppImage from this repository's
   releases and adds a **7thDroid** tile to the Desktop page.
3. Open the tile. Its menu offers **Install 7th Heaven**. 7thDroid first shows its warning, then asks
   its questions in on-screen windows: which copy of FF7 to use, which 7th Heaven build, and whether to
   copy the game into 7th Heaven's prefix. A file picker opens in Android's Downloads folder when you
   need to point it at an installer or disc images.
4. When it's done, the menu comes back with everything else: **Launch 7th Heaven**,
   **Launch 7th Heaven with Steam** (Steam copies of FF7 only), **Update or repair 7th Heaven**,
   **Back up 7th Heaven**, **Restore a backup**, **Show the last log**, **Save logs** and
   **Uninstall 7th Heaven**. Each task returns to the menu when it finishes.
   The 7thDroid tile is how you start 7th Heaven: 7thDroid adds no tile or menu entry of its own.

To update 7thDroid itself, update the tile from the Desktop page when a new release is out; your 7th
Heaven install is kept.

Uninstalling removes 7th Heaven's prefix (7th Heaven, its mods, the FF7 saves made through it, and the
game copy if you made one), its launcher, its Steam entry and its downloads. Your original FF7 game files
are never touched. It offers to back up first, and its backups are kept.

### From a terminal

Shared Android storage is mounted `noexec`, so run the script with `bash` from a terminal such as
Konsole on DroidDeck's KDE desktop:

1. Download this repository and unpack it, for example into `/root/Storage/Download/7thDroid`
   (Android's Downloads folder).
2. Run:

```bash
bash /root/Storage/Download/7thDroid/7thdroid.sh
```

It shows the same menu, with typed answers. Start 7th Heaven from that menu too.
The questions are typed answers there, so the script needs a terminal; on the Desktop page, use the
AppImage instead.

### Options

Without a task option the script shows its menu. A task option runs that task on its own instead:

| Option | |
|---|---|
| `--install` | Install 7th Heaven, or update or repair it. `--yes` on its own implies it. |
| `--steam-shortcut` | Only add 7th Heaven's Steam entry, for example after closing Steam. |
| `--backup` | Back up the saves, 7th Heaven's settings and profiles, FFNx settings and (asked) the mods. |
| `--restore [FILE]` | Restore a backup; without FILE, the script asks which. |
| `--save-logs` | Save every log, redacted, to `Documents/7thDroid Logs`. |
| `--uninstall` | Remove 7th Heaven's prefix, launcher, Steam entry and downloads (not the original game). |
| `--version stable\|canary` | The 7th Heaven build. If you leave it out, the script asks. |
| `--source PATH` | Use this game instead of searching. Repeat it once per disc. |
| `--game-dir DIR` | Where a GOG installer puts the game (default `~/Games/FINAL FANTASY VII`). |
| `--copy-game`, `--no-copy-game` | Copy the game into 7th Heaven's prefix, or use it where it is, without asking. |
| `--mods`, `--no-mods` | Include the mods in a backup, or leave them out, without asking. |
| `--no-backup` | Don't offer a backup before updating or uninstalling, or a restore after a fresh install. |
| `--winetricks-dinput` | Also run winetricks' `dinput` verb, if a Proton build that ships protonfixes is installed (e.g. DroidDeck-Proton). |
| `--reinstall` | Run every step again. |
| `--yes` | Accept every default without asking. |
| `--dry-run` | Show what would run without changing anything. |

The log is written to `~/.local/state/7thdroid/install.log`.

## Troubleshooting

To report a problem, choose **Save logs** in 7thDroid's menu and attach the file it saves in `Documents/7thDroid Logs`.

- **Launch with Steam doesn't start.** 7th Heaven's Steam entry is a Linux script. If Steam tries to run it with Proton, open its Properties → Compatibility and turn off the forced compatibility tool.
- **The Steam entry wasn't added.** Steam has to be closed while it's written. Choose **Launch 7th Heaven with Steam**, and 7thDroid offers to add it once Steam is closed.
- **FF7 says "Steam must be running".** Steam Compatibility is on, which happens when 7th Heaven was last started with Steam, or from its entry in Steam's library. Start it from 7thDroid's menu, which sets it for the way you launch.
- **Achievements don't unlock.** They need a Steam copy of FF7, **Launch 7th Heaven with Steam**, and Steam online. On the very first play, FFNx is still being installed, so start the game a second time. If you installed with an earlier 7thDroid, run **Update or repair 7th Heaven** once so the launcher reports FF7's app id to Steam.
- **"Could not find file '…\FFNx_steam_api.dll'" when launching the game.** The game folder still has an FFNx older than 1.25, installed by an earlier 7th Heaven, and 7th Heaven 4.6 refuses to start FF7 with it. Start 7th Heaven from 7thDroid's menu, or run **Update or repair 7th Heaven**, and 7thDroid updates FFNx first. You can also update it in 7th Heaven: **Settings > General Settings**, the FFNx **Check for Updates** button, then **Yes** (that resets your FFNx settings).
- **Mods don't load.** Re-run with `--winetricks-dinput` if a Proton with protonfixes is installed, and please report it.
- **An earlier 7thDroid installed into Steam's FF7 prefix.** That prefix is left as it is. If vanilla FF7 misbehaves, delete `~/.local/share/Steam/steamapps/compatdata/39140` (or `3837340`) and Steam recreates it the next time the game starts.
- **Paths to DroidDeck's helpers changed.** Each one can be overridden: `DROIDDECK_BIN` (the folder with DroidDeck's helper scripts), `DROIDDECK_PROTON_RUN`, `DROIDDECK_PROTON_EXTRA`, `DROIDDECK_INNOEXTRACT`, `DROIDDECK_MSITOOLS`, `DROIDDECK_STEAM_SHORTCUTS`, `DROIDDECK_STEAM_LAUNCH`, `DROIDDECK_APPS_DIR` (where earlier versions' tiles are removed from) and `STEAM_ROOT`.

## Development

The tests run on any Linux machine against a DroidDeck checkout (`DROIDDECK_SRC`), whose own Python helpers decide Proton choices and Steam shortcuts. Stubs replace running Wine and downloading DroidDeck-Proton:

```bash
DROIDDECK_SRC=../DroidDeck bash tests/test_install.sh
```

```bash
DROIDDECK_SRC=../DroidDeck python3 -m unittest discover -s tests
```

```bash
shellcheck -x 7thdroid.sh
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
and run the workflow by hand on that branch. To test several feature or fix branches together, build
them on a `canary` branch: start it from `master`, merge each branch in, and commit the pre-release
`VERSION` on top, so the feature branches themselves never carry it. For the next beta, rebuild
`canary` the same way and raise the number. It publishes a pre-release, which DroidDeck's **Add an
app > GitHub** passes over while a normal release is among the 15 newest. Install it by downloading the
AppImage and adding it with **Desktop > Add an app > AppImage**. Delete old pre-releases once the normal
release is out. `master` only publishes normal releases.

A pre-release is built as `7thDroid-Canary-<version>-aarch64.AppImage`, named **7thDroid Canary** and
with a red icon (`packaging/7thdroid-canary.png`), so its tile is told apart from the release's. Both
tiles work on the same 7th Heaven install.

Release notes: a normal release uses its `## [X.Y.Z]` section of `CHANGELOG.md` ([Keep a
Changelog](https://keepachangelog.com/) format), and the workflow stops if that section is missing. A
pre-release lists the commit subjects since the last normal release, leaving out merges and `VERSION`
bumps.

## License

GPL-3.0. See [LICENSE](LICENSE).
