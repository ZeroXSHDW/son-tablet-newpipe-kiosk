#!/data/data/com.termux/files/usr/bin/bash
set -e

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:/system/bin:$PATH"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Building com.android.kioskbooter APK..."

# Clean previous builds
rm -rf bin compiled-res.zip classes.dex kioskbooter.apk kioskbooter-aligned.apk kioskbooter-signed.apk
mkdir -p bin

# 1. Compile accessibility-service resources and package the manifest
echo "Packaging resources..."
aapt2 compile --dir res -o compiled-res.zip
aapt2 link -o kioskbooter.apk -I /system/framework/framework-res.apk -0 arsc \
    --manifest AndroidManifest.xml compiled-res.zip

# 2. Compile Java code
echo "Compiling Java sources..."
ecj -d bin -bootclasspath /system/framework/framework-res.apk \
    src/com/android/kioskbooter/BootReceiver.java \
    src/com/android/kioskbooter/InputBlockerService.java

# 3. Dex compilation
echo "Converting class files to Dex..."
dx --dex --output=classes.dex bin

# 4. Add classes.dex to the APK
echo "Adding classes.dex to APK..."
jar uf kioskbooter.apk classes.dex
zipalign -f 4 kioskbooter.apk kioskbooter-aligned.apk

# 5. Generate debug keystore if not exists
if [ ! -f debug.keystore ]; then
    echo "Generating debug keystore..."
    keytool -genkey -v -keystore debug.keystore -storepass android -alias androiddebugkey \
        -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
fi

# 6. Sign the APK
echo "Signing APK..."
apksigner sign --ks debug.keystore --ks-pass pass:android --out kioskbooter-signed.apk kioskbooter-aligned.apk

echo "APK Build Complete: kioskbooter-signed.apk"
