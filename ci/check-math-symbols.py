#!/usr/bin/env python3
"""Compile every picker command in math; requires the Typst CLI."""
import json
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'macos/TyPad/Sources/TyPad/MathSymbolPicker.swift').read_text()
tables = re.findall(r'category\("[^"]+", ("(?:[^"\\]|\\.)*")\)', source)
entries = [tuple(entry.rsplit(":", 1)) for table in tables for entry in json.loads(table).split()]
assert len(entries) > 1000, len(entries)
assert len({name for _, name in entries}) == len(entries)
overrides = dict(re.findall(r'case "([\w.]+)": return "([^"]+)"', source))
assert "default: return name" in source
lines = []
for glyph, name in entries:
    command = overrides.get(name, name)
    assert "#" not in command and ";" not in command, command
    if name not in overrides and name not in ("dif", "Dif"):
        # Some symbols carry a text-presentation variation selector.
        lines.append(f'#assert(str(sym.{name}).replace(regex("[\\u{{fe00}}-\\u{{fe0f}}]"), "") == {json.dumps(glyph, ensure_ascii=False)})')
    lines.append(f'$ x {command} y $')
with tempfile.TemporaryDirectory(prefix='typad-symbols-') as folder:
    path = pathlib.Path(folder) / 'symbols.typ'
    path.write_text('\n\n'.join(lines))
    subprocess.run(['typst', 'compile', str(path), str(path.with_suffix('.pdf'))], check=True)
print(f'PASS: {len(entries)} formula commands and symbol mappings; no prefixes or semicolons')
