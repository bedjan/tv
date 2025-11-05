#!/bin/bash
# Skript pro instalaci Cockpit, pluginu pro sdílení souborů a konfiguraci Samby
# na MX Linux (Debian-based)

# Nastavení barvy pro hlášky
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}### 1. Aktualizace systému a instalace základních balíčků ###${NC}"
sudo apt update || { echo -e "${RED}Chyba při aktualizaci repozitářů!${NC}"; exit 1; }
sudo apt upgrade -y
sudo apt install -y curl nano

echo -e "${GREEN}### 2. Instalace Cockpit Web Konsole a sluzeb ###${NC}"
sudo apt install -y cockpit samba nfs-kernel-server
sudo systemctl enable --now cockpit.socket

# >>> OPRAVENÁ ČÁST PRO ŘÁDEK 10 (nebo blízko něj)
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(ip a 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
fi

if [ -z "$SERVER_IP" ]; then
    SERVER_ACCESS_INFO="<IP_ADRESA_SERVERU>"
else
    SERVER_ACCESS_INFO="$SERVER_IP"
fi

echo -e "${GREEN}Cockpit je spuštěn a dostupný na https://$SERVER_ACCESS_INFO:9090${NC}"
# <<< KONEC OPRAVY

echo -e "${GREEN}### 3. Instalace pluginu cockpit-file-sharing ###${NC}"
# Tato sekce automaticky zjišťuje a stahuje nejnovější DEB balíček
LATEST_DEB_URL=$(curl -s https://api.github.com/repos/45Drives/cockpit-file-sharing/releases/latest | grep "browser_download_url" | grep "focal_all.deb" | cut -d : -f 2,3 | tr -d \" | sed 's/ //g')

if [ -z "$LATEST_DEB_URL" ]; then
    echo -e "${RED}Nepodařilo se najít odkaz na nejnovější DEB balíček! Pokračuji bez něj.${NC}"
else
    TEMP_DEB_FILE="/tmp/cockpit-file-sharing.deb"
    echo -e "Stahování: $LATEST_DEB_URL"
    curl -Lo "$TEMP_DEB_FILE" "$LATEST_DEB_URL"
    
    echo "Instalace staženého DEB balíčku..."
    sudo apt install -y "$TEMP_DEB_FILE" || { echo -e "${RED}Chyba při instalaci DEB balíčku!${NC}"; exit 1; }
    rm "$TEMP_DEB_FILE"
fi

echo -e "${GREEN}### 4. Konfigurace Samby (smb.conf) pro domovské a USB disky ###${NC}"
SAMBA_CONF="/etc/samba/smb.conf"
CONFIG_LINE_REGISTRY="include = registry"

# 4a. Povolení pluginu v globální sekci
if ! grep -q "$CONFIG_LINE_REGISTRY" "$SAMBA_CONF"; then
    echo "Pridavam 'include = registry' pro kompatibilitu s Cockpit pluginem."
    # Přidání pod sekci [global]
    sudo sed -i '/^\[global\]/a\    include = registry' "$SAMBA_CONF"
fi

# 4b. Přidání sekce [homes] a [USB-disky]
echo "Pridavam konfiguraci pro automaticke sdileni [homes] a [USB-disky]."
sudo tee -a "$SAMBA_CONF" > /dev/null << EOF

# =======================================================
# SEKCE PŘIDANÉ PRO COCKPIT A AUTOMATICKÉ SDÍLENÍ
# =======================================================

[homes]
    comment = Home Directories
    browseable = no
    read only = no
    create mask = 0600
    directory mask = 0700
    valid users = %S
    writable = yes
    
[USB-disky]
    comment = Pripojene USB disky a media
    path = /media
    browseable = yes
    read only = no
    guest ok = yes
    writable = yes
    public = yes
    create mask = 0777
    directory mask = 0777
    force user = nobody
    force group = nogroup
EOF

echo -e "${GREEN}### 5. Restart Samba služby ###${NC}"
sudo systemctl restart smbd
echo -e "${GREEN}Samba služba restartována.${NC}"

echo -e "${YELLOW}### DŮLEŽITÉ UPOZORNĚNÍ K USB DISKŮM A 'usbmount' ###${NC}"
echo "Balíček 'usbmount' není na moderních desktopových distribucích jako MX Linux potřeba."
echo "MX Linux používá pro automatické připojování (auto-mounting) diskových jednotek"
echo "jiné nástroje (UDisks/GVFS/Thunar), které připojují disky do složky ${RED}/media/<vase_jmeno>/${NC}."
echo "Konfigurace [USB-disky] sdílí celou složku ${RED}/media${NC}, což by mělo zajistit přístup"
echo "ke všem připojeným diskům, jak jste si přál."
echo -e "${YELLOW}Pro funkční zápis na sdílené USB disky se ujistěte, že je disk naformátován na systém souborů (jako např. FAT32 nebo NTFS), který respektuje jednoduchá oprávnění, nebo že se připojená jednotka automaticky mountuje s oprávněním pro zápis pro všechny (jak je obvyklé).${NC}"

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ Instalace a konfigurace DOKONČENA!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo "Přístup k webové konzoli pro grafickou správu:"
echo -e "   -> ${RED}https://$SERVER_ACCESS_INFO:9090${NC}"
echo "Připojení k Samba sdílení:"
echo "   -> Domovský adresář: \\\\$SERVER_ACCESS_INFO\\<vase_jmeno_uzivatele>"
echo "   -> USB disky: \\\\$SERVER_ACCESS_INFO\\USB-disky"
