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
# TRADUCIR SEGURIDAD Y SEÑAL A ALGO LEGIBLE
# ----------------------------------------------------------

security_label() {

    case "$1" in
        psk)    echo "WPA/WPA2" ;;
        sae)    echo "WPA3" ;;
        wep)    echo "WEP" ;;
        open)   echo "Abierta" ;;
        8021x)  echo "WPA-Enterprise" ;;
        owe)    echo "OWE (cifrado sin clave)" ;;
        wpa)    echo "WPA" ;;
        *)      echo "$1" ;;
    esac
}

signal_label() {

    local raw="$1"
    local trimmed

    trimmed=$(echo -n "$raw" | tr -d '[:space:]')

    # ------------------------------------------------------
    # SEÑAL EN ASTERISCOS
    # ------------------------------------------------------

    if [[ "$trimmed" =~ ^\*+$ ]]; then

        local count=${#trimmed}

        # Limitar a 5
        [ "$count" -gt 5 ] && count=5

        local filled=""
        local empty=""
        local i

        # Asteriscos llenos
        for ((i=0; i<count; i++)); do
            filled+="*"
        done

        # Asteriscos vacíos
        for ((i=count; i<5; i++)); do
            empty+="*"
        done

        local quality

        case "$count" in
            5) quality="Excelente" ;;
            4) quality="Buena" ;;
            3) quality="Regular" ;;
            2) quality="Débil" ;;
            1) quality="Muy débil" ;;
            *) quality="Sin señal" ;;
        esac

        # Blanco = señal recibida
        # Gris = señal faltante
        printf "\033[37m%s\033[90m%s\033[0m %s" \
            "$filled" \
            "$empty" \
            "$quality"

        return 0
    fi

    # ------------------------------------------------------
    # SEÑAL EN dBm
    # ------------------------------------------------------

    if [[ "$raw" =~ -?[0-9]+[[:space:]]*dBm ]]; then

        local dbm
        dbm=$(echo "$raw" | grep -oE -- '-?[0-9]+')

        local count

        if [ "$dbm" -ge -50 ]; then
            count=5
        elif [ "$dbm" -ge -60 ]; then
            count=4
        elif [ "$dbm" -ge -70 ]; then
            count=3
        elif [ "$dbm" -ge -80 ]; then
            count=2
        else
            count=1
        fi

        local filled=""
        local empty=""
        local i

        for ((i=0; i<count; i++)); do
            filled+="*"
        done

        for ((i=count; i<5; i++)); do
            empty+="*"
        done

        local quality

        case "$count" in
            5) quality="Excelente" ;;
            4) quality="Buena" ;;
            3) quality="Regular" ;;
            2) quality="Débil" ;;
            1) quality="Muy débil" ;;
        esac

        printf "\033[37m%s\033[90m%s\033[0m %s" \
            "$filled" \
            "$empty" \
            "$quality"

        return 0
    fi

    echo "$raw"
}


# ----------------------------------------------------------
# ESCANEAR REDES
# ----------------------------------------------------------

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

    # IMPORTANTE:
    # Conservamos los códigos ANSI que iwctl utiliza para
    # representar la intensidad de la señal.

    mapfile -t NETWORKS < <(

        "$IWCTL" station "$DEVICE" get-networks 2>/dev/null |
        awk '
        /^[[:space:]]*Network[[:space:]]+Name/ {
            next
        }

        /^[[:space:]]*-+[[:space:]]*$/ {
            next
        }

        NF >= 3 {
            print
        }
        '

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
    echo -e "${CYAN}              REDES WIFI${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo

    local i=1

    for network in "${NETWORKS[@]}"; do

        printf "  %2d) %b\n" "$i" "$network"

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

                    # Guardamos la línea completa seleccionada.
                    SELECTED_NETWORK="${NETWORKS[$((choice-1))]}"

                    # El SSID es la parte anterior a la columna
                    # de seguridad.
                    SSID=$(echo "$SELECTED_NETWORK" |
                        sed -E 's/[[:space:]]+(psk|open|wep|8021x|owe|sae|wpa)[[:space:]].*$//')

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
