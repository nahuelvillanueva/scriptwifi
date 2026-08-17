#!/bin/bash

# 1. Detectar placas Wi-Fi a través de iwd
echo "=== 1. Placas Wi-Fi detectadas (iwd) ==="
# Extrae solo los nombres de los dispositivos de la lista de iwd
interfaces=($(iwctl device list | awk 'NR>4 {print $2}' | grep -v '^$'))

if [ ${#interfaces[@]} -eq 0 ]; then
    echo "No se encontraron placas Wi-Fi activas en iwd."
    exit 1
fi

# Mostrar las placas numeradas
for i in "${!interfaces[@]}"; do
    echo "[$((i+1))] ${interfaces[$i]}"
done

# Elegir la placa
read -p "Seleccioná el número de interfaz que querés usar: " iface_idx
if [[ ! "$iface_idx" =~ ^[0-9]+$ ]] || [ "$iface_idx" -le 0 ] || [ "$iface_idx" -gt ${#interfaces[@]} ]; then
    echo "Selección inválida."
    exit 1
fi
IFACE=${interfaces[$((iface_idx-1))]}

# 2. Escanear y listar redes disponibles en esa placa
echo -e "\n=== 2. Buscando redes con $IFACE... ==="
iwctl station "$IFACE" scan
sleep 2

# Obtener la lista limpia de SSIDs (nombres de red)
# El comando de iwd devuelve códigos de color ANSI, con 'sed' los limpiamos para que el script no falle
raw_networks=$(iwctl station "$IFACE" get-networks | sed 's/\x1B\[[0-9;]*[JKmsu]//g')

# Guardar los nombres de las redes en un arreglo (saltando las cabeceras de iwctl)
IFS=$'\n' red_ssids=($(echo "$raw_networks" | awk 'NR>4 {print substr($0, 5, 32)}' | sed 's/[[:space:]]*$//' | grep -v '^$'))

if [ ${#red_ssids[@]} -eq 0 ]; then
    echo "No se encontraron redes Wi-Fi al alcance de esta placa."
    exit 1
fi

# Mostrar la lista de redes numeradas para el usuario
echo "Redes encontradas:"
echo "--------------------------------------------------------"
echo "$raw_networks" | awk 'NR>4 {print "["NR-4"] " $0}'
echo "--------------------------------------------------------"

# Elegir el número de la red
read -p "Seleccioná el número de la red (1, 2, 3...): " red_idx
if [[ ! "$red_idx" =~ ^[0-9]+$ ]] || [ "$red_idx" -le 0 ] || [ "$red_idx" -gt ${#red_ssids[@]} ]; then
    echo "Selección de red inválida."
    exit 1
fi

TARGET_SSID=${red_ssids[$((red_idx-1))]}

# 3. Conexión interactiva
echo -e "\n=== 3. Conexión ==="
echo "Conectando a '$TARGET_SSID' a través de $IFACE..."

# iwctl es inteligente: si la red ya está guardada, se conecta directo.
# Si no está guardada y requiere clave, el propio iwctl te va a pedir el Password en la terminal de forma segura.
iwctl station "$IFACE" connect "$TARGET_SSID"
