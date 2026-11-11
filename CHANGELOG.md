# Changelog

All notable changes to 7thDroid are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-11

### Added

- One menu for everything: launch 7th Heaven, launch it with Steam, update or repair, back up,
  restore, show the last log, save logs and uninstall. Every question comes before anything is
  installed.
- **Launch 7th Heaven with Steam** for Steam copies of FF7, so FF7's Steam API and achievements
  work. 7th Heaven's Steam entry is added automatically, and the menu offers it once you have played
  FF7 through 7th Heaven once.
- An installed Steam or GOG game can be copied into 7th Heaven's prefix (`C:\FINAL FANTASY VII`), so
  the original game files are never changed.
- **Back up and restore:** your FF7 saves, 7th Heaven's settings and profiles, FFNx settings and, if
  you want, your mods, as one file in `Documents/7thDroid Backups`. A backup is offered before
  **Update or repair** and before uninstalling, and a restore after a fresh install. Each backup is
  read back right after saving and again before a restore changes anything.
- **Save logs:** DroidDeck's, 7thDroid's, 7th Heaven's and FFNx's logs in one file in
  `Documents/7thDroid Logs`, with tokens, passwords, account names and IDs, emails, Steam IDs and
  network addresses removed.
- A launch log, and the last three install logs are kept.
- FFNx options set at each launch: Direct3D 11 instead of Auto, and Steam Compatibility on only when
  Steam starts 7th Heaven.
- Command-line tasks and options: `--backup`, `--restore`, `--save-logs`, `--update`, `--mods`,
  `--no-mods`, `--no-backup`, `--copy-game` and `--no-copy-game`.

### Changed

- 7th Heaven builds offered: stable and canary only, both on .NET 10.
- 7th Heaven is started from 7thDroid's menu. The DroidDeck app tile, KDE menu entry and shortcut
  choices of earlier versions are removed on update.
- FF7 releases are named as people know them (for example "Steam (2026 release)"), and sizes are
  shown in KB, MB or GB.

### Fixed

- An FFNx too old for 7th Heaven 4.6, which stopped FF7 with "Could not find file
  …FFNx_steam_api.dll", is updated automatically before a launch and during **Update or repair**,
  keeping your FFNx settings.
- A game copied into the prefix is reached through `C:`, so 7th Heaven finds `kernel.bin`.

### Removed

- `install.sh` and `menu.sh`; `7thdroid.sh` does both.

## [0.1.2] - 2026-10-29

### Fixed

- The folder chosen when unpacking a GOG installer, and the .NET check on ARM64 prefixes.

## [0.1.1] - 2026-10-29

### Fixed

- Asks for DroidDeck 0.6.7 or newer instead of failing to find DroidDeck-Proton.

## [0.1.0] - 2026-10-29

### Added

- 7thDroid, a 7th Heaven installer for DroidDeck, replacing 7thDeck. 7th Heaven gets its own
  DroidDeck-Proton prefix, whatever the FF7 source.
- The 7thDroid AppImage, with on-screen windows, a menu and uninstall.

[0.2.0]: https://github.com/chucklesb/7thDroid/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/chucklesb/7thDroid/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/chucklesb/7thDroid/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/chucklesb/7thDroid/releases/tag/v0.1.0
