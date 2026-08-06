#!/bin/bash
# Déclencher l'automount des deux disques Freebox
source /home/immich/.env
ls /mnt/freebox-ssd > /dev/null 2>&1
ls /mnt/freebox-hdd > /dev/null 2>&1

# Attendre que les deux soient montés
timeout=60
while [ $timeout -gt 0 ]; do
    if mountpoint -q /mnt/freebox-ssd && mountpoint -q /mnt/freebox-hdd; then
        break
    fi
    ls /mnt/freebox-ssd > /dev/null 2>&1
    ls /mnt/freebox-hdd > /dev/null 2>&1
    sleep 2
    timeout=$((timeout-2))
done

# Démonter le pool existant si monté
umount /mnt/immich-pool 2>/dev/null

# Monter le pool mergerfs avec les 3 disques + Notification de la reconstruction du pool
mergerfs /mnt/photos:/mnt/freebox-ssd:/mnt/freebox-hdd /mnt/immich-pool \
    -o defaults,allow_other,use_ino,category.create=mfs

if [ $? -eq 0 ]; then
    POOL_SIZE=$(df -h /mnt/immich-pool | tail -1 | awk '{print $2}')
    curl -s -H "Title: ✅ Pool monté au démarrage" -H "Priority: default" -H "Tags: white_check_mark" \
        -d "Pool mergerfs opérationnel — capacité $POOL_SIZE" \
        "$NTFY_URL" > /dev/null 2>&1
else
    curl -s -H "Title: ❌ Échec montage pool" -H "Priority: urgent" -H "Tags: warning,cd" \
        -d "Le pool mergerfs n'a pas pu être monté au démarrage — intervention requise" \
        "$NTFY_URL" > /dev/null 2>&1
fi
