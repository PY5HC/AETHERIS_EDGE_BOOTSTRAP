#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${AETHERIS_RELEASE_MANIFEST:-}"
OUTPUT="${AETHERIS_UNIT_OUTPUT:-}"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
[ -n "$MANIFEST" ] && [ -f "$MANIFEST" ] || fail manifest
[ -n "$OUTPUT" ] || fail output
case "$OUTPUT" in /etc/*|/usr/lib/*|/lib/*|/opt/*|/var/*|/run/*|/home/*) fail live-output;; esac
case "$OUTPUT" in /*) ;; *) fail absolute-output;; esac
python3 - "$MANIFEST" "$OUTPUT" "$ROOT_DIR/templates/aetheris-node.service.g3.6.template" <<'PY'
import json, os, re, sys
manifest_path, output, template_path = sys.argv[1:]
data = json.load(open(manifest_path, encoding='utf-8'))
if data.get('schema_version') != '1.0': raise SystemExit('schema')
entry = data.get('entrypoint', {})
release_id = data.get('release_id', '')
relative = entry.get('relative_path', '')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', release_id): raise SystemExit('release id')
if not re.fullmatch(r'(?:bin|venv/bin)/[A-Za-z0-9._/-]+', relative) or '..' in relative: raise SystemExit('entrypoint')
root = f'/opt/aetheris/releases/{release_id}'
executable = f'{root}/{relative}'
if not os.path.isfile(executable) or not os.access(executable, os.X_OK): raise SystemExit('executable')
text = open(template_path, encoding='utf-8').read()
text = text.replace('@RELEASE_ROOT@', root).replace('@RELEASE_EXECUTABLE@', executable)
if '@' in text or '$' in text: raise SystemExit('unresolved token')
open(output, 'w', encoding='utf-8').write(text)
PY
printf 'UNIT_RENDER=PASS\nUNIT_OUTPUT=%s\n' "$OUTPUT"
