#!/bin/bash
# Compila o Meety (Debug) para rodar aqui. O app fica em build/dd/Build/Products/Debug/Meety.app.
# Registro completo em build/build.log. Opções:
#   --engine   reconstrói o motor Python antes (scripts/build-engine.sh)
#   --loc      exporta as chaves de texto e aplica as traduções (Localization/*.json)
#   --test     roda os testes do MeetyKit depois
set -uo pipefail
cd "$(dirname "$0")/.."
ENGINE=0; LOC=0; TEST=0
for a in "$@"; do case "$a" in --engine) ENGINE=1;; --loc) LOC=1;; --test) TEST=1;; esac; done
mkdir -p build
[[ $ENGINE -eq 1 || ! -d engine/dist/engine ]] && scripts/build-engine.sh
[[ -f Config/Local.xcconfig ]] || echo "aviso: sem Config/Local.xcconfig (copie o .example e preencha o time)"
xcodegen generate >/dev/null
if [[ $LOC -eq 1 ]]; then
  rm -rf build/loc
  for lang in pt-BR; do
    xcodebuild -project Meety.xcodeproj -scheme Meety -exportLocalizations -localizationPath build/loc \
      -exportLanguage "$lang" -derivedDataPath build/dd > build/loc.log 2>&1 || { echo "exportLocalizations falhou (build/loc.log)"; exit 1; }
    python3 scripts/sync-localization.py "$lang"
  done
fi
xcodebuild -project Meety.xcodeproj -scheme Meety -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/dd -skipPackagePluginValidation build > build/build.log 2>&1
status=$?
grep -E "error:" build/build.log | sed -E "s#$PWD/##" | sort -u | head -40
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" build/build.log
if [[ $status -eq 0 && $TEST -eq 1 ]]; then
  (cd MeetyKit && swift test 2>&1 | grep -E "✘|Test run with|error:")
fi
exit $status
