---
name: finish-translation
description: "Propagate new/changed translations to all target languages, audit for missing keys, and find hardcoded strings. Auto-detects the i18n framework (ARB/Flutter, JSON/i18next, .strings/Apple, .xcstrings, gettext .po, YAML/Rails, Android XML). Use this skill when the user says /finish-translation, 'internationalization', 'i18n', 'l10n', 'finish translation', 'translate strings', 'translate new strings', 'sync translations', 'fill missing translations', 'missing translations', 'translation audit', 'find hardcoded strings', or any variation requesting translation propagation, i18n auditing, or localization work."
---

# Finish Translation

Detect the project's i18n framework, find missing/new translation keys, translate them naturally into all target languages, and validate the result.

## User Request

$ARGUMENTS

---

## Phase 0: Detect i18n Framework

Auto-detect the i18n setup by scanning the project. Check in this order — use the **first match**:

| Priority | Signal | Framework | Source Format |
|----------|--------|-----------|---------------|
| 1 | `l10n.yaml` or `lib/l10n/*.arb` | Flutter ARB | `.arb` (JSON with `@` metadata) |
| 2 | `*.xcstrings` in project | Apple Xcode String Catalogs | `.xcstrings` |
| 3 | `*.lproj/Localizable.strings` | Apple .strings | `.strings` key-value |
| 4 | `res/values*/strings.xml` | Android XML | `strings.xml` |
| 5 | `i18next` in package.json or `locales/**/*.json` | i18next JSON | nested `.json` |
| 6 | `next-intl` or `next-i18next` in package.json | Next.js i18n | `.json` |
| 7 | `react-intl` in package.json or `src/**/*.messages.*` | React Intl | `.json` or extracted |
| 8 | `vue-i18n` in package.json | Vue i18n | `.json` or `.yaml` |
| 9 | `config/locales/*.yml` | Rails i18n | `.yml` |
| 10 | `locale/**/*.po` or `*.pot` files | gettext | `.po` / `.pot` |
| 11 | `**/*.resx` | .NET Resources | `.resx` XML |
| 12 | `**/*.properties` with locale suffixes | Java Properties | `.properties` |

### Detection Script

```bash
# Quick framework detection
echo "=== i18n Framework Detection ==="
[ -f l10n.yaml ] && echo "FOUND: l10n.yaml (Flutter ARB)"
find . -maxdepth 5 -name "*.arb" 2>/dev/null | head -3
find . -maxdepth 5 -name "*.xcstrings" 2>/dev/null | head -3
find . -maxdepth 5 -name "Localizable.strings" 2>/dev/null | head -3
find . -maxdepth 5 -name "strings.xml" -path "*/values*" 2>/dev/null | head -3
[ -f package.json ] && grep -l "i18next\|next-intl\|next-i18next\|react-intl\|vue-i18n" package.json 2>/dev/null
find . -maxdepth 5 -name "*.po" -o -name "*.pot" 2>/dev/null | head -3
find . -maxdepth 5 -name "*.yml" -path "*/locales/*" 2>/dev/null | head -3
find . -maxdepth 5 -name "*.resx" 2>/dev/null | head -3
find . -maxdepth 5 -name "*.properties" 2>/dev/null | grep -E '_[a-z]{2}(_[A-Z]{2})?\.properties' | head -3
```

After detection, set these variables for subsequent phases:

- **`FORMAT`**: The file format (arb, json, xcstrings, strings, xml, yaml, po, resx, properties)
- **`SOURCE_FILE`**: Path to the source/template language file
- **`TARGET_FILES`**: List of target language files
- **`SOURCE_LANG`**: Source language code (usually `en`)
- **`GEN_COMMAND`**: Code generation command if applicable (`flutter gen-l10n`, `npx i18next`, etc.), or empty
- **`LINT_COMMAND`**: Lint/analyze command if applicable (`flutter analyze`, `npx eslint`, etc.), or empty

If detection fails, ask the user to specify the format and paths.

---

## Phase 1: Audit Current State

Always run this phase first regardless of mode.

### 1.1 Parse and Compare Keys

Use the appropriate parser based on `FORMAT`:

