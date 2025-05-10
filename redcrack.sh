#!/bin/bash

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

echo -e "${CYAN}Ejecutando Script redcrack.sh${NC}"


#----------------------------------------------------------------------------------------------

# Verificación y descarga de la última versión de redcrack.sh

echo -e "${CYAN}Verificando ultima version de Script disponible...${NC}"
REPO_URL="https://raw.githubusercontent.com/Guido-Romano/redcrack/main/redcrack.sh"
LOCAL_HASH=$(sha256sum "$0" | awk '{print $1}')
REMOTE_HASH=$(wget -qO- "$REPO_URL" | sha256sum | awk '{print $1}')

if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
    echo -e "${YELLOW}Se encontró una nueva versión de redcrack.sh. Descargando...${NC}"
    wget -qO "$0" "$REPO_URL"
    echo -e "${GREEN}Actualización completada. Reiniciando el script...${NC}"
    exec bash "$0" # Reinicia el script automáticamente
    exit 0
else
    echo -e "${GREEN}Ya tienes la última versión de redcrack.sh.${NC}"
fi


#----------------------------------------------------------------------------------------------

# Comprobacion y descarga de dependencias

for pkg in xmlstarlet wget aircrack-ng iw wireless-tools grep awk sed mate-terminal; do
    if ! command -v "$pkg" &> /dev/null; then
        echo -e "${YELLOW}Instalando dependencia: $pkg${NC}"
        sudo apt-get install -y "$pkg"
    fi
done

# Verificación y descarga oui.txt
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
        echo -e "${GREEN}Archivo 'oui.txt' actualizado correctamente.${NC}"
    else
        echo -e "${GREEN}El archivo 'oui.txt' está actualizado.${NC}"
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

echo -e "${GREEN}Interfaz en modo monitor: $INTERFAZ_MONITOR${NC}"

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
echo -e "${GREEN}Modo monitor detenido en $INTERFAZ_MONITOR${NC}"
sudo service NetworkManager restart
sudo dhclient "$INTERFAZ"
echo -e "${CYAN}Conexión restablecida${NC}"