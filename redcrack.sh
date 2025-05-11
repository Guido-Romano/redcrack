#!/bin/bash

VERSION="0.0.1"
set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

REPO_URL="https://raw.githubusercontent.com/Guido-Romano/redcrack/main/redcrack.sh"
SCRIPT_PATH="$0"

# --- Verificar nueva version ---
echo -e "Comprobando última versión disponible..."

LOCAL_HASH=$(sha256sum "$SCRIPT_PATH" | awk '{print $1}')
REMOTE_CONTENT=$(curl -fsSL "$REPO_URL" || echo "")

if [[ -n "$REMOTE_CONTENT" ]]; then
    REMOTE_HASH=$(echo "$REMOTE_CONTENT" | sha256sum | awk '{print $1}')
    if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
        echo -e "${YELLOW}Nueva versión disponible. Actualizando...${NC}"
        TMP_SCRIPT="$(mktemp)"
        echo "$REMOTE_CONTENT" > "$TMP_SCRIPT"
        chmod +x "$TMP_SCRIPT"
        echo -e "${CYAN}Reiniciando con nueva versión...${NC}"
        exec bash "$TMP_SCRIPT"
        exit 0
    fi
else
    echo -e "${YELLOW}No se pudo verificar la última versión. Continuando con la versión actual...${NC}"
fi

# --- Banner ---
echo
echo -e "${RED}"
cat << "EOF"
                                 88                                                  88         
                                 88                                                  88         
                                 88                                                  88         
8b,dPPYba,   ,adPPYba,   ,adPPYb,88   ,adPPYba,  8b,dPPYba,  ,adPPYYba,   ,adPPYba,  88   ,d8   
88P'   "Y8  a8P_____88  a8"    `Y88  a8"     ""  88P'   "Y8  ""     `Y8  a8"     ""  88 ,a8"    
88          8PP"""""""  8b       88  8b          88          ,adPPPPP88  8b          8888[      
88          "8b,   ,aa  "8a,   ,d88  "8a,   ,aa  88          88,    ,88  "8a,   ,aa  88`"Yba,   
88           `"Ybbd8"'   `"8bbdP"Y8   `"Ybbd8"'  88          `"8bbdP"Y8   `"Ybbd8"'  88   `Y8a  
EOF

echo -e "${WHITE}  By apocca V$VERSION${NC}"

# --- Dependencias ---
for pkg in xmlstarlet wget aircrack-ng iw wireless-tools grep awk sed mate-terminal; do
    if ! command -v "$pkg" &> /dev/null; then
        echo -e "${YELLOW}Instalando dependencia: $pkg${NC}"
        sudo apt-get install -y "$pkg"
    fi
done

# --- Verificar oui.txt ---
OUI_URL="https://standards-oui.ieee.org/oui/oui.txt"
LATEST_HASH_URL="https://standards-oui.ieee.org/oui/oui.txt.sha256"

if [ ! -f "oui.txt" ]; then
    echo -e "${YELLOW}Descargando archivo 'oui.txt'...${NC}"
    wget "$OUI_URL" -O oui.txt
else
    echo -e "${CYAN}'oui.txt' ya existe. Verificando si está actualizado...${NC}"

    OUI_HASH="$(sha256sum oui.txt | awk '{print $1}')"
    LATEST_HASH="$(wget -qO- "$LATEST_HASH_URL" | awk '{print $1}' || echo "")"

    if [[ "$LATEST_HASH" != "$OUI_HASH" && -n "$LATEST_HASH" ]]; then
        echo -e "${RED}El archivo 'oui.txt' está desactualizado. Descargando nueva versión...${NC}"
        wget "$OUI_URL" -O oui.txt
        echo -e "${NC}Archivo 'oui.txt' actualizado correctamente.${NC}"
    else
        echo -e "${NC}El archivo 'oui.txt' está actualizado.${NC}"
    fi
fi


#----------------------------------------------------------------------------------------------


# Comprobacion de modo monitor

INTERFAZ=$(airmon-ng | awk 'NR>2 && $1!="" {print $2; exit}')

if [ -z "$INTERFAZ" ]; then
    echo -e "${RED}No se encontró ninguna interfaz inalámbrica.${NC}"
    exit 1
fi

if ! iwconfig "$INTERFAZ" 2>/dev/null | grep -q "Mode:Monitor"; then
    echo -e "${YELLOW}La interfaz $INTERFAZ no está en modo monitor. Configurando...${NC}"
    sudo airmon-ng check kill > /dev/null 2>&1
    sudo airmon-ng start "$INTERFAZ" > /dev/null
    INTERFAZ_MONITOR=$(iwconfig 2>/dev/null | awk '/Mode:Monitor/ {print $1}' | head -n1)
    
    if [ -z "$INTERFAZ_MONITOR" ]; then
        echo -e "${RED}Fallo al activar modo monitor.${NC}"
        exit 1
    fi
else
    INTERFAZ_MONITOR="$INTERFAZ"
fi

echo -e "${NC}Interfaz en modo monitor: $INTERFAZ_MONITOR${NC}"

rm -f captura*.*

echo -e "${YELLOW}Abriendo airodump-ng en esta terminal...${NC}"
airodump-ng "$INTERFAZ_MONITOR" --band abg --write captura --output-format netxml,csv &
AIROD_PID=$!

read -p "Presioná ENTER cuando quieras procesar los resultados..."

kill "$AIROD_PID"
sleep 2

sed -i '/<!DOCTYPE.*kismet.*dtd">/d' captura-01.kismet.netxml

if [ ! -f captura-01.kismet.netxml ]; then
    echo -e "${RED}Error: El archivo de captura no se generó correctamente.${NC}"
    exit 1
fi


#----------------------------------------------------------------------------------------------

echo -e "\n${CYAN}========== REDES DETECTADAS ==========${NC}\n"
printf "%-22s %-20s %-36s %-8s %-6s %-30s\n" "Red" "MAC (punto de acceso)" "Fabricante" "Intens." "Canal" "Encriptación"

xmlstarlet sel --skip-dtd -t -m "//wireless-network[@type='infrastructure']" \
  -v "SSID/essid" -o "|" \
  -v "BSSID" -o "|" \
  -v "snr-info/last_signal_dbm" -o "|" \
  -v "channel" -o "|" \
  -v "SSID/encryption" -o "|" \
  -v "manuf" -n captura-01.kismet.netxml 2>/dev/null | while IFS='|' read -r essid bssid signal channel enc fabricante; do
    [ -z "$essid" ] && essid="(oculta)"
    [ -z "$fabricante" ] && fabricante="Unknown"
    printf "%-22s %-20s %-36s %-8s %-6s %-30s\n" "$essid" "$bssid" "$fabricante" "$signal" "$channel" "$enc"
done

# 4) DETENER MODO MONITOR Y RESTABLECER CONEXIÓN
sudo airmon-ng stop "$INTERFAZ_MONITOR"
echo -e "${NC}Modo monitor detenido en $INTERFAZ_MONITOR${NC}"
sudo service NetworkManager restart
sudo dhclient "$INTERFAZ"
echo -e "${CYAN}Conexión restablecida${NC}"