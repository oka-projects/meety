#!/usr/bin/env python3
"""Preenche os catálogos de strings (Localizable.xcstrings) com as traduções de Localization/<idioma>.json.

1. Exporta as chaves do projeto: xcodebuild -exportLocalizations (o build-mac.sh faz isso com --loc).
2. Lê build/loc/<idioma>.xcloc/Localized Contents/<idioma>.xliff para saber que chave pertence a que catálogo.
3. Grava cada catálogo com o texto traduzido. Chave sem tradução fica em inglês e é listada no fim.

Uso: scripts/sync-localization.py [pt-BR]
"""
import glob, json, sys, xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
lang = sys.argv[1] if len(sys.argv) > 1 else "pt-BR"
translations = json.load(open(ROOT / "Localization" / f"{lang}.json", encoding="utf-8"))
ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}

xliffs = glob.glob(str(ROOT / "build/loc" / f"{lang}.xcloc" / "Localized Contents" / "*.xliff"))
if not xliffs:
    sys.exit("exporte as chaves antes: xcodebuild -exportLocalizations -localizationPath build/loc -exportLanguage " + lang)

missing = set()
for xliff in xliffs:
    root = ET.parse(xliff).getroot()
    for f in root.findall("x:file", ns):
        catalog = ROOT / f.get("original")
        if catalog.suffix != ".xcstrings":
            continue
        data = json.load(open(catalog, encoding="utf-8")) if catalog.exists() else {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
        strings = data.setdefault("strings", {})
        for unit in f.findall(".//x:trans-unit", ns):
            key = unit.find("x:source", ns).text
            if key is None:
                continue
            # A entrada do catálogo é o id da unidade: no InfoPlist é a chave do plist (CFBundleName...);
            # nos outros é o texto, e textos com dois argumentos aparecem duas vezes ("%@ ... %@" e
            # "%1$@ ... %2$@", este último como source do primeiro). A tradução vale para as duas formas.
            entry = strings.setdefault(unit.get("id") or key, {})
            value = translations.get(key) or translations.get(unit.get("id") or "")
            if value is None:
                missing.add(key)
                continue
            entry.setdefault("localizations", {})[lang] = {"stringUnit": {"state": "translated", "value": value}}
        json.dump(data, open(catalog, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)
        open(catalog, "a").write("\n")
        print(f"{catalog.relative_to(ROOT)}: {len(strings)} chaves")

if missing:
    print("\nSem tradução:")
    for k in sorted(missing):
        print("  " + repr(k))