#### For ARB (Flutter)

```bash
python3 -c "
import json, glob, os

# Find source file
source = None
for f in glob.glob('**/app_en.arb', recursive=True):
    source = f; break
if not source:
    for f in glob.glob('**/*_en.arb', recursive=True):
        source = f; break
if not source:
    print('ERROR: No English ARB source file found'); exit(1)

base_dir = os.path.dirname(source)
with open(source) as f:
    en = json.load(f)

en_keys = sorted(k for k in en if not k.startswith('@'))
print(f'Source: {source} ({len(en_keys)} keys)')

en_set = set(en_keys)
total_missing = 0
for fn in sorted(glob.glob(os.path.join(base_dir, '*.arb'))):
    if fn == source: continue
    with open(fn) as f:
        lang = json.load(f)
    lang_keys = set(k for k in lang if not k.startswith('@'))
    missing = sorted(en_set - lang_keys)
    extra = sorted(lang_keys - en_set)
    total_missing += len(missing)
    name = os.path.basename(fn)
    status = 'OK' if not missing and not extra else f'{len(missing)} missing, {len(extra)} extra'
    print(f'{name}: {len(lang_keys)} keys [{status}]')
    if missing:
        for m in missing[:10]:
            val = en[m]
            if len(str(val)) > 60: val = str(val)[:60] + '...'
            print(f'  MISSING: {m} = \"{val}\"')
        if len(missing) > 10:
            print(f'  ... and {len(missing) - 10} more')
print(f'\nTotal missing across all files: {total_missing}')
"
```

#### For JSON (i18next, Next.js, Vue i18n, React Intl)

```bash
python3 -c "
import json, glob, os

# Find locales directory
locale_dirs = ['locales', 'locale', 'i18n', 'lang', 'languages', 'translations',
               'src/locales', 'src/i18n', 'public/locales', 'src/translations']
base_dir = None
for d in locale_dirs:
    if os.path.isdir(d):
        base_dir = d; break

if not base_dir:
    # Try directory-per-locale pattern: locales/en/common.json
    for d in locale_dirs:
        en_dir = os.path.join(d, 'en')
        if os.path.isdir(en_dir):
            base_dir = d; break

if not base_dir:
    print('ERROR: No locales directory found'); exit(1)

def flatten(obj, prefix=''):
    items = {}
    for k, v in obj.items():
        key = f'{prefix}.{k}' if prefix else k
        if isinstance(v, dict):
            items.update(flatten(v, key))
        else:
            items[key] = v
    return items

# Detect pattern: flat files (en.json) vs directory-per-locale (en/common.json)
en_file = os.path.join(base_dir, 'en.json')
en_dir = os.path.join(base_dir, 'en')

if os.path.isfile(en_file):
    # Flat file pattern
    with open(en_file) as f:
        en = flatten(json.load(f))
    en_keys = set(en.keys())
    print(f'Source: {en_file} ({len(en_keys)} keys)')
    for fn in sorted(glob.glob(os.path.join(base_dir, '*.json'))):
        if fn == en_file: continue
        with open(fn) as f:
            lang = flatten(json.load(f))
        lang_keys = set(lang.keys())
        missing = sorted(en_keys - lang_keys)
        extra = sorted(lang_keys - en_keys)
        name = os.path.basename(fn)
        status = 'OK' if not missing and not extra else f'{len(missing)} missing, {len(extra)} extra'
        print(f'{name}: {len(lang_keys)} keys [{status}]')
        for m in missing[:10]:
            val = en[m]
            if len(str(val)) > 60: val = str(val)[:60] + '...'
            print(f'  MISSING: {m} = \"{val}\"')
elif os.path.isdir(en_dir):
    # Directory-per-locale pattern
    namespaces = {}
    for fn in sorted(glob.glob(os.path.join(en_dir, '*.json'))):
        ns = os.path.splitext(os.path.basename(fn))[0]
        with open(fn) as f:
            namespaces[ns] = flatten(json.load(f))
    en_keys = {f'{ns}.{k}' for ns, keys in namespaces.items() for k in keys}
    print(f'Source: {en_dir}/ ({len(en_keys)} keys across {len(namespaces)} namespace(s))')
    for lang_dir in sorted(glob.glob(os.path.join(base_dir, '*/'))):
        if lang_dir.rstrip('/') == en_dir: continue
        lang_keys = set()
        for fn in glob.glob(os.path.join(lang_dir, '*.json')):
            ns = os.path.splitext(os.path.basename(fn))[0]
            with open(fn) as f:
                lang_keys.update(f'{ns}.{k}' for k in flatten(json.load(f)))
        missing = sorted(en_keys - lang_keys)
        name = os.path.basename(lang_dir.rstrip('/'))
        status = 'OK' if not missing else f'{len(missing)} missing'
        print(f'{name}: {len(lang_keys)} keys [{status}]')
        for m in missing[:10]:
            print(f'  MISSING: {m}')
"
```

