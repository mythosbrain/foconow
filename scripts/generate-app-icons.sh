#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/habit-counter-icons.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
clang -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -fobjc-arc -framework AppKit \
  "$ROOT/scripts/generate-app-icons.m" -o "$WORK/generate"
"$WORK/generate" "$ROOT"
python3 - "$ROOT" "$WORK" <<'PY'
from pathlib import Path
import struct, subprocess, sys
root, work = map(Path, sys.argv[1:])
source = root / 'Apple/AppIcon1024.png'
types = {'icp4':16, 'icp5':32, 'icp6':64, 'ic07':128, 'ic08':256,
         'ic09':512, 'ic10':1024, 'ic11':32, 'ic12':64, 'ic13':256, 'ic14':512}
chunks = []
for kind, size in types.items():
    target = work / f'{kind}.png'
    subprocess.run(['sips','-z',str(size),str(size),str(source),'--out',str(target)],
                   check=True, stdout=subprocess.DEVNULL)
    data = target.read_bytes()
    chunks.append(kind.encode() + struct.pack('>I',len(data)+8) + data)
body = b''.join(chunks)
(root/'Apple/AppIcon.icns').write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
PY
echo "Generated $ROOT/Apple/AppIcon.icns"
