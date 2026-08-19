#!/bin/bash

# ==========================================================
# Wi-Fi interactivo para iwd / iwctl
# ==========================================================

set -u

IWCTL="iwctl"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ----------------------------------------------------------
# Obtener interfaces Wi-Fi
# ----------------------------------------------------------

get_interfaces() {
    "$IWCTL" device list 2>/dev/null |
        awk '/^[[:space:]]*[a-zA-Z0-9._-]+[[:space:]]+.*wifi/ {
            print $1
        }'
}

# ----------------------------------------------------------
# Seleccionar dispositivo
# ----------------------------------------------------------

select_device() {

    mapfile -t DEVICES < <(get_interfaces)

    if [ "${#DEVICES[@]}" -eq 0 ]; then
        echo -e "${RED}No se encontraron dispositivos Wi-Fi.${NC}"
        exit 1
    fi

    echo
    echo -e "${CYAN}Dispositivos Wi-Fi disponibles:${NC}"
    echo

    local i=1

    for dev in "${DEVICES[@]}"; do
        echo "  $i) $dev"
        ((i++))
    done

    echo
    echo "  c) Cancelar"
    echo

    while true; do

        read -rp "Seleccioná el dispositivo: " choice

        case "$choice" in
            c|C)
                echo "Cancelado."
                exit 0
                ;;
            ''|*[!0-9]*)
                echo -e "${RED}Opción inválida.${NC}"
                ;;
            *)
                if [ "$choice" -ge 1 ] &&
                   [ "$choice" -le "${#DEVICES[@]}" ]; then

                    DEVICE="${DEVICES[$((choice-1))]}"
                    return 0
                fi

                echo -e "${RED}Opción inválida.${NC}"
                ;;
        esac
    done
}

# ----------------------------------------------------------
# Escanear redes
# ----------------------------------------------------------

scan_networks() {

    echo
    echo -e "${YELLOW}Escaneando redes con $DEVICE...${NC}"

    "$IWCTL" station "$DEVICE" scan >/dev/null 2>&1

    sleep 2

    mapfile -t NETWORKS < <(
        "$IWCTL" station "$DEVICE" get-networks 2>/dev/null |
        tail -n +5 |
        sed 's/^[* ]*//' |
        awk '{$1=$1; print}'
    )

    if [ "${#NETWORKS[@]}" -eq 0 ]; then
        echo -e "${RED}No se encontraron redes.${NC}"
        return 1
    fi

    return 0
}

# ----------------------------------------------------------
# Seleccionar red
# ----------------------------------------------------------

select_network() {

    echo
    echo -e "${CYAN}Redes Wi-Fi encontradas:${NC}"
    echo

    local i=1

    for network in "${NETWORKS[@]}"; do
        echo "  $i) $network"
        ((i++))
    done

    echo
    echo "  d) Volver a escanear / seleccionar otra red"
    echo "  c) Cancelar"
    echo

    while true; do

        read -rp "Seleccioná la red: " choice

        case "$choice" in

            c|C)
                echo "Cancelado."
                exit 0
                ;;

            d|D)
                return 1
                ;;

            ''|*[!0-9]*)
                echo -e "${RED}Opción inválida.${NC}"
                ;;

            *)
                if [ "$choice" -ge 1 ] &&
                   [ "$choice" -le "${#NETWORKS[@]}" ]; then

                    SSID="${NETWORKS[$((choice-1))]}"
                    return 0
                fi

                echo -e "${RED}Opción inválida.${NC}"
                ;;
        esac
    done
}

# ----------------------------------------------------------
# Pedir contraseña
# ----------------------------------------------------------

ask_password() {

    while true; do

        echo
        read -rsp "Contraseña para '$SSID' (c=cancelar, d=otra red): " PASSWORD
        echo

        case "$PASSWORD" in

            c|C)
                echo "Cancelado."
                exit 0
                ;;

            d|D)
                return 1
                ;;

            *)
                if [ -n "$PASSWORD" ]; then
                    return 0
                fi

                echo -e "${RED}La contraseña no puede estar vacía.${NC}"
                ;;
        esac

    done
}

# ----------------------------------------------------------
# Conectar
# ----------------------------------------------------------

connect_wifi() {

    echo
    echo -e "${YELLOW}Conectando a '$SSID'...${NC}"

    RESULT=$(
        "$IWCTL" station "$DEVICE" connect "$SSID" <<EOF
$PASSWORD
EOF
        2>&1
    )

    STATUS=$?

    if [ "$STATUS" -eq 0 ]; then
        echo
        echo -e "${GREEN}✓ Conectado correctamente a '$SSID'.${NC}"
        echo -e "${GREEN}Dispositivo: $DEVICE${NC}"
        echo
        unset PASSWORD
        return 0
    fi

    echo
    echo -e "${RED}✗ No se pudo conectar a '$SSID'.${NC}"
    echo "$RESULT"
    echo

    unset PASSWORD
    return 1
}


# ==========================================================
# PROGRAMA PRINCIPAL
# ==========================================================

while true; do

    clear

    echo "=========================================="
    echo "        Wi-Fi / iwd / iwctl"
    echo "=========================================="

    select_device

    while true; do

        clear

        echo "=========================================="
        echo " Dispositivo: $DEVICE"
        echo "=========================================="

        if ! scan_networks; then
            read -rp "Enter para volver a intentar, c para cancelar: " x

            case "$x" in
                c|C) exit 0 ;;
            esac

            continue
        fi

        if select_network; then

            while true; do

                if ask_password; then

                    if connect_wifi; then
                        exit 0
                    fi

                    echo
                    echo "Contraseña incorrecta o no se pudo establecer la conexión."
                    echo
                    echo "  Enter = volver a intentar contraseña"
                    echo "  d     = seleccionar otra red"
                    echo "  c     = cancelar"
                    echo

                    read -rp "Opción: " retry

                    case "$retry" in
                        c|C)
                            exit 0
                            ;;

                        d|D)
                            break
                            ;;

                        *)
                            # Volver a pedir contraseña
                            ;;
                    esac
                else
                    # d desde la contraseña
                    break
                fi

            done

        fi

    done

done
