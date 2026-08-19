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

RED='\033;31m'
GREEN='\033;32m'
YELLOW='\033[1;33m'
CYAN='\033;36m'
BLUE='\033;34m'
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
                if [ "$choice" -ge 1 ] && [ "$choice" -le "${#DEVICES[@]}" ]; then
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

    if [[ -n "$trimmed" ]] && [[ "$trimmed" =~ ^(.)\1*$ ]]; then
        local count=${#trimmed}
        case "$count" in
            4) echo "Excelente ($raw)" ;;
            3) echo "Buena ($raw)" ;;
            2) echo "Regular ($raw)" ;;
            1) echo "Débil ($raw)" ;;
            *) echo "$raw" ;;
        esac
        return
    fi

    if [[ "$raw" =~ ^-?[0-9]+[[:space:]]*dBm$ ]]; then
        local dbm
        dbm=$(echo "$raw" | grep -oE -- '-?[0-9]+')
        if   [ "$dbm" -ge -50 ]; then echo "Excelente ($raw)"
        elif [ "$dbm" -ge -60 ]; then echo "Buena ($raw)"
        elif [ "$dbm" -ge -70 ]; then echo "Regular ($raw)"
        else echo "Débil ($raw)"
        fi
        return
    fi

    echo "$raw"
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

    # Definimos el separador en una variable limpia para evitar fallos con set -u
    local sep=$'\x1f'

    mapfile -t NETWORKS < <(
        "$IWCTL" station "$DEVICE" get-networks 2>/dev/null |
        tr -d '\r' |
        awk '
        {
            line = $0
            sub(/^[* >]+/, "", line)
            if (match(line, /[[:space:]](psk|open|wep|8021x|owe|sae|wpa)([[:space:]]|$)/)) {
                sectok = substr(line, RSTART, RLENGTH)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", sectok)
                name = substr(line, 1, RSTART - 1)
                gsub(/[[:space:]]+$/, "", name)
                rest = substr(line, RSTART + RLENGTH)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
                if (name != "") {
                    printf "%s\x1f%s\x1f%s\n", name, sectok, rest
                }
            }
        }
        ' |
        sort -u -t "$sep" -k1,1
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
    local name
    local sec
    local signal

    for network in "${NETWORKS[@]}"; do
        IFS=$'\x1f' read -r name sec signal <<< "$network"
        printf "  %2d) %-28s %-16s Señal: %b\n" \
            "$i" \
            "$name" \
            "[$(security_label "$sec")]" \
            "$(signal_label "$signal")" # Agregada la función de traducción de señal que faltaba aplicar
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
                if [ "$choice" -ge 1 ] && [ "$choice" -le "${#NETWORKS[@]}" ]; then
                    IFS=$'\x1f' read -r SSID sec signal <<< "${NETWORKS[$((choice-1))]}"
                    return 0
                fi
                echo -e "${RED}Opción inválida.${NC}"
                ;;
        </ac
    done
}

# ----------------------------------------------------------
# PEDIR CONTRASEÑA Y CONECTAR
# ----------------------------------------------------------

ask_password() {
    echo
    echo -e "${CYAN}Red:${NC} $SSID"
    echo

    if [ "$sec" = "open" ]; then
        echo "Conectando a red abierta..."
        if "$IWCTL" station "$DEVICE" connect "$SSID"; then
            echo -e "${GREEN}¡Conectado exitosamente!${NC}"
            exit 0
        else
            echo -e "${RED}Error al conectar.${NC}"
            return 1
        fi
    fi

    echo "Escribí la contraseña."
    echo
    echo "  d = elegir otra red"
    echo "  c = cancelar"
    echo

    while true; do
        read -s -rp "Contraseña: " PASSWORD # -s oculta los caracteres al escribir por seguridad
        echo

        case "$PASSWORD" in
            c|C)
                exit 0
                ;;
            d|D)
                return 1
                ;;
            "")
                echo -e "${RED}La contraseña no puede estar vacía.${NC}"
                ;;
            *)
                echo -e "${YELLOW}Conectando a $SSID...${NC}"
                if "$IWCTL" station "$DEVICE" connect "$SSID" --passphrase "$PASSWORD"; then
                    echo -e "${GREEN}¡Conectado exitosamente!${NC}"
                    exit 0
                else
                    echo -e "${RED}Fallo en la conexión. Verificá la contraseña.${NC}"
                fi
                ;;
        esac
    done
}

# ----------------------------------------------------------
# FLUJO PRINCIPAL DEL SCRIPT
# ----------------------------------------------------------

select_device

while true; do
    if scan_networks; then
        if select_network; then
            if ask_password; then
                exit 0
            fi
        fi
    fi
done
