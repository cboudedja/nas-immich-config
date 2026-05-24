# NAS Immich — MacBook Pro 2012

Cloud photos privé self-hosted pour 5 appareils Apple (2 iPhones, 1 iPad, 2 MacBooks).  
Coût total : **0 €** — matériel 100% recyclé.

---

## 🖥️ Matériel

| Composant | Détail |
|-----------|--------|
| Machine | MacBook Pro 13" mi-2012 |
| CPU | Intel Core i5-3210M (2 cœurs, 2.5 GHz) |
| RAM | 4 Go DDR3 |
| OS | Debian 13 Trixie |
| Hostname | nas-immich |
| Réseau | Wi-Fi + Ethernet — IP réservée DHCP |
| Accès distant | Tailscale VPN |

---

## 💾 Stockage — Pool mergerfs 1.3 To

| Disque | Capacité | Montage |
|--------|----------|---------|
| SSD interne MacBook | 480 Go | `/mnt/photos` |
| SSD Freebox Delta | 480 Go | `/mnt/freebox-ssd` (SMB) |
| HDD Freebox Delta | 458 Go | `/mnt/freebox-hdd` (SMB) |
| **Pool mergerfs** | **1.3 To** | `/mnt/immich-pool` |
| HDD USB backup | 916 Go | `/mnt/backup` |

---

## 🐳 Services Docker

| Conteneur | Rôle | Port |
|-----------|------|------|
| `immich_server` | Serveur Immich | 2283 |
| `immich_postgres` | Base de données PostgreSQL | — |
| `immich_machine_learning` | Reconnaissance faciale | — |
| `immich_redis` | Cache Redis (Valkey) | — |
| `ntfy` | Notifications push | 8090 |
| `homepage` | Page d'accueil | 3000 |

### Commandes utiles

```bash
cd ~/immich && docker compose up -d           # Démarrer
cd ~/immich && docker compose down            # Arrêter
cd ~/immich && docker compose restart         # Redémarrer
cd ~/immich && docker compose pull && docker compose up -d  # Mettre à jour
docker ps --format "table {{.Names}}\t{{.Status}}"         # Statut
```

---

## 🌐 Accès

| Service | URL |
|---------|-----|
| Immich | `http://${LOCAL_IP}:2283` |
| Dashboard monitoring | `http://${TAILSCALE_IP}:8088` |
| Homepage | `http://${TAILSCALE_IP}:3000` |
| Ntfy | `http://${TAILSCALE_IP}:8090` |
| SSH local | `ssh immich@${LOCAL_IP}` |
| SSH Tailscale | `ssh immich@${TAILSCALE_IP}` |

> ⚠️ Les variables `${TAILSCALE_IP}` et `${LOCAL_IP}` sont définies dans `~/.env` (non versionné).  
> Tous les services sont accessibles uniquement via **Tailscale VPN** depuis l'extérieur.

---

## 🔑 Variables d'environnement

Toutes les données sensibles sont centralisées dans `~/.env` (exclu du repo via `.gitignore`) :

```bash
API_TOKEN=          # Token API Flask dashboard
TAILSCALE_IP=       # IP Tailscale du serveur
LOCAL_IP=           # IP locale Wi-Fi
NTFY_TOPIC=         # Topic Ntfy
NTFY_URL=           # URL complète Ntfy
HDD_UUID=           # UUID du HDD backup USB
IMMICH_API_KEY=     # Clé API Immich pour Homepage
```

Les variables Homepage sont aussi dans `~/immich/.env` avec le préfixe `HOMEPAGE_VAR_`.

---

## 🔒 Sécurité

- **Tailscale VPN** — chiffrement WireGuard, aucun port ouvert sur la Freebox
- **Token API** — authentification requise sur tous les endpoints Flask
- **Fail2ban** — protection SSH (5 tentatives / 10 min → blocage 1h)
- **API en lecture seule** — les métriques n'exposent aucune donnée sensible
- **Variables d'env** — aucune donnée sensible dans le repo Git

---

## 💾 Sauvegarde

### Rsync photos
- **Script** : `backup.sh`
- **Planification** : chaque nuit à 3h00
- **Source** : `/mnt/immich-pool/`
- **Destination** : `/mnt/backup/`
- **Vérification** : UUID du HDD vérifié avant exécution (via `$HDD_UUID`)

