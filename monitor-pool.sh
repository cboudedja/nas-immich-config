#!/bin/bash
LOG="/home/immich/monitor.log"
source ~/.env


notify() {
    curl -s -H "Title: $1" -H "Priority: $2" -H "Tags: $3" -d "$4" "$NTFY_URL" > /dev/null 2>&1
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG
}

# Vérifier le montage SSD Freebox
if ! mountpoint -q /mnt/freebox-ssd; then
    log "SSD Freebox non monté — envoi alerte et tentative de remontage"
    notify "⚠️ SSD Freebox inaccessible" "high" "warning,cd" "Le SSD Freebox est inaccessible — tentative de remontage en cours"
    ls /mnt/freebox-ssd > /dev/null 2>&1
    sleep 3
    mount /mnt/freebox-ssd 2>/dev/null
    sleep 2
    if mountpoint -q /mnt/freebox-ssd; then
        log "SSD Freebox remonté avec succès"
        notify "✅ SSD Freebox remonté" "default" "white_check_mark,cd" "Le SSD Freebox est de nouveau accessible"
    else
        log "ERREUR: SSD Freebox toujours inaccessible"
        notify "❌ SSD Freebox inaccessible" "urgent" "warning,cd" "Impossible de remonter le SSD Freebox — intervention requise"
    fi
fi

# Vérifier le montage HDD Freebox
if ! mountpoint -q /mnt/freebox-hdd; then
    log "HDD Freebox non monté — envoi alerte et tentative de remontage"
    notify "⚠️ HDD Freebox inaccessible" "high" "warning,cd" "Le HDD Freebox est inaccessible — tentative de remontage en cours"
    ls /mnt/freebox-hdd > /dev/null 2>&1
    sleep 3
    mount /mnt/freebox-hdd 2>/dev/null
    sleep 2
    if mountpoint -q /mnt/freebox-hdd; then
        log "HDD Freebox remonté avec succès"
        notify "✅ HDD Freebox remonté" "default" "white_check_mark,cd" "Le HDD Freebox est de nouveau accessible"
    else
        log "ERREUR: HDD Freebox toujours inaccessible"
        notify "❌ HDD Freebox inaccessible" "urgent" "warning,cd" "Impossible de remonter le HDD Freebox — intervention requise"
    fi
fi

# Vérifier que le pool mergerfs contient les 3 disques
if mountpoint -q /mnt/freebox-ssd && mountpoint -q /mnt/freebox-hdd; then
    BRANCHES=$(mount | grep "/mnt/immich-pool")
    if ! echo "$BRANCHES" | grep -q "photos:freebox-ssd:freebox-hdd"; then
        log "Pool dégradé — reconstruction en cours"
        notify "🔧 Pool dégradé" "high" "warning,wrench" "Reconstruction du pool mergerfs en cours..."
        cd /home/immich/immich && docker compose down 2>> $LOG
        umount /mnt/immich-pool 2>/dev/null
        mergerfs /mnt/photos:/mnt/freebox-ssd:/mnt/freebox-hdd /mnt/immich-pool \
            -o defaults,allow_other,use_ino,category.create=mfs 2>> $LOG
        cd /home/immich/immich && docker compose up -d 2>> $LOG
        sleep 5
        if mount | grep -q "on /mnt/immich-pool type fuse.mergerfs"; then
            POOL_TOTAL=$(df -h /mnt/immich-pool | tail -1 | awk '{print $2}')
            log "Pool reconstruit avec succès — capacité $POOL_TOTAL"
            notify "✅ Pool reconstruit" "default" "white_check_mark,cd" "Pool mergerfs restauré à pleine capacité $POOL_TOTAL"
        else
            log "ERREUR: reconstruction du pool échouée"
            notify "❌ Reconstruction échouée" "urgent" "warning,cd" "Le pool n'a pas pu être reconstruit — intervention requise"
        fi
    fi
fi
