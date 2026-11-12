#!/usr/bin/env python3
"""Checks that every table has the same keys in `en` and `ca`, that no key is repeated
and that every tr("…") in the sources is translated. Run from the repository root."""
import glob
import re
import sys

KEY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)":', re.M)
errors = []
english = set()
used = set()

for path in sorted(glob.glob("Sources/Samune/**/*.swift", recursive=True)):
    source = open(path, encoding="utf-8").read()
    used |= set(re.findall(r'\btr\(\s*"((?:[^"\\]|\\.)*)"', source))
    if "static let en: [String: String]" not in source:
        continue
    start_en = source.index("static let en: [String: String]")
    start_ca = source.index("static let ca: [String: String]")
    en, ca = KEY.findall(source[start_en:start_ca]), KEY.findall(source[start_ca:])
    for name, keys in (("en", en), ("ca", ca)):
        for key in sorted({k for k in keys if keys.count(k) > 1}):
            errors.append(f"{path}: repeated key in {name}: {key}")
    for key in sorted(set(en) ^ set(ca)):
        errors.append(f"{path}: only in one table: {key}")
    for key in sorted(set(en) & english):
        errors.append(f"{path}: key already in another file: {key}")
    english |= set(en)

for key in sorted(used - english):
    errors.append(f"tr() key without translation: {key}")

print("\n".join(errors) if errors else f"Translations OK ({len(english)} keys)")
sys.exit(1 if errors else 0)