#### For Apple .strings

```bash
python3 -c "
import re, glob, os

def parse_strings(path):
    keys = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = re.match(r'\"(.+?)\"\s*=\s*\"(.+?)\"\s*;', line)
            if m:
                keys[m.group(1)] = m.group(2)
    return keys

# Find English source
en_files = glob.glob('**/en.lproj/Localizable.strings', recursive=True) or \
           glob.glob('**/Base.lproj/Localizable.strings', recursive=True)
if not en_files:
    print('ERROR: No English .strings file found'); exit(1)

source = en_files[0]
en = parse_strings(source)
en_keys = set(en.keys())
base_dir = os.path.dirname(os.path.dirname(source))
print(f'Source: {source} ({len(en_keys)} keys)')

for lproj in sorted(glob.glob(os.path.join(base_dir, '*.lproj'))):
    name = os.path.basename(lproj)
    if name in ('en.lproj', 'Base.lproj'): continue
    strings_file = os.path.join(lproj, 'Localizable.strings')
    if not os.path.exists(strings_file): continue
    lang = parse_strings(strings_file)
    lang_keys = set(lang.keys())
    missing = sorted(en_keys - lang_keys)
    status = 'OK' if not missing else f'{len(missing)} missing'
    print(f'{name}: {len(lang_keys)} keys [{status}]')
    for m in missing[:10]:
        val = en[m]
        if len(str(val)) > 60: val = str(val)[:60] + '...'
        print(f'  MISSING: {m} = \"{val}\"')
"
```

#### For Apple .xcstrings (Xcode String Catalogs)

```bash
python3 -c "
import json, glob

files = glob.glob('**/*.xcstrings', recursive=True)
if not files:
    print('ERROR: No .xcstrings files found'); exit(1)

for path in files:
    with open(path) as f:
        catalog = json.load(f)
    source_lang = catalog.get('sourceLanguage', 'en')
    strings = catalog.get('strings', {})
    # Collect all languages
    all_langs = set()
    for key, entry in strings.items():
        for lang in entry.get('localizations', {}):
            all_langs.add(lang)
    all_langs.discard(source_lang)
    print(f'Source: {path} ({len(strings)} keys, source={source_lang})')
    print(f'Target languages: {sorted(all_langs)}')
    for lang in sorted(all_langs):
        missing = []
        for key, entry in strings.items():
            locs = entry.get('localizations', {})
            if lang not in locs:
                missing.append(key)
        status = 'OK' if not missing else f'{len(missing)} missing'
        print(f'  {lang}: {len(strings) - len(missing)} translated [{status}]')
        for m in missing[:10]:
            print(f'    MISSING: {m}')
        if len(missing) > 10:
            print(f'    ... and {len(missing) - 10} more')
"
```

#### For Android strings.xml

