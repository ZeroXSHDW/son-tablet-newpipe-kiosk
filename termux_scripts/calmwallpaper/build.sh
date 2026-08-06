#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:/system/bin:$PATH"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

FRAMEWORK=/system/framework/framework-res.apk
rm -rf bin gen compiled_resources.zip classes.dex calmwallpaper-unsigned.apk calmwallpaper-aligned.apk calmwallpaper-signed.apk
mkdir -p bin gen

aapt2 compile --dir res -o compiled_resources.zip
aapt2 link -o calmwallpaper-unsigned.apk -I "$FRAMEWORK" -0 arsc \
    --manifest AndroidManifest.xml --java gen compiled_resources.zip

ecj -d bin -bootclasspath "$FRAMEWORK" \
    src/com/android/calmwallpaper/CalmWallpaperService.java \
    gen/com/android/calmwallpaper/R.java

dx --dex --output=classes.dex bin
jar uf calmwallpaper-unsigned.apk classes.dex
zipalign -f 4 calmwallpaper-unsigned.apk calmwallpaper-aligned.apk

KEYSTORE="../kioskbooter/debug.keystore"
[ -f "$KEYSTORE" ] || {
    keytool -genkeypair -keystore "$KEYSTORE" -storepass android \
        -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
        -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
}

apksigner sign --ks "$KEYSTORE" --ks-pass pass:android \
    --out calmwallpaper-signed.apk calmwallpaper-aligned.apk
apksigner verify --verbose calmwallpaper-signed.apk
echo "Built: $DIR/calmwallpaper-signed.apk"
