#!/bin/bash

# --- Nastavení Proměnných ---
SYSTEM_USER="d" # Váš primární uživatel
AGENT_INSTALL_DIR="/home/${SYSTEM_USER}/agent_dvr"
AGENT_USER="agentdvr" # Speciální uživatel pro spouštění služby
AGENT_PORT=8090

# --- Zkontrolovat, zda skript běží jako root ---
if [ "$EUID" -ne 0 ]; then
  echo "Tento skript musí být spuštěn s právy root (sudo)."
  exit 1
fi

echo "🚀 Spouštím přímou instalaci Agent DVR do adresáře /home/${SYSTEM_USER}/agent_dvr."

# 1. Instalace Závislostí (.NET Runtime)
echo "1/4: Instaluji potřebné knihovny a .NET Runtime..."

# Zajištění HTTPS a CURL
apt update -y
apt install -y curl apt-transport-https

# Přidání klíče a repozitáře Microsoftu pro .NET
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/debian/11/prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/microsoft-dotnet.list
apt update -y

# Instalace .NET 6 Runtime
apt install -y dotnet-runtime-6.0

# 2. Vytvoření uživatele a instalace Agent DVR
echo "2/4: Vytvářím uživatele '${AGENT_USER}' a instaluji Agent DVR do ${AGENT_INSTALL_DIR}..."

# Vytvoření uživatele, pod kterým bude Agent běžet (bez přístupu do shellu)
useradd -r -s /bin/false -U "${AGENT_USER}"

# Stažení a rozbalení Agent DVR
mkdir -p "${AGENT_INSTALL_DIR}"
cd "${AGENT_INSTALL_DIR}"
wget https://ispy.s3.eu-west-2.amazonaws.com/Agent.zip
unzip Agent.zip
rm Agent.zip

# Nastavení oprávnění: vlastnictví uživatele "d", aby se k němu dalo přistupovat přes Sambu, ale služba poběží pod agentdvr.
chown -R "${SYSTEM_USER}":"${SYSTEM_USER}" "${AGENT_INSTALL_DIR}"
chmod -R 775 "${AGENT_INSTALL_DIR}" # Zajištění dostatečných oprávnění pro službu i uživatele

# 3. Vytvoření Systemd Služby pro Automatické Spouštění
echo "3/4: Nastavuji službu Systemd pro automatický start pod uživatelem '${AGENT_USER}'..."

cat <<EOF > /etc/systemd/system/agentdvr.service
[Unit]
Description=Agent DVR Camera Monitoring System
After=network.target

[Service]
Type=simple
User=${AGENT_USER}  # Spuštění pod vyhrazeným uživatelem
Group=${AGENT_USER}
WorkingDirectory=${AGENT_INSTALL_DIR}
ExecStart=/usr/bin/dotnet ${AGENT_INSTALL_DIR}/Agent.dll
Restart=always
RestartSec=5
# Důležité: Služba agentdvr musí mít právo zapisovat do adresáře ${AGENT_INSTALL_DIR},
# což zajistí správné nastavení oprávnění v kroku 2.

[Install]
WantedBy=multi-user.target
EOF

# 4. Povolení a Spuštění Služby
echo "4/4: Povoluji a startuji službu Agent DVR."
systemctl daemon-reload
systemctl enable agentdvr.service
systemctl start agentdvr.service

# --- Dokončení ---
echo ""
echo "✅ Instalace Agent DVR DOKONČENA!"
echo ""
echo "--- Přístup ---"
echo "1. Agent DVR běží jako služba a ukládá data do /home/${SYSTEM_USER}/agent_dvr."
echo "2. Otevřete webový prohlížeč a přejděte na:"
echo "   http://$(hostname -I | awk '{print $1}'):${AGENT_PORT}"
echo "3. Nyní můžete v rozhraní Agent DVR nastavit Topodome kamery, vypnout detekci Agent DVR a aktivovat spouštění nahrávání přes ONVIF události/HTTP příkazy."
echo "-------------------"
