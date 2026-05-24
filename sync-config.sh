#!/bin/bash
# Synchronise les fichiers de config vers le repo Git

# Scripts
cp ~/backup.sh ~/nas-config/
cp ~/backup-postgres.sh ~/nas-config/
cp ~/mount-pool.sh ~/nas-config/
cp ~/monitor-pool.sh ~/nas-config/
cp ~/nas-api.py ~/nas-config/

# Dashboard
cp ~/dashboard/index.html ~/nas-config/dashboard/
cp ~/dashboard/manifest.json ~/nas-config/dashboard/

# Homepage
cp ~/homepage/services.yaml ~/nas-config/homepage/
cp ~/homepage/settings.yaml ~/nas-config/homepage/
cp ~/homepage/widgets.yaml ~/nas-config/homepage/

# Configs systemd
sudo cp /etc/systemd/system/nas-api.service ~/nas-config/systemd/
sudo cp /etc/systemd/system/immich-pool.service ~/nas-config/systemd/
sudo cp /etc/systemd/system/monitor-pool.service ~/nas-config/systemd/
sudo cp /etc/systemd/system/monitor-pool.timer ~/nas-config/systemd/
sudo cp /etc/systemd/system/cpupower.service ~/nas-config/systemd/

# Autres configs
sudo cp /etc/fail2ban/jail.local ~/nas-config/etc/
sudo cp /etc/logrotate.d/immich ~/nas-config/etc/logrotate-immich
sudo chown -R immich:immich ~/nas-config/

# Git
cd ~/nas-config
git add .

# Vérifier s'il y a des changements
if git diff --cached --quiet; then
    echo "Aucun changement détecté — repo déjà à jour"
else
    git commit -m "Sync config $(date '+%Y-%m-%d %H:%M')"
    git push
    echo "Config synchronisée avec GitHub !"
fi
