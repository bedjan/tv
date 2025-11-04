#!/bin/bash

# --- Nastavení proměnných ---
SYSTEM_USER="d" 
HOME_SHARE_NAME="home_${SYSTEM_USER}"
HOME_SHARE_PATH="/home/${SYSTEM_USER}/NAS_Sdileny"
SAMBA_USER="${SYSTEM_USER}" # Používáme systémového uživatele jako Samba uživatele

# --- Nastavení USB Auto-Share ---
USB_SHARE_SCRIPT="/usr/local/bin/usb_samba_share.sh"
SMB_CONF="/etc/samba/smb.conf"
SHARE_NAME_PREFIX="USB-DISK-"
SAMBA_GROUP="samba_users"

# --- Zkontrolovat, zda skript běží jako root ---
if [ "$EUID" -ne 0 ]; then
  echo "Tento skript musí být spuštěn s právy root (sudo)."
  exit 1
fi

echo "🚀 Spouštím kompletní instalaci NAS (Cockpit, Samba, Home Share, Auto-USB Share) na MX Linux."

# 1. Kontrola uživatele 'd' a skupiny
echo "1/7: Kontroluji uživatele a skupiny..."
if ! id "${SYSTEM_USER}" &>/dev/null; then
    echo "🚨 Chyba: Systémový uživatel '${SYSTEM_USER}' nebyl nalezen. Skript končí."
    exit 1
fi
groupadd "${SAMBA_GROUP}" 2>/dev/null
usermod -aG "${SAMBA_GROUP}" "${SAMBA_USER}"

# 2. Aktualizace a Instalace softwaru
echo "2/7: Aktualizuji a instaluji balíčky (Cockpit, Samba, File Sharing, usbmount)..."
apt update -y
# Instalace hlavních balíčků
apt install -y cockpit samba cockpit-file-sharing usbmount
# usbmount pro automatické připojení USB disků do /media/usbX

# 3. Vytvoření a nastavení Home Share
echo "3/7: Vytvářím trvalou sdílenou složku: ${HOME_SHARE_PATH}"
mkdir -p "${HOME_SHARE_PATH}"
chown -R "${SYSTEM_USER}":"${SYSTEM_USER}" "${HOME_SHARE_PATH}"
chmod -R 770 "${HOME_SHARE_PATH}"

# Konfigurace trvalého Home Share v Sambě (ručně, aby to fungovalo okamžitě)
echo "   -> Konfiguruji trvalé sdílení v ${SMB_CONF}"
cat <<EOF >> $SMB_CONF

[${HOME_SHARE_NAME}]
    comment = Home Share for ${SYSTEM_USER}
    path = ${HOME_SHARE_PATH}
    read only = no
    guest ok = no
    browsable = yes
    valid users = @${SAMBA_GROUP}
    create mask = 0770
    directory mask = 0770
EOF

# 4. Nastavení hesla Samby
echo "4/7: Nastavuji heslo pro samba uživatele (${SAMBA_USER})."
echo "Zadejte heslo pro samba uživatele (${SAMBA_USER}):"
smbpasswd -a "${SAMBA_USER}"

# 5. Vytvoření Skriptu pro Auto-Sdílení USB disků
echo "5/7: Vytvářím skript pro automatické sdílení USB disků: ${USB_SHARE_SCRIPT}"
cat <<'EOF' > "${USB_SHARE_SCRIPT}"
#!/bin/bash
# Skript pro automatické přidání/odebrání sdílené složky Samby.

SMB_CONF="/etc/samba/smb.conf"
SHARE_NAME_PREFIX="USB-DISK-"

ACTION="$1"
DEVICE_DIR="$2"

DEVICE_NAME=$(basename "$DEVICE_DIR")
SHARE_NAME="${SHARE_NAME_PREFIX}${DEVICE_NAME}"

if [ "$ACTION" = "add" ]; then
    echo "PŘIPOJENÍ: Přidávám sdílení pro $DEVICE_DIR"
    
    # --- Zápis do smb.conf ---
    cat <<EOT >> $SMB_CONF

[${SHARE_NAME}]
    comment = USB External Drive ${DEVICE_NAME}
    path = ${DEVICE_DIR}
    read only = no
    guest ok = no
    browsable = yes
    valid users = @samba_users
    create mask = 0770
    directory mask = 0770
EOT

    # Zajištění přístupu po připojení usbmountem
    chmod -R 777 "${DEVICE_DIR}"
    
    systemctl restart smbd

elif [ "$ACTION" = "remove" ]; then
    echo "ODPOJENÍ: Odebírám sdílení pro $DEVICE_DIR"

    # Odstranění sekce z smb.conf
    sed -i "/^\[${SHARE_NAME}\]/,/^$/d" $SMB_CONF
    sed -i '/^$/N;/^\n$/D' $SMB_CONF # Čištění prázdných řádků

    systemctl restart smbd
fi
EOF

# Nastavení oprávnění pro skript
chmod +x "${USB_SHARE_SCRIPT}"

# 6. Vytvoření Pravidla UDEV
echo "6/7: Vytvářím pravidlo udev pro spouštění skriptu při připojení USB disku."
UDEV_RULES_FILE="/etc/udev/rules.d/99-usb-samba.rules"
cat <<EOF > "${UDEV_RULES_FILE}"
# Spustit náš skript, když se připojí/odpojí zařízení USB (cílí na adresáře /media/usbX od usbmount)
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", KERNEL=="sd[a-z][0-9]", RUN+="${USB_SHARE_SCRIPT} add /media/%k"
ACTION=="remove", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", KERNEL=="sd[a-z][0-9]", RUN+="${USB_SHARE_SCRIPT} remove /media/%k"
EOF

# Aktivace pravidel udev
udevadm control --reload-rules
udevadm trigger

# 7. Spuštění a Restart služeb
echo "7/7: Povoluji a restartuji služby Cockpit a Samba."
systemctl restart samba
systemctl enable cockpit.socket
systemctl start cockpit.socket

# --- Dokončení ---
echo ""
echo "✅ Instalace DOKONČENA!"
echo ""
echo "--- Přístupové body ---"
echo "1. WEB GUI (Cockpit): https://$(hostname -I | awk '{print $1}'):9090"
echo "   -> Přihlášení: Systémový uživatel '${SYSTEM_USER}' a jeho heslo."
echo "2. TRVALÉ SDÍLENÍ: \\\\$(hostname -I | awk '{print $1}')\\${HOME_SHARE_NAME}"
echo "   -> Cesta: ${HOME_SHARE_PATH}"
echo "3. USB SDÍLENÍ: \\\\$(hostname -I | awk '{print $1}')\\USB-DISK-usb[0-9]"
echo "   -> Automaticky se objeví po připojení USB disku."
echo "   -> Přihlášení k Sambě: Uživatel '${SAMBA_USER}' a jeho Samba heslo."
echo "-------------------"