```bash
python3 -c "
import xml.etree.ElementTree as ET
import glob, os

# Find default (English) strings
default_files = glob.glob('**/res/values/strings.xml', recursive=True)
if not default_files:
    print('ERROR: No default strings.xml found'); exit(1)

source = default_files[0]
tree = ET.parse(source)
en_keys = {elem.get('name') for elem in tree.findall('.//string')}
print(f'Source: {source} ({len(en_keys)} keys)')

res_dir = os.path.dirname(os.path.dirname(source))
for values_dir in sorted(glob.glob(os.path.join(res_dir, 'values-*'))):
    strings_file = os.path.join(values_dir, 'strings.xml')
    if not os.path.exists(strings_file): continue
    tree = ET.parse(strings_file)
    lang_keys = {elem.get('name') for elem in tree.findall('.//string')}
    missing = sorted(en_keys - lang_keys)
    name = os.path.basename(values_dir)
    status = 'OK' if not missing else f'{len(missing)} missing'
    print(f'{name}: {len(lang_keys)} keys [{status}]')
    for m in missing[:10]:
        print(f'  MISSING: {m}')
"
```

#### For gettext (.po/.pot)

```bash
python3 -c "
import re, glob, os

def parse_po(path):
    keys = set()
    with open(path, encoding='utf-8') as f:
        content = f.read()
    for m in re.finditer(r'msgid \"(.+?)\"', content):
        keys.add(m.group(1))
    return keys

def count_untranslated(path):
    with open(path, encoding='utf-8') as f:
        content = f.read()
    entries = re.findall(r'msgid \"(.+?)\"\s*\nmsgstr \"(.*?)\"', content)
    untranslated = [(msgid, msgstr) for msgid, msgstr in entries if not msgstr]
    return entries, untranslated

pot_files = glob.glob('**/*.pot', recursive=True)
po_files = glob.glob('**/*.po', recursive=True)

if pot_files:
    source = pot_files[0]
    template_keys = parse_po(source)
    print(f'Template: {source} ({len(template_keys)} keys)')

for po in sorted(po_files):
    entries, untranslated = count_untranslated(po)
    status = 'OK' if not untranslated else f'{len(untranslated)} untranslated'
    print(f'{po}: {len(entries)} entries [{status}]')
    for msgid, _ in untranslated[:10]:
        if len(msgid) > 60: msgid = msgid[:60] + '...'
        print(f'  UNTRANSLATED: \"{msgid}\"')
"
```

#### For YAML (Rails)

```bash
python3 -c "
import yaml, glob, os

files = sorted(glob.glob('config/locales/*.yml') or glob.glob('locales/*.yml') or glob.glob('i18n/*.yml'))
if not files:
    print('ERROR: No YAML locale files found'); exit(1)

def flatten(obj, prefix=''):
    items = {}
    if not isinstance(obj, dict): return {prefix: obj}
    for k, v in obj.items():
        key = f'{prefix}.{k}' if prefix else str(k)
        if isinstance(v, dict):
            items.update(flatten(v, key))
        else:
            items[key] = v
    return items

# Find English source
en_keys = {}
en_file = None
for f in files:
    with open(f) as fh:
        data = yaml.safe_load(fh)
    if data and 'en' in data:
        en_keys = flatten(data['en'])
        en_file = f
        break

if not en_file:
    print('ERROR: No English YAML locale found'); exit(1)

print(f'Source: {en_file} ({len(en_keys)} keys)')
en_set = set(en_keys.keys())

for f in files:
    if f == en_file: continue
    with open(f) as fh:
        data = yaml.safe_load(fh)
    if not data: continue
    lang_code = list(data.keys())[0]
    lang_flat = flatten(data[lang_code])
    lang_set = set(lang_flat.keys())
    missing = sorted(en_set - lang_set)
    status = 'OK' if not missing else f'{len(missing)} missing'
    print(f'{os.path.basename(f)} ({lang_code}): {len(lang_set)} keys [{status}]')
    for m in missing[:10]:
        val = en_keys[m]
        if len(str(val)) > 60: val = str(val)[:60] + '...'
        print(f'  MISSING: {m} = \"{val}\"')
"
```

### 1.2 Check Recently Changed Keys

If the user mentions "new" or "changed" strings, detect what changed in the source file:

```bash
git diff HEAD -- <SOURCE_FILE> | head -200
```

Parse added lines (`+`) for new/changed source entries.

**If in Audit mode:** Stop here and report findings. Do not proceed to Phase 2.

---

## Mode Detection

Determine mode from `$ARGUMENTS`:

