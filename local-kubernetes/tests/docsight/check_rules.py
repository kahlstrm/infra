"""Test the deployed Prometheus rules with promtool, without duplicate rule files."""

from pathlib import Path
import shutil
import subprocess
import tempfile

import yaml

root = Path(__file__).resolve().parents[2]
manifest = root / 'manifests/docsight/prometheusrule.yaml'
with tempfile.TemporaryDirectory(prefix='docsight-rules-') as directory:
    work = Path(directory)
    rules = yaml.safe_load(manifest.read_text())['spec']
    (work / 'rules.yaml').write_text(yaml.safe_dump(rules))
    shutil.copy(Path(__file__).with_name('rule-tests.yaml'), work / 'rule-tests.yaml')
    subprocess.run(['promtool', 'check', 'rules', 'rules.yaml'], cwd=work, check=True)
    subprocess.run(['promtool', 'test', 'rules', 'rule-tests.yaml'], cwd=work, check=True)
