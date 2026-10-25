#!/bin/bash
source /home/immich/.env
LOG="/home/immich/monitor.log"
BRANCHES="photos freebox-ssd freebox-hdd"

notify() { curl -s -H "Title: $1" -H "Priority: $2" -H "Tags: $3" -d "$4" "$NTFY_URL" > /dev/null 2>&1; }
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"; }

remount_cifs() {
    umount -l "$1" 2>/dev/null
    sleep 2
    mount "$1" 2>/dev/null
    sleep 3
    mountpoint -q "$1"
}

# Temoin lisible a travers le pool (2 essais)
sentinel_ok() {
    for i in 1 2; do
        timeout -s KILL 20 cat "/mnt/immich-pool/.sentinel-$1" > /dev/null 2>&1 && return 0
        sleep 5
    done
    return 1
}

# 1. Montages SMB Freebox
for m in /mnt/freebox-ssd /mnt/freebox-hdd; do
    if ! mountpoint -q "$m"; then
        log "$m non monte - tentative de remontage"
        notify "⚠️ Disque Freebox inaccessible" "high" "warning,cd" "$m non monté — remontage en cours"
        if remount_cifs "$m"; then
            log "$m remonte avec succes"
            notify "✅ Disque Freebox remonté" "default" "white_check_mark,cd" "$m de nouveau accessible"
        else
            log "ERREUR: $m toujours inaccessible"
            notify "❌ Disque Freebox inaccessible" "urgent" "warning,cd" "Impossible de remonter $m — intervention requise"
        fi
    fi
done
{ mountpoint -q /mnt/freebox-ssd && mountpoint -q /mnt/freebox-hdd; } || exit 0

# 2. Pool complet ET tous les disques lisibles
REASON=""
mount | grep -q "photos:freebox-ssd:freebox-hdd on /mnt/immich-pool" || REASON="branches manquantes"
if [ -z "$REASON" ]; then
    for b in $BRANCHES; do
        sentinel_ok "$b" || { REASON="disque $b invisible dans le pool"; break; }
    done
fi
[ -z "$REASON" ] && exit 0

# 3. Reconstruction
log "Pool degrade ($REASON) - reconstruction"
notify "🔧 Pool dégradé" "high" "warning,wrench" "$REASON — reconstruction en cours"
cd /home/immich/immich && docker compose down >> "$LOG" 2>&1
umount /mnt/immich-pool 2>/dev/null || umount -l /mnt/immich-pool 2>/dev/null
remount_cifs /mnt/freebox-ssd
remount_cifs /mnt/freebox-hdd
mergerfs /mnt/photos:/mnt/freebox-ssd:/mnt/freebox-hdd /mnt/immich-pool \
    -o defaults,allow_other,use_ino,category.create=mfs 2>> "$LOG"
cd /home/immich/immich && docker compose up -d >> "$LOG" 2>&1

OK=1
for b in $BRANCHES; do sentinel_ok "$b" || OK=0; done
if [ $OK -eq 1 ]; then
    log "Pool reconstruit avec succes - capacite $(df -h /mnt/immich-pool | tail -1 | awk '{print $2}')"
    notify "✅ Pool reconstruit" "default" "white_check_mark,cd" "Tous les disques sont de nouveau lisibles"
else
    log "ERREUR: reconstruction du pool echouee"
    notify "❌ Reconstruction échouée" "urgent" "warning,cd" "Le pool reste dégradé ($REASON) — intervention requise"
fi
