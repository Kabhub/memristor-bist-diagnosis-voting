from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'MANIFEST_SHA256.json').read_text())
failed=[]
for name,want in manifest.items():
 p=root/name
 if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=want:failed.append(name)
if failed:raise SystemExit('Integrity mismatch: '+', '.join(failed))
print('PASS: verified',len(manifest),'packaged files')
