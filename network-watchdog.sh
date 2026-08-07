#!/bin/bash
source /home/immich/.env

GATEWAY="192.168.1.254"
LOG="/home/immich/network-watchdog.log"

# Tester la connexion vers la Freebox
if ! ping -c 3 -W 5 "$GATEWAY" > /dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Connexion perdue, tentative de reconnexion" >> $LOG

    # Relancer l'interface Wi-Fi
    nmcli device disconnect wlp2s0 2>/dev/null
    sleep 3
    nmcli device connect wlp2s0 2>/dev/null
    sleep 10

    # Vérifier si la reconnexion a réussi
    if ping -c 3 -W 5 "$GATEWAY" > /dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Reconnexion réussie" >> $LOG
        curl -s -H "Title: Wi-Fi reconnecté" -H "Priority: default" -H "Tags: white_check_mark" \
            -d "Le serveur a perdu la connexion puis s'est reconnecté automatiquement" \
            "$NTFY_URL" > /dev/null 2>&1
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ECHEC reconnexion - redemarrage NetworkManager" >> $LOG
        systemctl restart NetworkManager
        sleep 15
    fi
fi
