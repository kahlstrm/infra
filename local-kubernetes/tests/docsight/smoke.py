import os
from pathlib import Path
import subprocess
import time
import urllib.request
import urllib.error

root = Path(__file__).resolve().parents[2] / 'manifests/docsight/scripts'
image = os.environ['DOCSIGHT_IMAGE']
name = 'docsight-monitoring-smoke-' + str(os.getpid())
volume = name + '-data'
old_token = 'dsk_' + 'synthetic-scrape-token-' * 3
token = 'dsk_' + 'rotated-scrape-token-' * 3

def docker(*args):
    return subprocess.check_output(['docker', *args], text=True).strip()

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request(port, path, credential=None):
    headers = {'Authorization': 'Bearer ' + credential} if credential else {}
    try:
        with urllib.request.build_opener(NoRedirect).open(urllib.request.Request(f'http://127.0.0.1:{port}{path}', headers=headers), timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()

try:
    docker('volume', 'create', volume)
    docker('run', '--rm', '-v', volume + ':/data', '--entrypoint', 'chown', image, '1000:1000', '/data')
    common = ['--user', '1000:1000', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
              '--read-only', '--tmpfs', '/tmp', '-e', 'PYTHONDONTWRITEBYTECODE=1', '-e', 'PYTHONPATH=/app',
              '-v', volume + ':/data', '-v', str(root) + ':/scripts:ro']
    for seed_token in (old_token, old_token, token):
        docker('run', '--rm', *common, '-e', 'DOCSIGHT_SCRAPE_TOKEN=' + seed_token,
               '--entrypoint', 'python', image, '/scripts/bootstrap.py')
    docker('run', '--rm', *common, '--entrypoint', 'python', image, '-c',
           'from app.config import ConfigManager; assert ConfigManager("/data").is_configured()')
    docker('run', '-d', '--name', name, *common, '-p', '127.0.0.1::8765',
           '-e', 'WEB_HOST=0.0.0.0', '-e', 'DEMO_MODE=true', '-e', 'MODEM_PASSWORD=synthetic-modem', '-e', 'DATA_DIR=/data',
           '-e', 'ADMIN_PASSWORD=synthetic-admin', '-e', 'METRICS_REQUIRE_TOKEN=true',
           '--entrypoint', 'python', image, '-m', 'app.main')
    app_port = docker('port', name, '8765/tcp').rsplit(':', 1)[1]
    for _ in range(30):
        try:
            docker('exec', name, 'python', '-m', 'app.healthcheck')
            break
        except subprocess.CalledProcessError:
            pass
        time.sleep(1)
    docker('exec', name, 'python', '-m', 'app.healthcheck')
    assert request(app_port, '/metrics')[0] == 401
    assert request(app_port, '/metrics', old_token)[0] == 401
    assert request(app_port, '/metrics', token)[0] == 200
    assert request(app_port, '/api/tokens', token)[0] == 403
    assert request(app_port, '/api/snapshots', token)[0] == 403
    assert request(app_port, '/settings')[0] == 302
    assert request(app_port, '/login')[0] == 200
    status, body = request(app_port, '/metrics', token)
    assert b'docsight_modem_poll_success' in body
    privileges = docker('exec', name, 'python', '-c',
        'print("\\n".join(line.strip() for line in open("/proc/self/status") if line.startswith(("Uid:", "CapEff:", "NoNewPrivs:"))))')
    assert 'NoNewPrivs:\t1' in privileges
    assert 'CapEff:\t0000000000000000' in privileges
    print('PASS: idempotent bootstrap and token rotation, restricted container startup, healthcheck, protected scrape, metrics-only token restrictions, available UI login and protected settings.')
    print(privileges)
except Exception:
    try:
        print(docker('logs', name))
    except subprocess.CalledProcessError:
        pass
    raise
finally:
    subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['docker', 'volume', 'rm', volume], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