### Backup PostgreSQL
- **Script** : `backup-postgres.sh`
- **Planification** : chaque nuit à 2h00
- **Destination** : `/mnt/backup/postgres/`
- **Rétention** : 7 derniers dumps (~82 Mo compressé)

### Corbeille Immich
- Photos supprimées conservées **30 jours** avant suppression définitive

---

## 🔔 Notifications push (Ntfy)

Alertes automatiques envoyées sur iPhone via **ntfy.sh** :

| Événement | Priorité |
|-----------|----------|
| Température CPU > 100°C | 🔴 Urgente |
| Conteneur Docker arrêté | 🔴 Urgente |
| Serveur hors ligne (Healthchecks.io) | 🔴 Urgente |
| Disque Freebox inaccessible | 🟠 Haute |
| Pool mergerfs dégradé | 🟠 Haute |
| Sauvegarde échouée | 🟠 Haute |
| Disque > 80% | 🟠 Haute |
| Serveur de retour en ligne | 🟢 Info |
| Pool reconstruit | 🟢 Info |

---

## 📊 Monitoring

### API Flask (`nas-api.py`)
- Port 8088, accessible via Tailscale uniquement
- Authentification par token (`X-API-Token` header)
- Métriques : température, RAM, CPU, watts, réseau, disques, Docker, photos/vidéos

### Dashboard PWA
- Graphique historique Température + CPU + RAM
- Boutons d'action : redémarrer Immich, lancer sauvegarde, reboot, extinction
- Installable comme app iOS/macOS

### Homepage
- Widget Immich : photos, vidéos, stockage en temps réel
- Métriques CPU, RAM, disque en temps réel
- Fond d'écran Sonoma style glassmorphism
- Installable comme PWA iOS

---

## ⚙️ Optimisations système

| Optimisation | Résultat |
|-------------|----------|
| Thermald (Intel) | Gestion thermique intelligente |
| Powersave CPU | 1.2 GHz au repos |
| **Température repos** | 55-60°C (avant : 64°C) |
| **Température charge** | 70-75°C (avant : 88-90°C) |
| **Gain total** | -15 à -30°C |

---

## 🕐 Tâches planifiées (crontab)

```
0 2 * * *    → Backup PostgreSQL
0 3 * * *    → Rsync photos
*/5 * * * *  → Ping Healthchecks.io
*/15 * * * * → Surveillance métriques API
```

---

## 📁 Structure du repo

```
nas-immich-config/
├── .gitignore
├── README.md
├── backup.sh              # Rsync photos vers HDD backup
├── backup-postgres.sh     # Dump PostgreSQL quotidien
├── mount-pool.sh          # Montage pool mergerfs au démarrage
├── monitor-pool.sh        # Surveillance et réparation pool
├── nas-api.py             # API Flask monitoring
├── sync-config.sh         # Synchronisation configs → Git
├── dashboard/
│   ├── index.html         # Dashboard PWA
│   └── manifest.json      # Manifest PWA
├── homepage/
│   ├── services.yaml      # Services Homepage (avec {{HOMEPAGE_VAR_*}})
│   ├── settings.yaml      # Configuration Homepage
│   └── widgets.yaml       # Widgets Homepage
├── systemd/
│   ├── nas-api.service
│   ├── immich-pool.service
│   ├── monitor-pool.service
│   ├── monitor-pool.timer
│   └── cpupower.service
└── etc/
    ├── jail.local          # Config Fail2ban
    └── logrotate-immich    # Rotation des logs
```

---

## 🚀 Services systemd

| Service | Rôle |
|---------|------|
| `nas-api.service` | API Flask monitoring |
| `immich-pool.service` | Montage pool mergerfs |
| `monitor-pool.timer` | Surveillance pool (5 min) |
| `cpupower.service` | Mode powersave CPU |
| `thermald.service` | Gestion thermique Intel |
| `fail2ban.service` | Protection SSH |

---

## 📱 Applications iOS

| App | Usage |
|-----|-------|
| **Immich** | Synchronisation photos/vidéos |
| **Tailscale** | VPN pour accès distant |
| **Ntfy** | Notifications push |
| **Dashboard** (PWA) | Monitoring serveur |
| **Homepage** (PWA) | Portail d'accès |

---

## 🔄 Synchronisation du repo

Pour synchroniser les configs vers Git après une modification :

```bash
~/sync-config.sh
```

---

*Dernière mise à jour : Mai 2026*
