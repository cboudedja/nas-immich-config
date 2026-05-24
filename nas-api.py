from flask import Flask, jsonify, send_from_directory, request, abort
from flask_cors import CORS
import subprocess, re, os, time
from dotenv import load_dotenv
load_dotenv(os.path.expanduser("~/.env"))
from dotenv import load_dotenv
load_dotenv(os.path.expanduser("~/.env"))
from functools import wraps

NTFY_TOPIC = os.getenv("NTFY_TOPIC")
NTFY_URL = os.getenv("NTFY_URL")
last_alerts = {}

def send_alert(title, message, priority="default", tags=""):
    try:
        subprocess.run(
            ["curl", "-s",
             "-H", f"Title: {title}",
             "-H", f"Priority: {priority}",
             "-H", f"Tags: {tags}",
             "-d", message, NTFY_URL],
            timeout=5
        )
    except:
        pass

app = Flask(__name__)
CORS(app)

DASHBOARD_DIR = os.path.expanduser('~/dashboard')
API_TOKEN = os.getenv("API_TOKEN")

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except:
        return ""

def require_token(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('X-API-Token')
        if token != API_TOKEN:
            abort(401)
        return f(*args, **kwargs)
    return decorated

@app.route('/')
def dashboard():
    with open(os.path.join(DASHBOARD_DIR, 'index.html'), 'r') as f:
        content = f.read()
    content = content.replace('%%API_TOKEN%%', API_TOKEN)
    return content

@app.route('/manifest.json')
def manifest():
    return send_from_directory(DASHBOARD_DIR, 'manifest.json')

@app.route('/icon.png')
def icon():
    return send_from_directory(DASHBOARD_DIR, 'icon.png')

@app.route('/metrics')
@require_token
def metrics():
    data = {}

    # Température CPU
    sensors = sh("sensors")
    temps = re.findall(r'Core \d+:\s+\+?([\d.]+)°C', sensors)
    data['temp'] = round(max(float(t) for t in temps)) if temps else 0

    # Ventilateur
    fan = re.search(r'Exhaust\s*:\s*(\d+)\s*RPM', sensors)
    data['fan'] = int(fan.group(1)) if fan else 0

    # RAM
    mem = sh("free -m").splitlines()
    if len(mem) > 1:
        parts = mem[1].split()
        total, used, avail = int(parts[1]), int(parts[2]), int(parts[6])
        data['ramUsed'] = f"{used/1024:.1f} Go"
        data['ramAvail'] = f"{avail/1024:.1f} Go"
        data['ramPct'] = round(used/total*100)
        data['ramTotal'] = f"{total/1024:.1f} Go"

    # CPU usage (load average)
    try:
        load1 = os.getloadavg()[0]
        ncpu = os.cpu_count() or 1
        data['cpuPct'] = min(round(load1 / ncpu * 100), 100)
    except:
        data['cpuPct'] = 0

    # Énergie via RAPL
    try:
        e1 = int(sh("sudo cat /sys/class/powercap/intel-rapl*/energy_uj | head -1"))
        time.sleep(0.5)
        e2 = int(sh("sudo cat /sys/class/powercap/intel-rapl*/energy_uj | head -1"))
        data['watts'] = f"{(e2 - e1) / 0.5 / 1_000_000:.1f}"
    except:
        data['watts'] = "0"

    # Disque pool mergerfs
    disk = sh("df -h /mnt/immich-pool | tail -1").split()
    if len(disk) >= 5:
        data['diskUsed'] = disk[2].replace('G', ' Go')
        data['diskTotal'] = disk[1].replace('G', ' Go')
        data['diskPct'] = int(disk[4].replace('%', ''))

    # Disque backup HDD
    backup = sh("df -h /mnt/backup | tail -1").split()
    if len(backup) >= 5:
        data['backupUsed'] = backup[2].replace('G', ' Go')
        data['backupTotal'] = backup[1].replace('G', ' Go')
        data['backupPct'] = int(backup[4].replace('%', ''))

    # Batterie
    try:
        cap = sh("cat /sys/class/power_supply/BAT0/capacity")
        status = sh("cat /sys/class/power_supply/BAT0/status")
        data['battery'] = int(cap) if cap else 0
        data['batStatus'] = "Full — branché secteur" if status == "Full" else status
    except:
        data['battery'] = 0
        data['batStatus'] = "—"

    # Uptime
    up = sh("uptime -p").replace("up ", "").replace(" days", "j").replace(" day", "j").replace(" hours", "h").replace(" hour", "h").replace(" minutes", "m").replace(" minute", "m").replace(",", "")
    data['uptime'] = up or "—"

   # Réseau (vitesse upload/download)
    try:
        iface = sh("ip route get 1.1.1.1 | grep -oP 'dev \K\S+'")
        net1 = sh(f"cat /proc/net/dev | grep {iface}")
        time.sleep(1)
        net2 = sh(f"cat /proc/net/dev | grep {iface}")
        if net1 and net2:
            rx1 = int(net1.split()[1])
            tx1 = int(net1.split()[9])
            rx2 = int(net2.split()[1])
            tx2 = int(net2.split()[9])
            data['netDown'] = f"{(rx2-rx1)/1/1024/1024:.2f}"
            data['netUp'] = f"{(tx2-tx1)/1/1024/1024:.2f}"
        else:
            data['netDown'] = "0"
            data['netUp'] = "0"
    except:
        data['netDown'] = "0"
        data['netUp'] = "0"

    # Statut sauvegarde rsync
    try:
        last_line = sh("grep -v '^$' /home/immich/backup.log | tail -1")
        if "succes" in last_line or "succès" in last_line:
            data['backupStatus'] = "success"
            data['backupDate'] = last_line[:19]
            photos_match = re.search(r'Photos: (\d+)', last_line)
            videos_match = re.search(r'Videos: (\d+)', last_line)
            data['backupPhotos'] = int(photos_match.group(1)) if photos_match else 0
            data['backupVideos'] = int(videos_match.group(1)) if videos_match else 0
        elif "ERREUR" in last_line or "erreur" in last_line:
            data['backupStatus'] = "error"
            data['backupDate'] = last_line[:19]
        elif "Debut" in last_line or "Début" in last_line:
            data['backupStatus'] = "running"
            data['backupDate'] = "Sauvegarde en cours..."
        else:
            data['backupStatus'] = "unknown"
            data['backupDate'] = "Aucune sauvegarde récente"
    except:
        data['backupStatus'] = "unknown"
        data['backupDate'] = "—"

   # Compteurs photos et vidéos Immich
    try:
        photos = sh("""docker exec immich_postgres psql -U postgres -d immich -t -c "SELECT COUNT(*) FROM asset WHERE \\"deletedAt\\" IS NULL AND visibility = 'timeline' AND type = 'IMAGE';" 2>/dev/null""")
        data['photoCount'] = int(photos.strip()) if photos.strip().isdigit() else 0
        videos = sh("""docker exec immich_postgres psql -U postgres -d immich -t -c "SELECT COUNT(*) FROM asset WHERE \\"deletedAt\\" IS NULL AND visibility = 'timeline' AND type = 'VIDEO';" 2>/dev/null""")
        data['videoCount'] = int(videos.strip()) if videos.strip().isdigit() else 0
    except:
        data['photoCount'] = 0
        data['videoCount'] = 0

    # Conteneurs Docker
    containers = []
    docker = sh('docker ps -a --format "{{.Names}}|{{.Status}}"')
    for line in docker.splitlines():
        if '|' in line:
            name, status = line.split('|', 1)
            containers.append({
                'name': name,
                'status': 'Up (healthy)' if 'healthy' in status else status[:20],
                'healthy': 'Up' in status
            })
    data['containers'] = containers


   # Alertes automatiques
    now = time.time()

    # Température critique > 100°C
    if data.get('temp', 0) > 100:
        if now - last_alerts.get('temp', 0) > 3600:
            send_alert("🌡️ Température critique !", f"CPU à {data['temp']}°C — intervenir immédiatement", "urgent", "warning,thermometer")
            last_alerts['temp'] = now
    else:
        last_alerts.pop('temp', None)

    # Disque pool > 80%
    if data.get('diskPct', 0) > 80:
        if now - last_alerts.get('disk', 0) > 3600:
            send_alert("💾 Pool presque plein", f"{data['diskPct']}% utilisé sur {data['diskTotal']}", "high", "warning,cd")
            last_alerts['disk'] = now
    else:
        last_alerts.pop('disk', None)

    # Backup > 80%
    if data.get('backupPct', 0) > 80:
        if now - last_alerts.get('backup_disk', 0) > 3600:
            send_alert("💾 Backup presque plein", f"{data['backupPct']}% utilisé sur {data['backupTotal']}", "high", "warning,cd")
            last_alerts['backup_disk'] = now
    else:
        last_alerts.pop('backup_disk', None)

    # Conteneurs Docker arrêtés
    stopped = [c['name'] for c in data.get('containers', []) if not c['healthy']]
    for container in stopped:
        alert_key = f'docker_{container}'
        if now - last_alerts.get(alert_key, 0) > 1800:
            send_alert("🐳 Conteneur arrêté !", f"{container} ne répond plus", "urgent", "warning,whale")
            last_alerts[alert_key] = now
    running = [c['name'] for c in data.get('containers', []) if c['healthy']]
    for container in running:
        last_alerts.pop(f'docker_{container}', None)

    # Sauvegarde en erreur
    if data.get('backupStatus') == 'error':
        if now - last_alerts.get('backup_err', 0) > 3600:
            send_alert("❌ Sauvegarde échouée", f"Erreur rsync — {data.get('backupDate', '')}", "high", "warning,floppy_disk")
            last_alerts['backup_err'] = now
    else:
        last_alerts.pop('backup_err', None)
    return jsonify(data)

@app.route('/action/restart-immich', methods=['POST'])
@require_token
def restart_immich():
    sh('cd /home/immich/immich && docker compose restart')
    return jsonify({'status': 'ok', 'message': 'Immich redémarré'})

@app.route('/action/backup', methods=['POST'])
@require_token
def run_backup():
    import threading
    def do_backup():
        sh('/home/immich/backup.sh')
    threading.Thread(target=do_backup).start()
    return jsonify({'status': 'ok', 'message': 'Sauvegarde lancée en arrière-plan'})

@app.route('/action/reboot', methods=['POST'])
@require_token
def reboot():
    import threading
    def do_reboot():
        time.sleep(2)
        os.system('sudo reboot')
    threading.Thread(target=do_reboot).start()
    return jsonify({'status': 'ok', 'message': 'Redémarrage dans 2 secondes'})

@app.route('/action/poweroff', methods=['POST'])
@require_token
def poweroff():
    import threading
    def do_poweroff():
        time.sleep(2)
        os.system('sudo poweroff')
    threading.Thread(target=do_poweroff).start()
    return jsonify({'status': 'ok', 'message': 'Extinction dans 2 secondes'})

if __name__ == '__main__':
    ts_ip = sh("tailscale ip -4").split('\n')[0]
    host = ts_ip if ts_ip else '127.0.0.1'
    app.run(host=host, port=8088)
