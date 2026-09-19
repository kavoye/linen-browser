#!/usr/bin/env python3
"""Refuse to benchmark a stale build and identify the exact Linen source."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
paths = list((root / 'Linen').rglob('*.swift')) + list((root / 'LinenTests').rglob('*.swift'))
paths += [root / 'Linen.xcodeproj/project.pbxproj', root / 'Linen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']
paths += [root / 'Tools' / name for name in ['benchmark-provenance.py', 'build-benchmark-adapter.sh', 'run-benchmark-adapter.sh']]
digest = hashlib.sha256()
for path in sorted(paths):
    digest.update(str(path.relative_to(root)).encode())
    digest.update(path.read_bytes())
metadata = {
    'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'source_sha256': digest.hexdigest(),
    'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True)),
}
record = Path(os.environ.get('LINEN_BENCHMARK_DERIVED_DATA', root / 'build/BenchmarkDD')) / 'benchmark-build.json'
if sys.argv[1] == 'write':
    record.write_text(json.dumps(metadata, indent=2))
elif sys.argv[1] == 'verify':
    if not record.exists() or json.loads(record.read_text())['source_sha256'] != metadata['source_sha256']:
        raise SystemExit('Benchmark build is stale. Run Tools/build-benchmark-adapter.sh.')
elif sys.argv[1] == 'hash':
    print(metadata['source_sha256'])
else:
    raise SystemExit('Expected write, verify, or hash')
