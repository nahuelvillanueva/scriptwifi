#!/bin/bash

# Función para limpiar variables al volver a empezar
reiniciar_variables() {
    unset interfaces iface_idx IFACE raw_networks red_ssids red_idx TARGET_SSID
}

while true; do
    reiniciar_variables
    clear
    
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
        echo "Selección inválida. Presioná Enter para reiniciar..."
        read
        continue
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
        read -p "Presioná Enter para volver a escanear o 's' para salir: " op_vacia
        if [ "$op_vacia" = "s" ] || [ "$op_vacia" = "S" ]; then exit 0; else continue; fi
    fi

    # Mostrar la lista de redes numeradas para el usuario
    echo "Redes encontradas:"
    echo "--------------------------------------------------------"
    for idx in "${!red_ssids[@]}"; do
        echo "[$((idx+1))] ${red_ssids[$idx]}"
    done
    echo "--------------------------------------------------------"

    # Elegir el número de la red
    read -p "Seleccioná el número de la red (1, 2, 3...): " red_idx
    if [[ ! "$red_idx" =~ ^[0-9]+$ ]] || [ "$red_idx" -le 0 ] || [ "$red_idx" -gt ${#red_ssids[@]} ]; then
        echo "Selección de red inválida. Presioná Enter para volver al inicio..."
        read
        continue
    fi

    TARGET_SSID=${red_ssids[$((red_idx-1))]}

    # 3. Bucle de conexión interactiva
    echo -e "\n=== 3. Conexión ==="
    
    # Comprobar si la red ya está guardada en iwd de antemano
    if [ -f "/var/lib/iwd/$TARGET_SSID.psk" ] || [ -f "/var/lib/iwd/$TARGET_SSID.8021x" ]; then
        echo "Red conocida detectada. Conectando automáticamente a '$TARGET_SSID'..."
        iwctl station "$IFACE" connect "$TARGET_SSID" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "¡Conexión establecida con éxito!"
            exit 0
        fi
    fi

    # Bucle exclusivo para la contraseña o cambio de opción
    while true; do
        read -s -p "Ingresá la contraseña para '$TARGET_SSID': " user_pass
        echo "" # Salto de línea obligado por ocultar la entrada

        # SOLUCIÓN AL "ARGUMENT FORMAT IS INVALID":
        # Usamos envíos crudos usando 'xargs' para asegurar que las comillas y los espacios de la variable
        # se traduzcan de manera exacta como strings hacia el binario de iwd, redirigiendo salidas toscas a la nada.
        echo "station $IFACE connect \"$TARGET_SSID\"" | xargs iwctl --passphrase "$user_pass" >/dev/null 2>&1
        
        # Evaluar el código de salida real del intento
        if [ $? -eq 0 ]; then
            echo -e "\n¡Conexión establecida con éxito con '$TARGET_SSID'!"
            exit 0
        else
            echo -e "\n[!] Error: Contraseña incorrecta."
            echo "--------------------------------------------------------"
            echo "Opciones:"
            echo "  [Enter] Volver a intentar la contraseña"
            echo "  [d]     Volver a seleccionar una placa o red"
            echo "  [s]     Salir del script"
            echo "--------------------------------------------------------"
            read -p "Elegí una opción: " opcion
            
            if [ "$opcion" = "s" ] || [ "$opcion" = "S" ]; then
                echo "Conexión cancelada por el usuario."
                exit 0
            elif [ "$opcion" = "d" ] || [ "$opcion" = "D" ]; then
                # Rompe el bucle de contraseña y vuelve al menú principal
                break 2
            fi
            echo "Reintentando contraseña..."
        fi
    done
done
