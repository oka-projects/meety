#!/bin/bash
# Publica uma versão do Meety: motor assinado, archive, export Developer ID, DMG, notarização,
# appcast do Sparkle e release no GitHub. Roda só localmente (o certificado não vai para o GitHub).
#
# Uso: scripts/release.sh <versão> [--no-upload]
#
# Pré-requisitos (uma vez):
#   - Certificado "Developer ID Application" no chaveiro (o mesmo do voice desktop).
#   - Perfil de notarização: xcrun notarytool store-credentials meety-notary \
#         --apple-id <apple id> --team-id <team> --password <senha de app>
#   - Chave do Sparkle: build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
#     (grava a privada no chaveiro e imprime a pública; a pública vai em Config/Local.xcconfig,
#     SPARKLE_PUBLIC_ED_KEY=...).
#   - gh autenticado, com acesso ao repositório.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?versão, ex. 1.0.0}"
UPLOAD=1; [[ "${2:-}" == "--no-upload" ]] && UPLOAD=0
REPO="oka-projects/meety"
NOTARY_PROFILE="meety-notary"
OUT="dist/$VERSION"
APP="$OUT/Meety.app"
DMG="$OUT/Meety-$VERSION.dmg"
SPARKLE_BIN=$(ls -d build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1 || true)

echo "==> Motor (assinado para distribuição)"
scripts/build-engine.sh --release

echo "==> Número de build"
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
sed -i '' -E "s/^    MARKETING_VERSION: .*/    MARKETING_VERSION: \"$VERSION\"/; s/^    CURRENT_PROJECT_VERSION: .*/    CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml
xcodegen generate >/dev/null

echo "==> Archive"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -project Meety.xcodeproj -scheme Meety -configuration Release -destination 'platform=macOS' \
  -archivePath "$OUT/Meety.xcarchive" -derivedDataPath build/dd -skipPackagePluginValidation archive > "$OUT/archive.log" 2>&1 \
  || { grep -E "error:" "$OUT/archive.log" | head; exit 1; }

echo "==> Export (Developer ID)"
cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Meety.xcarchive" -exportOptionsPlist "$OUT/export.plist" \
  -exportPath "$OUT" -allowProvisioningUpdates > "$OUT/export.log" 2>&1 || { tail -20 "$OUT/export.log"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2

echo "==> DMG"
STAGE="$OUT/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Meety $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" > /dev/null
codesign --force --sign "Developer ID Application" --timestamp "$DMG"

echo "==> Notarização (pode levar alguns minutos)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -1

echo "==> Appcast (Sparkle)"
if [[ -n "$SPARKLE_BIN" ]]; then
  mkdir -p "$OUT/appcast"
  cp "$DMG" "$OUT/appcast/"
  "$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" "$OUT/appcast/" > /dev/null
  cp "$OUT/appcast/appcast.xml" "$OUT/appcast.xml"
else
  echo "aviso: generate_appcast não encontrado; compile o app uma vez antes"
fi

if [[ $UPLOAD -eq 1 ]]; then
  echo "==> GitHub release v$VERSION"
  NOTES="docs/releases/$VERSION.md"
  [[ -f "$NOTES" ]] || { echo "Meety $VERSION" > "$OUT/notes.md"; NOTES="$OUT/notes.md"; }
  git tag -f "v$VERSION" && git push -f origin "v$VERSION"
  # Meety.dmg é a cópia com nome fixo: o site aponta para releases/latest/download/Meety.dmg
  cp "$DMG" "$OUT/Meety.dmg"
  gh release create "v$VERSION" "$DMG" "$OUT/Meety.dmg" "$OUT/appcast.xml" --repo "$REPO" --title "Meety $VERSION" --notes-file "$NOTES"
fi
echo "pronto: $DMG"