| Mode | Triggers | Action |
|------|----------|--------|
| **Propagate** (default) | "propagate", "translate", "sync", "fill", "finish", empty args | Detect new/changed keys → translate → insert into all targets |
| **Audit** | "audit", "missing", "check", "report" | Report missing/extra keys per file, no modifications |
| **Hardcoded** | "hardcoded", "find strings", "grep" | Scan source files for hardcoded user-facing strings |

---

## Phase 2: Translate Missing/New Keys

### 2.1 Determine Keys to Translate

Build the key list from one of:
- Missing keys detected in Phase 1
- Explicit list from the user
- Git diff showing newly added keys

### 2.2 Scale Decision

Before translating, decide whether to work serially or use `/team`:

- **< 10 missing keys**: Translate all target files in a single pass
- **10-50 missing keys**: Use `/team` with 3-4 agents grouped by language family
- **50+ missing keys**: Use `/team` with 4+ agents — parallel execution saves substantial time

### 2.3 Translation Rules

1. **Natural translations, not literal.** Translate the meaning. Use natural phrasing for the target language and context, not word-for-word calques.

2. **Preserve interpolation tokens exactly.** Whatever placeholder syntax the format uses must appear identically in translations. Never translate placeholder names.
   - ARB/ICU: `{placeholder}`, `{count, plural, ...}`
   - i18next: `{{placeholder}}`, `$t(key)`
   - .strings: `%@`, `%d`, `%1$@`
   - Android XML: `%s`, `%d`, `%1$s`
   - gettext: `%(name)s`, `%s`
   - Rails/YAML: `%{name}`
   - React Intl: `{placeholder}`, `{count, plural, ...}`

3. **Preserve plural/select syntax exactly.** If the format supports pluralization (ICU, gettext, Rails), reproduce the structure and only translate the human-readable text. Never translate keywords (`plural`, `select`, `one`, `other`, `few`, `many`, etc.).

4. **Preserve format-specific metadata.** Each format has its own metadata conventions:
   - ARB: Only `app_en.arb` has `@key` metadata; target files have only key-value pairs + `@@locale`
   - .xcstrings: Preserve `state`, `extractionState`, and `comment` fields
   - gettext: Preserve `#.` comments, `msgctxt`, and plural forms header
   - Android XML: Preserve `translatable="false"` attributes

5. **Chinese variants:** If the project has zh/zh_CN/zh_TW:
   - `zh` / `zh_CN`: Simplified Chinese
   - `zh_TW` / `zh_Hant`: Traditional Chinese with locale-specific vocabulary

6. **RTL languages (ar, fa, he):** Most frameworks handle RTL automatically. Just provide natural translations.

7. **Technical terms — keep as-is** unless the project has established translations for them. Check existing translations for precedent.

8. **Consistency check:** Before translating, read 3-5 similar existing translations in each target file to match the established tone and terminology.

### 2.4 Agent Grouping (when using /team)

Group by language family so each agent can cross-check terminology:

- Agent 1: Chinese variants (zh, zh_CN, zh_TW, zh_Hant)
- Agent 2: East Asian (ja, ko)
- Agent 3: RTL languages (ar, fa, he)
- Agent 4: European / remaining (es, fr, de, pt, ru, it, nl, vi, etc.)

Adjust groups based on which languages actually exist in the project.

### 2.5 Insert Translations

Edit each target file to add missing translations using the correct format:

- **ARB/JSON**: Valid JSON, no trailing commas, UTF-8
- **.strings**: `"key" = "value";` format, proper escaping
- **.xcstrings**: Add `localizations.<lang>.stringUnit.value` entries
- **Android XML**: Add `<string name="key">value</string>` elements, escape `'`, `"`, `&`, `<`
- **gettext**: Fill empty `msgstr` fields
- **YAML**: Maintain nesting structure, proper quoting
- **.resx**: Add `<data name="key"><value>...</value></data>` elements

---

## Phase 3: Validate

### 3.1 Run Code Generation (if applicable)

Run the framework's code generation command:

