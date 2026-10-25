#!/bin/bash
source /home/immich/.env
LOG="/home/immich/backup.log"
LOCKFILE="/tmp/backup.lock"

notify() {
    curl -s -H "Title: $1" -H "Priority: $2" -H "Tags: warning,floppy_disk" -d "$3" "$NTFY_URL" > /dev/null 2>&1
}
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"; }

# Verrou : une seule sauvegarde a la fois
if [ -f "$LOCKFILE" ]; then
    log "Sauvegarde deja en cours, abandon"
    exit 0
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# 1. Le bon HDD de backup est monte
MOUNTED_UUID=$(sudo blkid -s UUID -o value "$(findmnt -n -o SOURCE /mnt/backup)" 2>/dev/null)
if [ "$MOUNTED_UUID" != "$HDD_UUID" ]; then
    log "ERREUR: HDD backup non monte ou mauvais disque"
    notify "❌ HDD Backup non branché" "urgent" "Le HDD de sauvegarde n'est pas monté — rsync annulé"
    exit 1
fi

# 2. Le pool est complet (sinon --delete effacerait des fichiers du backup)
if ! mountpoint -q /mnt/freebox-ssd || ! mountpoint -q /mnt/freebox-hdd \
   || ! mount | grep -q "photos:freebox-ssd:freebox-hdd on /mnt/immich-pool" \
   || [ ! -d /mnt/immich-pool/library ]; then
    log "ERREUR: pool incomplet - rsync annule pour proteger le backup"
    notify "❌ Sauvegarde annulée" "urgent" "Pool incomplet (disques Freebox absents) — rsync annulé pour protéger le backup"
    exit 1
fi

log "Debut de la sauvegarde"
rsync -a --delete --max-delete=500 \
    --exclude='*.tmp' \
    --exclude='lost+found' \
    --exclude='.DS_Store' \
    --exclude='._.DS_Store' \
    --exclude='.fbxgrabberd/' \
    --exclude='.fbxtimeshifting/' \
    --exclude='backups/' \
    --exclude='encoded-video/' \
    --stats \
    /mnt/immich-pool/ /mnt/backup/ >> "$LOG" 2>&1
RSYNC_EXIT=$?

if [ $RSYNC_EXIT -eq 0 ]; then
    log "Sauvegarde terminee avec succes"
elif [ $RSYNC_EXIT -eq 25 ]; then
    log "ERREUR: plus de 500 suppressions demandees - arret par securite"
    notify "⚠️ Sauvegarde bloquée" "urgent" "rsync voulait supprimer plus de 500 fichiers — arrêt par sécurité, vérification nécessaire"
else
    log "ERREUR lors de la sauvegarde - Code: $RSYNC_EXIT"
    notify "❌ Sauvegarde échouée" "high" "Erreur rsync, code $RSYNC_EXIT"
fi
