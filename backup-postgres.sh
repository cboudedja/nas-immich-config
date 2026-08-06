#!/bin/bash
LOG="/home/immich/backup-postgres.log"
source /home/immich/.env
BACKUP_DIR="/mnt/backup/postgres"
DATE=$(date '+%Y-%m-%d')


# Vérifier que le bon HDD backup est monté
MOUNTED_UUID=$(sudo blkid -s UUID -o value $(findmnt -n -o SOURCE /mnt/backup) 2>/dev/null)
if [ "$MOUNTED_UUID" != "$HDD_UUID" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERREUR: HDD backup non monté ou mauvais disque" >> $LOG
    curl -s -H "Title: ❌ HDD Backup non branché" -H "Priority: urgent" -H "Tags: warning,cd" \
        -d "Le HDD de sauvegarde n'est pas branché — backup PostgreSQL annulé" \
        "$NTFY_URL" > /dev/null 2>&1
    exit 1
fi

mkdir -p $BACKUP_DIR

echo "$(date '+%Y-%m-%d %H:%M:%S') - Debut sauvegarde PostgreSQL" >> $LOG

docker exec immich_postgres pg_dump -U postgres immich | gzip > $BACKUP_DIR/immich-$DATE.sql.gz

if [ $? -eq 0 ]; then
    SIZE=$(du -sh $BACKUP_DIR/immich-$DATE.sql.gz | awk '{print $1}')
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Sauvegarde PostgreSQL terminee - $SIZE" >> $LOG
    # Garder uniquement les 30 derniers dumps
    ls -t $BACKUP_DIR/*.sql.gz | tail -n +8 | xargs rm -f 2>/dev/null
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERREUR sauvegarde PostgreSQL" >> $LOG
    curl -s -H "Title: ❌ Backup PostgreSQL échoué" -H "Priority: high" -H "Tags: warning,database" \
        -d "La sauvegarde de la base de données Immich a échoué" \
        "$NTFY_URL" > /dev/null 2>&1
fi
