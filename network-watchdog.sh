#!/bin/bash
source /home/immich/.env
GATEWAY="192.168.1.254"
LOG="/home/immich/network-watchdog.log"
FAILS_FILE="/var/tmp/watchdog-fails"
REBOOT_FILE="/var/tmp/watchdog-last-reboot"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"; }
check() { ping -c 3 -W 5 "$GATEWAY" > /dev/null 2>&1; }

if check; then
    rm -f "$FAILS_FILE"
    exit 0
fi

{ echo "--- diag $(date) ---"; dmesg | tail -30; /usr/sbin/iw dev wlp2s0 link; ip -br addr; } >> /home/immich/network-diag.log 2>&1
log "Connexion perdue - rechargement du driver Wi-Fi (wl)"
modprobe -r wl
sleep 3
modprobe wl
sleep 30

if check; then
    log "Reconnexion reussie apres rechargement du driver"
    rm -f "$FAILS_FILE"
    curl -s -H "Title: Wi-Fi reconnecte" -H "Tags: white_check_mark" \
        -d "Driver Wi-Fi bloque, recharge automatiquement" "$NTFY_URL" > /dev/null 2>&1
    exit 0
fi

FAILS=$(( $(cat "$FAILS_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$FAILS" > "$FAILS_FILE"
log "ECHEC reconnexion ($FAILS/3)"

if [ "$FAILS" -ge 3 ]; then
    LAST=$(cat "$REBOOT_FILE" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - LAST )) -gt 3600 ]; then
        log "3 echecs consecutifs - redemarrage du serveur"
        date +%s > "$REBOOT_FILE"
        rm -f "$FAILS_FILE"
        systemctl reboot
    else
        log "Reboot deja effectue il y a moins d'1h - pas de nouveau reboot"
    fi
fi
