#!/bin/bash
# Skript pro instalaci Cockpit, pluginu pro sdílení souborů a konfiguraci Samby
# na MX Linux (Debian-based)

# Nastavení barvy pro hlášky
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funkce pro bezpečné zjištění IP adresy
get_server_ip() {
    # Pokus 1: Standardní a čistý způsob
    IP_ADDRESS=$(hostname -I 2>/dev/null | awk '{print $1}')
    
    # Pokus 2: Pokud hostname nefunguje, použijeme ip
    if [ -z "$IP_ADDRESS" ]; then
        # Hledáme IP V4, která není loopback (127.0.0.1)
        IP_ADDRESS=$(ip a 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    fi
    
    echo "$IP_ADDRESS"
}
# ----------------------------------------------------------------------

echo -e "${GREEN}### 1. Aktualizace systému a instalace základních balíčků ###${NC}"
sudo apt update || { echo -e "${RED}Chyba při aktualizaci repozitářů!${NC}"; exit 1; }
sudo apt upgrade -y
sudo apt install -y curl nano

echo -e "${GREEN}### 2. Instalace Cockpit Web Konsole a sluzeb ###${NC}"
sudo apt install -y cockpit samba nfs-kernel-server
sudo systemctl enable --now cockpit.socket

# Zjištění IP adresy (zavolání opravené funkce)
SERVER_IP=$(get_server_ip)

if [ -z "$SERVER_IP" ]; then
    SERVER_ACCESS_INFO="<IP_ADRESA_SERVERU>"
else
    SERVER_ACCESS_INFO="$SERVER_IP"
fi

echo -e "${GREEN}Cockpit je spuštěn a dostupný na https://$SERVER_ACCESS_INFO:9090${NC}"

# ----------------------------------------------------------------------

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
if ! grep -q "$CONFIG_LINE_REGISTRY" "$SAMBA_CONF
