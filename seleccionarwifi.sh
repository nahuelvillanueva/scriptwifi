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
# COMPROBAR IWD
# ----------------------------------------------------------

if ! command -v iwctl >/dev/null 2>&1; then
    echo -e "${RED}Error: no se encontró iwctl.${NC}"
    echo
    echo "Instalá iwd con:"
    echo "sudo apt install iwd"
    exit 1
fi

if ! systemctl is-active --quiet iwd; then
    echo -e "${RED}El servicio iwd no está funcionando.${NC}"
    echo
    echo "Podés iniciarlo con:"
    echo "sudo systemctl start iwd"
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
        echo "Comprobá con:"
        echo
        echo "iwctl device list"
        echo

        exit 1
    fi

    echo
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}       DISPOSITIVOS WIFI${NC}"
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
# ESCANEAR REDES
# ----------------------------------------------------------

scan_networks() {

    echo
    echo -e "${YELLOW}Escaneando redes con $DEVICE...${NC}"

    "$IWCTL" station "$DEVICE" scan >/dev/null 2>&1

    sleep 3

    mapfile -t NETWORKS < <(

        "$IWCTL" station "$DEVICE" get-networks 2>/dev/null |
        sed -n '/^[[:space:]]*Network[[:space:]]/,$p' |
        tail -n +2 |
        sed 's/^[* ]*//' |
        sed 's/[[:space:]]\{2,\}.*$//' |
        sed '/^$/d'

    )

    # Método alternativo si el formato anterior no encuentra redes

    if [ "${#NETWORKS[@]}" -eq 0 ]; then

        mapfile -t NETWORKS < <(

            "$IWCTL" station "$DEVICE" get-networks 2>/dev/null |
            tail -n +5 |
            awk '{$1=$1; print}' |
            sed '/^$/d'

        )

    fi

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
    echo -e "${CYAN}          REDES DISPONIBLES${NC}"
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
# PEDIR CONTRASEÑA
# ----------------------------------------------------------

ask_password() {

    echo

    echo -e "${CYAN}Red seleccionada:${NC} $SSID"

    echo
    echo "Escribí la contraseña."
    echo
    echo "  c = cancelar"
    echo "  d = elegir otra red"
    echo

    while true; do

        read -rp "Contraseña: " PASSWORD

        case "$PASSWORD" in

            c|C)

                echo "Cancelado."
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
# ESCAPAR CARACTERES PARA ARCHIVO IWD
# ----------------------------------------------------------

escape_iwd() {

    printf '%s' "$1" |
        sed 's/\\/\\\\/g; s/"/\\"/g'

}

# ----------------------------------------------------------
# CONECTAR
# ----------------------------------------------------------

connect_wifi() {

    local PROFILE_DIR="/var/lib/iwd"
    local PROFILE="$PROFILE_DIR/$SSID.psk"

    echo
    echo -e "${YELLOW}Conectando a:${NC} $SSID"
    echo -e "${YELLOW}Dispositivo:${NC} $DEVICE"
    echo

    # Necesitamos permisos para escribir en /var/lib/iwd
    if [ ! -w "$PROFILE_DIR" ]; then

        echo -e "${RED}No hay permisos para escribir en $PROFILE_DIR.${NC}"
        echo
        echo "Ejecutá el script con:"
        echo
        echo "sudo $0"
        echo

        return 1
    fi

    # Escapar valores
    local SAFE_SSID
    local SAFE_PASSWORD

    SAFE_SSID=$(escape_iwd "$SSID")
    SAFE_PASSWORD=$(escape_iwd "$PASSWORD")

    # Crear perfil de iwd
    cat > "$PROFILE" <<EOF
[Security]
Passphrase=$SAFE_PASSWORD
EOF

    chmod 600 "$PROFILE"

    echo -e "${YELLOW}Intentando conexión...${NC}"

    # Conectar mediante iwctl
    RESULT=$(
        "$IWCTL" station "$DEVICE" connect "$SSID" 2>&1
    )

    STATUS=$?

    # Esperar un momento para comprobar estado
    sleep 3

    # Comprobar conexión
    STATE=$(
        "$IWCTL" station "$DEVICE" show 2>/dev/null |
        grep -i "State" |
        head -n 1
    )

    if echo "$STATE" | grep -qi "connected"; then

        echo
        echo -e "${GREEN}==========================================${NC}"
        echo -e "${GREEN}          CONECTADO CORRECTAMENTE${NC}"
        echo -e "${GREEN}==========================================${NC}"
        echo
        echo -e "${GREEN}Red:${NC}        $SSID"
        echo -e "${GREEN}Dispositivo:${NC} $DEVICE"
        echo
        echo -e "${GREEN}Perfil guardado en iwd.${NC}"
        echo

        unset PASSWORD

        return 0

    fi

    echo
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}             NO SE CONECTÓ${NC}"
    echo -e "${RED}==========================================${NC}"
    echo

    if [ -n "$RESULT" ]; then
        echo "$RESULT"
        echo
    fi

    unset PASSWORD

    return 1
}

# ==========================================================
# PROGRAMA PRINCIPAL
# ==========================================================

while true; do

    clear

    echo
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}          WIFI / IWD${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo

    # ------------------------------------------------------
    # Elegir adaptador
    # ------------------------------------------------------

    select_device

    while true; do

        clear

        echo
        echo -e "${CYAN}Dispositivo seleccionado: ${GREEN}$DEVICE${NC}"
        echo

        # --------------------------------------------------
        # Escanear
        # --------------------------------------------------

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

        # --------------------------------------------------
        # Elegir red
        # --------------------------------------------------

        if select_network; then

            while true; do

                # ------------------------------------------
                # Pedir contraseña
                # ------------------------------------------

                if ask_password; then

                    # --------------------------------------
                    # Intentar conexión
                    # --------------------------------------

                    if connect_wifi; then

                        exit 0

                    fi

                    # --------------------------------------
                    # Falló
                    # --------------------------------------

                    echo
                    echo -e "${RED}La conexión falló.${NC}"
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
                            # Volver a pedir contraseña
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
