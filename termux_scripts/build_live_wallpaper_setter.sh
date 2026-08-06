#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:/system/bin:$PATH"

WORK="$HOME/live_wallpaper_setter_build"
rm -rf "$WORK"
mkdir -p "$WORK/bin"
cp "$HOME/LiveWallpaperSetter.java" "$WORK/"
cd "$WORK"

ecj -d bin -bootclasspath /system/framework/framework-res.apk LiveWallpaperSetter.java
dx --dex --output=classes.dex bin
jar cf LiveWallpaperSetter.jar classes.dex
echo "$WORK/LiveWallpaperSetter.jar"
