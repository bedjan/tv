#!/bin/bash
# Skript pro instalaci Cockpit, Samby a konfiguraci sdílení souborů na MX Linux.

# Nastavení barvy pro hlášky
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funkce pro bezpečné zjištění IP adresy
get_server_ip() {
    IP_ADDRESS=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$IP_ADDRESS" ]; then
        IP_ADDRESS=$(ip a 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    fi
    echo "$IP_ADDRESS"
}

# ----------------------------------------------------------------------

echo -e "${GREEN}### 1. Aktualizace systému a instalace základních balíčků ###${NC}"
# Tato aktualizace může stále hlásit chyby 404, pokud systém ještě nezapomněl na starý MS repozitář.
sudo apt update || echo -e "${YELLOW}Upozornění: Aktualizace možná hlásí staré chyby MS repozitáře. Instalace pokračuje.${NC}"
sudo apt upgrade -y
sudo apt install -y curl nano apt-transport-https wget

# ----------------------------------------------------------------------

echo -e "${GREEN}### 2. Instalace Cockpit Web Konsole a sluzeb pro Sdílení ###${NC}"
sudo apt install -y cockpit samba nfs-kernel-server
sudo systemctl enable --now cockpit.socket

# Zjištění IP adresy pro informaci o přístupu
SERVER_IP=$(get_server_ip)
if [ -z "$SERVER_IP" ]; then
    SERVER_ACCESS_INFO="<IP_ADRESA_SERVERU>"
else
    SERVER_ACCESS_INFO="$SERVER_IP"
fi

echo -e "${GREEN}Cockpit je spuštěn a dostupný na https://$SERVER_ACCESS_INFO:9090${NC}"

# ----------------------------------------------------------------------

echo -e "${GREEN}### 3. Instalace pluginu cockpit-file-sharing ###${NC}"
# Zjištění URL pro instalaci pluginu (využívá DEB balíček pro focal, který je kompatibilní)
LATEST_DEB_URL=$(curl -s https://api.github.com/repos/45Drives/cockpit-file-sharing/releases/latest | grep "browser_download_url" | grep "focal_all.deb" | cut -d : -f 2,3 | tr -d \" | sed 's/ //g')

if [ -z "$LATEST_DEB_URL" ]; then
    echo -e "${YELLOW}Upozornění: Nepodařilo se najít odkaz na nejnovější DEB balíček pro file-sharing. Plugin nebude nainstalován. ${NC}"
else
    TEMP_DEB_FILE="/tmp/cockpit-file-sharing.deb"
    echo -e "Stahování: $LATEST_DEB_URL"
    curl -Lo "$TEMP_DEB_FILE" "$LATEST_DEB_URL"
    
    echo "Instalace staženého DEB balíčku..."
    sudo apt install -y "$TEMP_DEB_FILE" || { echo -e "${RED}Chyba při instalaci DEB balíčku!${NC}"; exit 1; }
    rm "$TEMP_DEB_FILE"
fi

# ----------------------------------------------------------------------

echo -e "${GREEN}### 4. Konfigurace Samby (smb.conf) pro domovské a USB disky ###${NC}"
SAMBA_CONF="/etc/samba/smb.conf"
CONFIG_LINE_REGISTRY="include = registry"

# 4a. Povolení pluginu v globální sekci
if ! grep -q "$CONFIG_LINE_REGISTRY" "$SAMBA_CONF"; then
    echo "Pridavam 'include = registry' pro kompatibilitu s Cockpit pluginem."
    sudo sed -i '/^\[global\]/a\    include = registry' "$SAMBA_CONF"
fi

# 4b. Přidání sekce [homes] a [USB-disky]
echo "Přidávám konfiguraci pro sdílení [homes] a [USB-disky]."

# Odstranění potenciálně duplicitních sekcí před přidáním
sudo sed -i '/^\[homes\]/,/^$/d' "$SAMBA_CONF"
sudo sed -i '/^\[USB-disky\]/,/^$/d' "$SAMBA_CONF"

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

# ----------------------------------------------------------------------

echo -e "${YELLOW}### KONEČNÁ KONTROLA A UPOZORNĚNÍ ###${NC}"
echo "1. ${RED}Uživatelé Samby:${NC} Nezapomeňte vytvořit Samba heslo pro uživatele, kteří mají přistupovat k [homes] sdílení:"
echo "   -> ${RED}sudo smbpasswd -a <vase_jmeno_uzivatele>${NC}"
echo "2. ${RED}USB disky:${NC} Jsou sdíleny přes /media. Pro plný zápis se ujistěte, že je disk naformátován na FAT32/NTFS nebo má nastavená správná oprávnění."
echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ INSTALACE A KONFIGURACE DOKONČENA!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo "Přístup k webové konzoli pro grafickou správu:"
echo "   -> ${RED}https://$SERVER_ACCESS_INFO:9090${NC}"
