#!/bin/bash

# 1. Detectar placas Wi-Fi a través de iwd
echo "=== 1. Placas Wi-Fi detectadas (iwd) ==="
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
echo "Escaneando el entorno, por favor esperá..."
sleep 4

# Obtener la lista limpia de códigos ANSI de color
raw_networks=$(iwctl station "$IFACE" get-networks | sed 's/\x1B\[[0-9;]*[JKmsu]//g')

# Guardar los nombres de las redes en un arreglo limpios de espacios al inicio/final
IFS=$'\n' red_ssids=($(echo "$raw_networks" | awk 'NR>4 {print substr($0, 5, 32)}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'))

if [ ${#red_ssids[@]} -eq 0 ]; then
    echo "No se encontraron redes Wi-Fi al alcance de esta placa."
    exit 1
fi

# Mostrar la lista de redes numeradas para el usuario (reutilizando el arreglo limpio para evitar confusiones visuales)
echo "Redes encontradas:"
echo "--------------------------------------------------------"
for idx in "${!red_ssids[@]}"; do
    echo "[$((idx+1))] ${red_ssids[$idx]}"
done
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

# Comprobar si la red ya está guardada en iwd (los perfiles se guardan en /var/lib/iwd/)
# Si ya existe el perfil, no hace falta pedir clave.
if [ -f "/var/lib/iwd/$TARGET_SSID.psk" ] || [ -f "/var/lib/iwd/$TARGET_SSID.8021x" ]; then
    echo "Red conocida detectada. Conectando automáticamente..."
    iwctl station "$IFACE" connect "$TARGET_SSID"
else
    # Si es una red nueva, te pedimos la clave nosotros de forma segura
    read -s -p "Ingresá la contraseña para '$TARGET_SSID': " user_pass
    echo "" # Nueva línea para prolijidad
    
    # Se la pasamos de forma directa usando el parámetro oficial de la terminal
    iwctl --passphrase "$user_pass" station "$IFACE" connect "$TARGET_SSID"
fi
