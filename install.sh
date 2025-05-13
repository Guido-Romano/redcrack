#!/bin/bash

# Comprobamos si el script se ejecuta como root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root (utiliza sudo)"
    exit 1
fi

# Instalamos las dependencias necesarias
echo "[RedCrack Installer] Instalando dependencias..."
apt-get update
apt-get install -y xmlstarlet wget aircrack-ng iw wireless-tools mate-terminal

# Instalamos el paquete .deb desde el directorio actual
DEB_PATH="$(dirname "$0")/redcrack.deb"

if [ -f "$DEB_PATH" ]; then
    echo "[RedCrack Installer] Instalando el paquete .deb..."
    dpkg -i "$DEB_PATH"
else
    echo "[Error] No se encontró el paquete redcrack.deb en $DEB_PATH"
    exit 1
fi

# Añadimos el archivo .desktop al menú de aplicaciones
DESKTOP_SRC="$(dirname "$0")/usr/share/applications/redcrack.desktop"
DESKTOP_DEST="/usr/share/applications/redcrack.desktop"

if [ -f "$DESKTOP_SRC" ]; then
    echo "[RedCrack Installer] Añadiendo acceso directo al menú..."
    cp "$DESKTOP_SRC" "$DESKTOP_DEST"
    chmod +x "$DESKTOP_DEST"
else
    echo "[Advertencia] No se encontró el archivo .desktop en $DESKTOP_SRC"
fi

echo "[RedCrack Installer] ¡RedCrack ha sido instalado correctamente!"
