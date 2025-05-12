#!/bin/bash

# --------------------
# RedCrack - Apocca v0.1.5
# --------------------

VERSION="0.1.5"
set -e

# --- Colores terminal ---
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

REPO_URL="https://raw.githubusercontent.com/Guido-Romano/redcrack/rama01/redcrack.sh"
SCRIPT_PATH="$0"


# Verificar si hay una nueva versión disponible
verificar_actualizacion() {
    if [[ -n "$REMOTE_CONTENT" ]]; then
        REMOTE_HASH=$(echo "$REMOTE_CONTENT" | sha256sum | awk '{print $1}')
        
        # Comparar hashes solo si son diferentes
        if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
            echo -e "\e[33mSe ha detectado una nueva versión del software.\e[0m"
            echo -e "\e[34mVersiones:\e[0m"
            echo -e "  Versión actual: \e[32m$LOCAL_HASH\e[0m"
            echo -e "  Versión nueva:  \e[36m$REMOTE_HASH\e[0m"
            
            # Preguntar explícitamente antes de cualquier actualización
            while true; do
                read -p "¿Desea actualizar el software? (s/n): " respuesta
                
                case "$respuesta" in
                    [sS]|[sS][iI])
                        echo "Iniciando proceso de actualización..."
                        # Aquí solo PREPARAMOS la actualización, NO la ejecutamos automáticamente
                        return 0  # Indica que el usuario quiere actualizar
                        ;;
                    [nN]|[nN][oO])
                        echo "Actualización cancelada. Continuando con la versión actual."
                        return 1  # Indica que el usuario NO quiere actualizar
                        ;;
                    *)
                        echo -e "\e[31mRespuesta inválida. Por favor, responda 's' o 'n'.\e[0m"
                        ;;
                esac
            done
        fi
    else
        echo -e "\e[31mNo se pudo verificar la última versión. Compruebe su conexión a internet.\e[0m"
        return 1
    fi
    
    # Si los hashes son iguales o no hay contenido remoto
    return 1
}

# Función de actualización separada
realizar_actualizacion() {
    if [[ -n "$REMOTE_CONTENT" ]]; then
        # Crear script temporal
        TMP_SCRIPT="$(mktemp)"
        echo "$REMOTE_CONTENT" > "$TMP_SCRIPT"
        chmod +x "$TMP_SCRIPT"
        
        echo "Ejecutando nueva versión..."
        # Cambiar al nuevo script
        exec bash "$TMP_SCRIPT"
        exit 0
    else
        echo "No hay contenido para actualizar."
        exit 1
    fi
}


# verificar si hay actualización

if verificar_actualizacion; then
    # Si el usuario confirma, realizamos la actualización
    read -p "Presione Enter para continuar con la actualización o Ctrl+C para cancelar..." 
    realizar_actualizacion
else
    echo "No se requiere actualización."
fi

# --- Banner ---

echo -e "\n${RED}"
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

echo
echo -e "${WHITE}  By apocca v$VERSION${NC}"


# --- Verificar e instalar dependencias ---

for pkg in xmlstarlet wget aircrack-ng iw wireless-tools grep awk sed mate-terminal; do
    if ! command -v "$pkg" &> /dev/null; then
        echo -e "Instalando dependencias..."
        sudo apt-get install -y "$pkg"
    fi
done

# --- Descarga oui.txt si no está o si hay nueva versión ---

OUI_URL="https://standards-oui.ieee.org/oui/oui.txt"
LATEST_HASH_URL="https://standards-oui.ieee.org/oui/oui.txt.sha256"

if [ ! -f "oui.txt" ]; then
    wget "$OUI_URL" -O oui.txt
else
    OUI_HASH="$(sha256sum oui.txt | awk '{print $1}')"
    LATEST_HASH="$(wget -qO- "$LATEST_HASH_URL" | awk '{print $1}' || echo "")"
    if [[ "$LATEST_HASH" != "$OUI_HASH" && -n "$LATEST_HASH" ]]; then
        wget "$OUI_URL" -O oui.txt
    fi
fi



# --- Comprobación modo monitor ---

INTERFAZ=$(airmon-ng | awk 'NR>2 && $1!="" {print $2; exit}')
if [ -z "$INTERFAZ" ]; then
    echo -e "${RED}No se encontró ninguna interfaz inalámbrica.${NC}"
    exit 1
fi

if ! iwconfig "$INTERFAZ" 2>/dev/null | grep -q "Mode:Monitor"; then
    echo -e "${YELLOW}Cambiando interfaz a modo monitor${NC}"
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

# --- Captura ---
rm -f captura*.*
airodump-ng "$INTERFAZ_MONITOR" --band abg --write captura --output-format netxml,csv &
AIROD_PID=$!

read -p "Presioná ENTER cuando quieras procesar los resultados..."
kill "$AIROD_PID"
sleep 2

# Limpiar DTD innecesario
sed -i '/<!DOCTYPE.*kismet.*dtd">/d' captura-01.kismet.netxml
if [ ! -f captura-01.kismet.netxml ]; then
    echo -e "${RED}Error: El archivo de captura no se generó correctamente.${NC}"
    exit 1
fi


#========== REDES DETECTADAS ==========

echo -e "\n${WHITE}========== REDES DETECTADAS ==========\n${NC}"
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


#========== CLIENTES DETECTADOS ==========

echo
echo -e "${WHITE}========== CLIENTES DETECTADOS ==========${NC}"
echo
printf "%-17s %-11s %-36s %-11s %-17s %-20s\n" "MAC" "Conectividad" "Fabricante" "Intensidad" "Asociado a" "Red"

xmlstarlet sel --skip-dtd -t -m "//wireless-network/wireless-client" \
  -v "../BSSID" -o "|" \
  -v "client-mac" -o "|" \
  -v "@type" -o "|" \
  -v "snr-info/last_signal_dbm" -n captura-01.kismet.netxml 2>/dev/null |
while IFS='|' read -r bssid mac tipo intensidad; do
    [[ -z "$mac" || "$mac" == "00:00:00:00:00:00" ]] && continue

    fabricante=$(grep -i "$(echo $mac | cut -d':' -f1-3)" oui.txt | awk -F"\t" '{print $2}')
    [ -z "$fabricante" ] && fabricante=$(xmlstarlet sel --skip-dtd -t -m "//wireless-client[client-mac='$mac']" -v "client-manuf" captura-01.kismet.netxml)
    [ -z "$fabricante" ] && fabricante="Unknown"

    essid=$(xmlstarlet sel --skip-dtd -t -m "//wireless-network[BSSID='$bssid']" -v "SSID/essid" captura-01.kismet.netxml)

    COLOR_INT="${NC}"
    [[ "$intensidad" -ge -50 ]] && COLOR_INT="${GREEN}"
    [[ "$intensidad" -lt -50 && "$intensidad" -gt -70 ]] && COLOR_INT="${YELLOW}"
    [[ "$intensidad" -le -70 ]] && COLOR_INT="${RED}"

    printf "%-17s %-11s %-36s ${COLOR_INT}%-11s${NC} %-17s %-20s\n" "$mac" "$tipo" "$fabricante" "$intensidad" "$bssid" "$essid"
done



# --- Restablecer conexión ---

sudo airmon-ng stop "$INTERFAZ_MONITOR"
echo -e "Modo monitor detenido en $INTERFAZ_MONITOR"
sudo service NetworkManager restart
sudo dhclient "$INTERFAZ"
echo -e "${YELLOW}Conexión restablecida${NC}"
