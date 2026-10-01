#!/usr/bin/env python3
"""Compare shipped assets and executable code, excluding code-signature data."""
import hashlib, json, pathlib, struct

root = pathlib.Path(__file__).resolve().parent
original = pathlib.Path('/Applications/Animates.app')
dev = pathlib.Path('/Applications/Animates Dev.app')

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()

def sections(path):
    data = path.read_bytes()
    start = 0
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        for i in range(count):
            cpu, _, offset, _, _ = struct.unpack_from('>IIIII', data, 8 + i * 20)
            if cpu == 0x0100000c: start = offset; break
        else: raise ValueError('arm64 slice missing')
    if data[start:start+4] != b'\xcf\xfa\xed\xfe': raise ValueError('Expected 64-bit Mach-O')
    count = struct.unpack_from('<I', data, start + 16)[0]
    cursor = start + 32
    result = {}
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, cursor)
        if command == 0x19:
            section_count = struct.unpack_from('<I', data, cursor + 64)[0]
            for i in range(section_count):
                p = cursor + 72 + i * 80
                name = data[p:p+16].split(b'\0')[0].decode()
                segment = data[p+16:p+32].split(b'\0')[0].decode()
                length = struct.unpack_from('<Q', data, p+40)[0]
                offset = struct.unpack_from('<I', data, p+48)[0]
                if segment == '__TEXT' and name in ('__text', 'il2cpp'):
                    result[name] = hashlib.sha256(data[start+offset:start+offset+length]).hexdigest()
        cursor += size
    if not result: raise ValueError('No executable sections found')
    return result

assets = []
for folder in ('Contents/Resources/Data', 'Contents/Resources/bundles'):
    for p in sorted((original/folder).rglob('*')):
        if not p.is_file(): continue
        rel = p.relative_to(original)
        a, b = digest(p), digest(dev/rel)
        assets.append({'path': str(rel), 'sha256': a, 'identical': a == b})
code = []
for name in ('UnityPlayer.dylib', 'GameAssembly.dylib'):
    rel = pathlib.Path('Contents/Frameworks')/name
    a, b = sections(original/rel), sections(dev/rel)
    code.append({'path': str(rel), 'sections': a, 'identical': a == b})
report = {'source': str(original), 'app': str(dev), 'assets': assets, 'executableCode': code}
report['passed'] = all(x['identical'] for x in assets + code)
(root/'verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(f"{'PASS' if report['passed'] else 'FAIL'}: {len(assets)} asset files, UnityPlayer + GameAssembly executable sections")
if not report['passed']: raise SystemExit(1)
