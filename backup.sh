#!/bin/bash

source ~/.env
# Verrou pour éviter deux instances simultanées
LOG="/home/immich/backup.log"
LOCKFILE="/tmp/backup.lock"


# Vérifier que le bon HDD backup est monté
MOUNTED_UUID=$(sudo blkid -s UUID -o value $(findmnt -n -o SOURCE /mnt/backup) 2>/dev/null)
if [ "$MOUNTED_UUID" != "$HDD_UUID" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERREUR: HDD backup non monté ou mauvais disque" >> $LOG
    curl -s -H "Title: ❌ HDD Backup non branché" -H "Priority: urgent" -H "Tags: warning,cd" \
        -d "Le HDD de sauvegarde n'est pas branché — rsync annulé" \
        "$NTFY_URL" > /dev/null 2>&1
    exit 1
fi

if [ -f "$LOCKFILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Sauvegarde deja en cours, abandon" >> $LOG
    exit 0
fi
touch "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT


echo "$(date '+%Y-%m-%d %H:%M:%S') - Debut de la sauvegarde" >> $LOG

rsync -a --delete \
    --exclude='*.tmp' \
    --exclude='lost+found' \
    --exclude='.DS_Store' \
    --exclude='._.DS_Store' \
    --exclude='.fbxgrabberd/' \
    --exclude='.fbxtimeshifting/' \
    --exclude='backups/' \
    --exclude='encoded-video/' \
    --stats \
    /mnt/immich-pool/ /mnt/backup/ >> $LOG 2>&1
RSYNC_EXIT=$?

if [ $RSYNC_EXIT -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Sauvegarde terminee avec succes" >> $LOG
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERREUR lors de la sauvegarde - Code: $RSYNC_EXIT" >> $LOG
fi