| Framework | Command |
|-----------|---------|
| Flutter ARB | `flutter gen-l10n` |
| i18next | `npx i18next` (if scanner configured) |
| Rails | N/A (loaded at runtime) |
| Android | Build picks up changes automatically |
| gettext | `msgfmt --check` on each `.po` file |

### 3.2 Verify File Validity

Validate all translation files parse correctly:

```bash
python3 -c "
import json, glob, os, sys

errors = []

# JSON-based formats (ARB, JSON, xcstrings)
for pattern in ['**/*.arb', '**/locales/**/*.json', '**/i18n/**/*.json', '**/*.xcstrings']:
    for fn in glob.glob(pattern, recursive=True):
        if 'node_modules' in fn or '.build' in fn: continue
        try:
            with open(fn) as f:
                json.load(f)
            print(f'OK: {fn}')
        except Exception as e:
            errors.append(f'{fn}: {e}')
            print(f'ERROR: {fn}: {e}')

if errors:
    print(f'\n{len(errors)} file(s) have errors!')
else:
    print('\nAll files valid.')
"
```

For non-JSON formats, use format-specific validation:

```bash
# Android XML validation
python3 -c "
import xml.etree.ElementTree as ET, glob
for fn in glob.glob('**/res/values*/strings.xml', recursive=True):
    try:
        ET.parse(fn)
        print(f'OK: {fn}')
    except Exception as e:
        print(f'ERROR: {fn}: {e}')
"
```

```bash
# gettext validation
for f in $(find . -name "*.po" 2>/dev/null); do
    msgfmt --check "$f" 2>&1 && echo "OK: $f" || echo "ERROR: $f"
done
```

### 3.3 Verify Placeholder Integrity

Check that all placeholders from the source appear in translations:

```bash
python3 -c "
import json, re, glob, os

# Detect format and check placeholders
# Patterns for different interpolation syntaxes
patterns = {
    'icu': re.compile(r'\{(\w+)'),           # {name}, {count, plural, ...}
    'i18next': re.compile(r'\{\{(\w+)\}\}'), # {{name}}
    'printf': re.compile(r'%[\d\$]*[sdf@]'), # %s, %d, %1\$s, %@
    'ruby': re.compile(r'%\{(\w+)\}'),       # %{name}
    'python': re.compile(r'%\((\w+)\)'),     # %(name)s
}

# Try ARB first
arb_files = glob.glob('**/*_en.arb', recursive=True) or glob.glob('**/app_en.arb', recursive=True)
if arb_files:
    source = arb_files[0]
    base_dir = os.path.dirname(source)
    with open(source) as f:
        en = json.load(f)
    pat = patterns['icu']
    en_ph = {k: set(pat.findall(str(v))) for k, v in en.items()
             if not k.startswith('@') and pat.search(str(v))}
    errors = []
    for fn in sorted(glob.glob(os.path.join(base_dir, '*.arb'))):
        if fn == source: continue
        with open(fn) as f:
            lang = json.load(f)
        for key, expected in en_ph.items():
            if key in lang:
                actual = set(pat.findall(str(lang[key])))
                if actual != expected:
                    errors.append(f'{os.path.basename(fn)}: {key} expected {expected}, got {actual}')
    if errors:
        print(f'PLACEHOLDER ERRORS ({len(errors)}):')
        for e in errors: print(f'  {e}')
    else:
        print('All placeholders match.')
    exit(0)

# Try JSON locales
for base in ['locales', 'locale', 'i18n', 'src/locales', 'public/locales']:
    en_file = os.path.join(base, 'en.json')
    if os.path.isfile(en_file):
        with open(en_file) as f:
            en = json.load(f)
        # Flatten and check both ICU and i18next patterns
        def flatten(obj, prefix=''):
            items = {}
            for k, v in obj.items():
                key = f'{prefix}.{k}' if prefix else k
                if isinstance(v, dict): items.update(flatten(v, key))
                else: items[key] = v
            return items
        en_flat = flatten(en)
        for pat_name, pat in patterns.items():
            en_ph = {k: set(pat.findall(str(v))) for k, v in en_flat.items() if pat.search(str(v))}
            if en_ph:
                errors = []
                for fn in sorted(glob.glob(os.path.join(base, '*.json'))):
                    if fn == en_file: continue
                    with open(fn) as f:
                        lang = flatten(json.load(f))
                    for key, expected in en_ph.items():
                        if key in lang:
                            actual = set(pat.findall(str(lang[key])))
                            if actual != expected:
                                errors.append(f'{os.path.basename(fn)}: {key} expected {expected}, got {actual}')
                if errors:
                    print(f'PLACEHOLDER ERRORS ({len(errors)}):')
                    for e in errors: print(f'  {e}')
                else:
                    print(f'All {pat_name} placeholders match.')
                break
        exit(0)

print('Could not determine format for placeholder checking — verify manually.')
"
```

