#!/bin/bash

# ==========================================================
# WIFI INTERACTIVO PARA IWD
# Debian 13
# ==========================================================

set -u

IWCTL="/usr/bin/iwctl"

# ----------------------------------------------------------
# COLORES
# ----------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ----------------------------------------------------------
# COMPROBAR IWD / IWCTL
# ----------------------------------------------------------

if ! command -v iwctl >/dev/null 2>&1; then

    echo -e "${RED}No se encontró iwctl.${NC}"
    echo
    echo "El paquete iwd no está instalado."
    echo
    echo "Para instalarlo:"
    echo
    echo "sudo apt install iwd"
    echo

    exit 1
fi

if ! systemctl is-active --quiet iwd; then

    echo -e "${RED}El servicio iwd no está funcionando.${NC}"
    echo
    echo "Podés iniciarlo con:"
    echo
    echo "sudo systemctl start iwd"
    echo

    exit 1
fi

# ----------------------------------------------------------
# OBTENER INTERFACES WIFI
# ----------------------------------------------------------

get_interfaces() {

    for dev in /sys/class/net/*; do

        dev="${dev##*/}"

        if [ -d "/sys/class/net/$dev/wireless" ]; then
            echo "$dev"
        fi

    done
}

# ----------------------------------------------------------
# SELECCIONAR DISPOSITIVO
# ----------------------------------------------------------

select_device() {

    mapfile -t DEVICES < <(get_interfaces)

    if [ "${#DEVICES[@]}" -eq 0 ]; then

        echo
        echo -e "${RED}No se encontraron dispositivos Wi-Fi.${NC}"
        echo

        exit 1
    fi

    echo
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}          DISPOSITIVOS WIFI${NC}"
    echo -e "${CYAN}==========================================${NC}"
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
# ESCANEAR REDES
# ----------------------------------------------------------

scan_networks() {

    echo
    echo -e "${YELLOW}Escaneando redes con $DEVICE...${NC}"

    if ! "$IWCTL" station "$DEVICE" scan >/dev/null 2>&1; then

        echo -e "${RED}No se pudo iniciar el escaneo.${NC}"

        return 1
    fi

    sleep 2

    mapfile -t NETWORKS < <(

        "$IWCTL" station "$DEVICE" get-networks 2>/dev/null |
        # 1) Quitar códigos de color ANSI (esto es lo que causaba
        #    el texto gris "pegado" al resto de la línea).
        sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' |
        # 2) Quitar caracteres no imprimibles raros (líneas de
        #    bordes con caracteres unicode de tabla, etc.)
        tr -d '\r' |
        # 3) Quedarnos SOLO con líneas que tengan una columna de
        #    seguridad real (psk/open/wep/8021x/owe/sae/wpa).
        #    Así ignoramos automáticamente título, separadores
        #    de guiones y la fila de encabezado "Network name...",
        #    sin depender de contar líneas fijas.
        awk '
        {
            line = $0

            # Quita el ">" de la red conectada y espacios/asteriscos iniciales
            sub(/^[>*[:space:]]+/, "", line)

            if (line ~ /[[:space:]](psk|open|wep|8021x|owe|sae|wpa)([[:space:]]|$)/) {

                sub(/[[:space:]]+(psk|open|wep|8021x|owe|sae|wpa).*$/, "", line)
                gsub(/[[:space:]]+$/, "", line)

                if (line != "") print line
            }
        }
        ' |
        sort -u

    )

    if [ "${#NETWORKS[@]}" -eq 0 ]; then

        echo
        echo -e "${RED}No se encontraron redes.${NC}"
        echo

        return 1
    fi

    return 0
}

# ----------------------------------------------------------
# SELECCIONAR RED
# ----------------------------------------------------------

select_network() {

    echo
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}            REDES WIFI${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo

    local i=1

    for network in "${NETWORKS[@]}"; do

        echo "  $i) $network"

        ((i++))

    done

    echo
    echo "  d) Volver a escanear"
    echo "  c) Cancelar"
    echo

    while true; do

        read -rp "Seleccioná la red: " choice

        case "$choice" in

            c|C)
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
# PEDIR CONTRASEÑA
# ----------------------------------------------------------

ask_password() {

    echo
    echo -e "${CYAN}Red:${NC} $SSID"
    echo

    echo "Escribí la contraseña."
    echo
    echo "  d = elegir otra red"
    echo "  c = cancelar"
    echo

    while true; do

        read -rp "Contraseña: " PASSWORD

        case "$PASSWORD" in

            c|C)
                exit 0
                ;;

            d|D)
                return 1
                ;;

            "")
                echo
                echo -e "${RED}La contraseña está vacía.${NC}"
                echo
                ;;

            *)
                return 0
                ;;

        esac

    done
}

# ----------------------------------------------------------
# CONECTAR
# ----------------------------------------------------------

connect_wifi() {

    echo
    echo -e "${YELLOW}Conectando...${NC}"
    echo
    echo "Dispositivo : $DEVICE"
    echo "Red         : $SSID"
    echo

    # IMPORTANTE:
    # No usamos sudo.
    # No escribimos en /var/lib/iwd.
    # La contraseña se entrega directamente a iwctl.

    RESULT=$(
        "$IWCTL" \
            --passphrase "$PASSWORD" \
            station "$DEVICE" connect "$SSID" 2>&1
    )

    STATUS=$?

    unset PASSWORD

    if [ "$STATUS" -eq 0 ]; then

        echo
        echo -e "${GREEN}==========================================${NC}"
        echo -e "${GREEN}       CONECTADO CORRECTAMENTE${NC}"
        echo -e "${GREEN}==========================================${NC}"
        echo
        echo "Dispositivo : $DEVICE"
        echo "Red         : $SSID"
        echo

        return 0
    fi

    echo
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}          NO SE PUDO CONECTAR${NC}"
    echo -e "${RED}==========================================${NC}"
    echo

    if [ -n "$RESULT" ]; then
        echo "$RESULT"
    fi

    echo

    return 1
}

# ==========================================================
# PROGRAMA PRINCIPAL
# ==========================================================

while true; do

    clear

    echo
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}             WIFI / IWD${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo

    # Elegir dispositivo

    select_device

    while true; do

        clear

        echo
        echo -e "${CYAN}Dispositivo:${NC} ${GREEN}$DEVICE${NC}"
        echo

        # Escanear

        if ! scan_networks; then

            echo
            read -rp "Enter = volver a escanear / c = cancelar: " option

            case "$option" in

                c|C)
                    exit 0
                    ;;

            esac

            continue
        fi

        # Seleccionar red

        if select_network; then

            while true; do

                # Contraseña

                if ask_password; then

                    # Conectar

                    if connect_wifi; then
                        exit 0
                    fi

                    # Falló la conexión

                    echo
                    echo "¿Qué querés hacer?"
                    echo
                    echo "  Enter = volver a introducir contraseña"
                    echo "  d     = elegir otra red"
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
                            # Reintentar contraseña
                            ;;

                    esac

                else

                    # d desde contraseña

                    break

                fi

            done

        fi

    done

done
