#!/bin/sh
# Builds 7thDroid-<version>-<arch>.AppImage in dist/: 7thDroid's scripts plus a zenity 3.44 (GTK 3)
# bundled with sharun. Runs in ghcr.io/pkgforge-dev/archlinux after pkgforge-dev/anylinux-setup-action,
# following pkgforge-dev/Zenity-GTK3-AppImage. A pre-release VERSION (X.Y.Z-beta.1) builds
# 7thDroid-Canary-<version>-<arch>.AppImage instead.
set -eu

ARCH=$(uname -m)
VERSION=$(cat VERSION)
ZENITY_BRANCH=zenity-3-44

# DroidDeck installs a pre-release as a tile beside the GitHub release, so it is named "7thDroid
# Canary" and gets a red icon. DroidDeck takes a tile's icon from the largest <Icon>.png anywhere in
# the AppImage, and assets/7th-heaven.png is in there too, so the red one needs a name of its own.
case $VERSION in
  *-*)
    APP_TITLE="7thDroid Canary" ICON_NAME=7thdroid-canary
    OUTNAME="7thDroid-Canary-$VERSION-$ARCH.AppImage"
    mkdir -p /tmp/canary
    sed -e "s/^Name=.*/Name=$APP_TITLE/" -e "s/^Icon=.*/Icon=$ICON_NAME/" \
      -e 's/^Comment=.*/Comment=Testing build of 7thDroid, the 7th Heaven installer for DroidDeck/' \
      packaging/7thDroid.desktop > /tmp/canary/7thDroid.desktop
    DESKTOP=/tmp/canary/7thDroid.desktop ICON="$PWD/packaging/$ICON_NAME.png" ;;
  *)
    APP_TITLE=7thDroid ICON_NAME=7th-heaven
    OUTNAME="7thDroid-$VERSION-$ARCH.AppImage"
    DESKTOP="$PWD/packaging/7thDroid.desktop" ICON="$PWD/assets/$ICON_NAME.png" ;;
esac

pacman -Syu --noconfirm base-devel git itstool libxtst meson xorg-server-xvfb
get-debloated-pkgs gtk3-mini libxml2-mini glycin-mini

rm -rf /tmp/zenity
git clone --depth 1 --branch "$ZENITY_BRANCH" https://gitlab.gnome.org/GNOME/zenity.git /tmp/zenity
meson setup /tmp/zenity/build /tmp/zenity --buildtype=release --prefix=/usr
meson compile -C /tmp/zenity/build
meson install --no-rebuild -C /tmp/zenity/build

export ARCH
export OUTPATH=./dist
export OUTNAME DESKTOP ICON
export MAIN_BIN=zenity
export URUNTIME_PRELOAD=1
# Software rendering only: dialogs draw the same everywhere, gamescope included.
export ALWAYS_SOFTWARE=1

quick-sharun /usr/bin/zenity

mkdir -p AppDir/share/7thdroid
cp -r install.sh menu.sh lib assets LICENSE README.md VERSION AppDir/share/7thdroid/
# Our AppRun replaces sharun's, so sharun's environment is applied to zenity only.
rm -f AppDir/AppRun
cp packaging/AppRun AppDir/AppRun
cp packaging/zenity AppDir/7thdroid-zenity
chmod +x AppDir/AppRun AppDir/7thdroid-zenity AppDir/share/7thdroid/install.sh AppDir/share/7thdroid/menu.sh

quick-sharun --make-appimage

# Smoke test: unpack the AppImage as DroidDeck does, then run its zenity and scripts.
rm -rf /tmp/check
mkdir -p /tmp/check
cp dist/"$OUTNAME" /tmp/check/
(
  cd /tmp/check
  ./"$OUTNAME" --appimage-extract >/dev/null
  # squashfs-root can be a link to the unpacked folder; DroidDeck resolves it the same way.
  if [ -d squashfs-root ]; then root=$(readlink -f squashfs-root); else root=$PWD/AppDir; fi
  head -n 1 "$root/AppRun" | grep -qx '#!/bin/bash'
  # The tile's name and icon, found the way DroidDeck finds them.
  grep -qx "Name=$APP_TITLE" "$root"/*.desktop || { echo "the AppImage is not named $APP_TITLE" >&2; exit 1; }
  find "$root" -maxdepth 8 -name "$ICON_NAME.png" | grep -q . || { echo "no $ICON_NAME.png in the AppImage" >&2; exit 1; }
  status=0
  APPDIR=$root xvfb-run -a "$root/7thdroid-zenity" --info --text=7thDroid --timeout=2 || status=$?
  [ "$status" -eq 5 ] || { echo "zenity did not open a window (exit $status)" >&2; exit 1; }
  bash "$root/share/7thdroid/install.sh" --help >/dev/null
)
echo "Built dist/$OUTNAME"
