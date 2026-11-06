#!/usr/bin/env python3
"""Sync the picker with the locked codex 0.3.0 sym.txt: PATH [--check]."""
import argparse
import collections
import json
import pathlib
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('catalog', type=pathlib.Path)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
# Explicit scope: mathematical sections, including named variants and default aliases.
sections = {
    'Lowercase Greek.': 'Greek Letters', 'Uppercase Greek.': 'Greek Letters',
    'Relations.': 'Relations', 'Arithmetic.': 'Operators',
    'Calculus.': 'Calculus', 'Logic.': 'Sets & Logic', 'Set theory.': 'Sets & Logic',
    'Arrows, harpoons, and tacks.': 'Arrows', 'Delimiters.': 'Delimiters',
    'Function and category theory.': 'Functions & Categories',
    'Game theory.': 'Other Mathematics', 'Number theory.': 'Other Mathematics',
    'Algebra.': 'Other Mathematics', 'Geometry.': 'Geometry & Shapes',
    'Shapes.': 'Geometry & Shapes', 'Punctuation.': 'Punctuation & Accents',
    'Accents, quotes, and primes.': 'Punctuation & Accents',
    'Hebrew.': 'Letterlike Symbols', 'Double-struck.': 'Letterlike Symbols',
    'Miscellaneous letter-likes.': 'Letterlike Symbols',
    'Lowercase Cyrillic.': 'Letterlike Symbols', 'Uppercase Cyrillic.': 'Letterlike Symbols',
    'Miscellaneous Technical.': 'Other Mathematics',
}
groups = collections.OrderedDict((title, {}) for title in sections.values())
defaults = {}
section = base = ''
deprecated = skip_base = False
for raw in args.catalog.read_text().splitlines():
    if raw.startswith('// ') and raw[3:] in sections:
        section = raw[3:]
    elif raw.startswith('// ') and raw[3:].endswith('.') and raw[3:] not in (
        'In math, the following symbols are replaced with corresponding characters',
        'from Letterlike Symbols.', 'See https://github.com/typst/typst/pull/3375.',
    ):
        section = ''
    line = raw.split('//')[0].strip()
    if not line:
        continue
    if line.startswith('@deprecated:'):
        deprecated = True
        continue
    parts = line.split()
    key = parts[0]
    if not key.startswith('.'):
        base = key
        skip_base = deprecated
    name = base + key if key.startswith('.') else key
    skip = deprecated or skip_base
    deprecated = False
    if section not in sections or skip or len(parts) != 2 or parts[1] == '{':
        continue
    # Power controls and hourglasses are technical icons, not mathematical symbols.
    if base in ('power', 'hourglass', 'zero'):
        continue
    glyph = re.sub(r'\\u\{([0-9A-Fa-f]+)\}', lambda m: chr(int(m[1], 16)), parts[1])
    glyph = re.sub(r'\\vs\{[^}]+\}', '', glyph)
    target = groups[sections[section]]
    rank = key.count('.') if key.startswith('.') else 0
    if rank < defaults.get(base, 999):
        target[base] = glyph
        defaults[base] = rank
    target[name] = glyph
# Radicals are functions, not members of sym.
groups['Calculus'].update({'sqrt': '√', 'root.cube': '∛', 'dif': 'd', 'Dif': 'D'})
lines = ['    // Generated from codex 0.3.0 sym.txt (Typst 0.15.1); see ci/update-math-symbols.py.',
         '    static let all: [Self] = [']
for title, symbols in groups.items():
    entries = ' '.join(f'{glyph}:{name}' for name, glyph in symbols.items())
    lines.append(f'        category({json.dumps(title)}, {json.dumps(entries, ensure_ascii=False)}),')
lines.append('    ]')
generated = '\n'.join(lines)
path = pathlib.Path(__file__).resolve().parents[1] / 'macos/TyPad/Sources/TyPad/MathSymbolPicker.swift'
source = path.read_text()
start = source.find('    // Generated from codex')
if start < 0:
    start = source.index('    static let all: [Self] = [')
end = source.index('\n    ]', start) + len('\n    ]')
if args.check:
    assert source[start:end] == generated, 'Picker differs from locked symbol catalog; run updater'
else:
    path.write_text(source[:start] + generated + source[end:])
print(f'{"PASS" if args.check else "Updated"}: {sum(map(len, groups.values()))} entries in {len(groups)} categories')