### 3.4 Re-audit

Run the Phase 1 audit script again to confirm all gaps are filled.

### 3.5 Lint/Analyze (if applicable)

Run the project's lint command:

| Framework | Command |
|-----------|---------|
| Flutter | `flutter analyze --no-pub 2>&1 \| head -20` |
| JS/TS | `npx eslint <locale-dir> 2>&1 \| head -20` |
| Rails | `bundle exec rails i18n:check 2>&1 \| head -20` (if available) |

---

## Phase 4: Find Hardcoded Strings (Optional)

Only run if the user explicitly requests hardcoded string detection.

### 4.1 Detect Source Language and Scan

Adapt scanning to the project's language:

#### Dart/Flutter
```bash
rg "Text\('[A-Z][a-z]" lib/ --glob '*.dart' -n | head -40
rg "(title|label|hint|message|content|tooltip)\s*:\s*'[A-Za-z]" lib/ --glob '*.dart' -n | head -40
rg "const String \w+ = '[A-Z][a-z]" lib/ --glob '*.dart' -n | head -20
```

#### Swift/SwiftUI
```bash
rg 'Text\("[A-Z][a-z]' --glob '*.swift' -n | head -40
rg '(title|message|label|placeholder)\s*[:=]\s*"[A-Z][a-z]' --glob '*.swift' -n | head -40
rg 'LocalizedStringKey' --glob '*.swift' -n --invert-match | rg '"[A-Z][a-z]' --glob '*.swift' -n | head -40
```

#### JavaScript/TypeScript (React, Vue, Next.js)
```bash
rg '>[A-Z][a-z][^<]*</' --glob '*.{tsx,jsx,vue}' -n | head -40
rg '(title|label|placeholder|message|alt|aria-label)\s*=\s*"[A-Z][a-z]' --glob '*.{tsx,jsx,vue}' -n | head -40
rg "(title|label|placeholder|message)\s*:\s*['\"][A-Z][a-z]" --glob '*.{ts,js}' -n | head -40
```

#### Kotlin/Android
```bash
rg '(setText|text\s*=)\s*"[A-Z][a-z]' --glob '*.kt' -n | head -40
rg 'android:(text|hint|title|summary)\s*=\s*"[A-Z][a-z]' --glob '*.xml' -n | head -40
```

#### Ruby/Rails
```bash
rg "(flash\[|redirect_to.*notice|alert)\s*[:=]\s*['\"][A-Z][a-z]" --glob '*.rb' -n | head -40
rg '>[A-Z][a-z][^<]*</' --glob '*.erb' -n | head -40
```

### 4.2 Report Findings

For each hardcoded string: file path, line number, the string, and a suggested translation key name. Mark each as user-visible or debug-only. Do NOT auto-fix — just report for the user to decide which to extract.

---

## Error Recovery

- **JSON/XML/YAML parse error:** Check for missing commas, trailing commas, unescaped quotes, broken Unicode. Fix and re-validate.
- **Placeholder mismatch:** Show source vs broken translation side-by-side. Fix to include all required tokens.
- **Plural/select syntax broken:** Show the original expression and the malformed translation. Restore the full structure, only replacing human-readable text.
- **Key count still mismatched after propagation:** Re-run Phase 1 audit to identify remaining gaps and continue from Phase 2.
- **Encoding issues:** Ensure all files are saved as UTF-8. For .strings files, verify UTF-16 encoding if required by the toolchain.
