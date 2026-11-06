
#!/system/bin/sh

export LANG=C
export LC_ALL=C

RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
GRAY='\033[0;37m'

RAINBOW=0
PREV_TOTAL=0
PREV_IDLE=0

getprop_value() {
    value=$(getprop "$1" 2>/dev/null)
    printf '%s' "${value:-Unknown}"
}

rainbow() {
    case $((RAINBOW % 6)) in
        0) color=31 ;;
        1) color=33 ;;
        2) color=32 ;;
        3) color=36 ;;
        4) color=34 ;;
        5) color=35 ;;
    esac
    printf '\033[1;%sm%s\033[0m' "$color" "$1"
    RAINBOW=$((RAINBOW + 1))
}

show() {
    printf "${CYAN}%-20s${RESET} : ${WHITE}%s${RESET}\n" "$1" "$2"
}

section() {
    printf "\n${YELLOW}========== %s ==========${RESET}\n" "$1"
}

read_cpu() {
    awk '/^cpu / {
        idle=$5+$6
        total=0
        for (i=2;i<=NF;i++) total+=$i
        printf "%.0f %.0f", total, idle
    }' /proc/stat
}

cpu_usage() {
    current=$(read_cpu)
    set -- $current

    total=${1:-0}
    idle=${2:-0}

    if [ "$PREV_TOTAL" -gt 0 ] && [ "$total" -gt "$PREV_TOTAL" ]; then
        dt=$((total - PREV_TOTAL))
        di=$((idle - PREV_IDLE))
        usage=$((100 * (dt - di) / dt))
        [ "$usage" -lt 0 ] && usage=0
        [ "$usage" -gt 100 ] && usage=100
    else
        usage=0
    fi

    PREV_TOTAL=$total
    PREV_IDLE=$idle

    printf '%s%%' "$usage"
}

get_ram() {
    awk '
    /^MemTotal:/ {t=$2}
    /^MemAvailable:/ {a=$2}
    END {
        if (t>0) printf "%.0f %.0f %.0f",t/1024,(t-a)/1024,a/1024
    }' /proc/meminfo
}

get_storage() {
    df -k /data 2>/dev/null | awk '
    NR==2 {
        printf "%.0f %.0f %.0f",
        $2/1048576,$3/1048576,$4/1048576
    }'
}

get_network() {
    awk '
    NR>2 {
        rx+=$2
        tx+=$10
    }
    END {
        printf "%.0f %.0f",rx,tx
    }' /proc/net/dev 2>/dev/null
}

format_bytes() {
    awk -v n="$1" 'BEGIN {
        if(n>=1073741824) printf "%.2f GB",n/1073741824
        else if(n>=1048576) printf "%.2f MB",n/1048576
        else if(n>=1024) printf "%.2f KB",n/1024
        else printf "%.0f B",n
    }'
}

get_ascii() {
    sdk=$(getprop_value ro.build.version.sdk)

    case "$sdk" in
        3[0-9]|[4-9][0-9])
            cat <<'ART'
          .-=========-.
          \'-=======-'/
          _| ANDROID |_
         ((|         |))
          \|         |/
           \_________/
ART
            ;;
        *)
            cat <<'ART'
             /\_/\\
            ( o.o )
             > ^ <
ART
            ;;
    esac
}

draw() {
    printf '\033[H\033[J'

    RAINBOW=$(( $(date +%S 2>/dev/null) % 6 ))

    rainbow "  _____ _____ _____ _____ _____"
    printf '\n'
    rainbow " |_   _| __  | __  |     |   __|"
    printf '\n'
    rainbow "   | | |    -|    -| | | |   __|"
    printf '\n'
    rainbow "   |_| |__|__|__|__|_|___|_____|"
    printf '\n\n'

    rainbow "       ANDROID LIVE MONITOR"
    printf '\n\n'

    get_ascii

    section "DEVICE INFORMATION"
    show "Manufacturer" "$(getprop_value ro.product.manufacturer)"
    show "Brand" "$(getprop_value ro.product.brand)"
    show "Model" "$(getprop_value ro.product.model)"
    show "Device" "$(getprop_value ro.product.device)"
    show "Product" "$(getprop_value ro.product.name)"
    show "Hardware" "$(getprop_value ro.hardware)"

    section "OPERATING SYSTEM"
    show "OS" "Android"
    show "Android Version" "$(getprop_value ro.build.version.release)"
    show "SDK" "$(getprop_value ro.build.version.sdk)"
    show "Build ID" "$(getprop_value ro.build.id)"
    show "Build Display" "$(getprop_value ro.build.display.id)"
    show "Security Patch" "$(getprop_value ro.build.version.security_patch)"
    show "Kernel" "$(uname -r 2>/dev/null)"
    show "Architecture" "$(uname -m 2>/dev/null)"
    show "CPU ABI" "$(getprop_value ro.product.cpu.abi)"
    show "ABI List" "$(getprop_value ro.product.cpu.abilist)"

    section "PROCESSOR"
    show "CPU Model" "$(getprop_value ro.soc.model)"
    show "CPU Hardware" "$(awk -F ': ' '/Hardware/ {print $2; exit}' /proc/cpuinfo)"
    show "CPU Cores" "$(grep -c '^processor' /proc/cpuinfo)"
    show "CPU Usage" "$cpu"

    section "MEMORY"
    ram=$(get_ram)
    set -- $ram

    if [ "$#" -ge 3 ]; then
        total=$1
        used=$2
        free=$3
        percent=$((used * 100 / total))
        show "Total RAM" "$total MB"
        show "Used RAM" "$used MB"
        show "Free RAM" "$free MB"
        show "RAM Usage" "$percent%"
    else
        show "RAM" "Unavailable"
    fi

    section "STORAGE"
    storage=$(get_storage)
    set -- $storage

    if [ "$#" -ge 3 ]; then
        show "Total Storage" "$1 GB"
        show "Used Storage" "$2 GB"
        show "Free Storage" "$3 GB"
        if [ "${1%.*}" -gt 0 ] 2>/dev/null; then
            percent=$(awk -v u="$2" -v t="$1" 'BEGIN {if(t>0) printf "%.0f",u*100/t; else print 0}')
            show "Storage Usage" "$percent%"
        fi
    else
        show "Storage" "Unavailable"
    fi

    section "BATTERY"
    battery=$(dumpsys battery 2>/dev/null)

    level=$(printf '%s\n' "$battery" | awk '/level:/ {print $2; exit}')
    status=$(printf '%s\n' "$battery" | awk '/status:/ {print $2; exit}')
    temp=$(printf '%s\n' "$battery" | awk '/temperature:/ {print $2; exit}')
    voltage=$(printf '%s\n' "$battery" | awk '/voltage:/ {print $2; exit}')

    case "$status" in
        1) status_text="Unknown" ;;
        2) status_text="Charging" ;;
        3) status_text="Discharging" ;;
        4) status_text="Not Charging" ;;
        5) status_text="Full" ;;
        *) status_text="Unavailable" ;;
    esac

    show "Battery Level" "${level:-Unknown}%"
    show "Battery Status" "$status_text"

    if [ -n "$temp" ]; then
        show "Temperature" "$(awk -v t="$temp" 'BEGIN {printf "%.1f C",t/10}')"
    fi

    show "Voltage" "${voltage:-Unknown} mV"

    section "DISPLAY"
    show "Resolution" "$(wm size 2>/dev/null)"
    show "Density" "$(wm density 2>/dev/null)"

    section "NETWORK"
    show "Wi-Fi IP" "$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')"
    show "Interfaces" "$(ip link show 2>/dev/null | awk -F ': ' '/^[0-9]+: / && $2 !~ /lo/ {print $2}' | tr '\n' ' ')"

    network=$(get_network)
    set -- $network

    if [ "$#" -ge 2 ]; then
        show "Total Received" "$(format_bytes "$1")"
        show "Total Transmitted" "$(format_bytes "$2")"

        if [ "$PREV_RX" -gt 0 ] 2>/dev/null; then
            rx_speed=$(( ($1 - PREV_RX) / 1 ))
            tx_speed=$(( ($2 - PREV_TX) / 1 ))
            show "Download Speed" "$(format_bytes "$rx_speed")/s"
            show "Upload Speed" "$(format_bytes "$tx_speed")/s"
        fi

        PREV_RX=$1
        PREV_TX=$2
    fi

    section "SYSTEM"
    show "Shell" "${SHELL:-Unknown}"
    show "Termux Prefix" "${PREFIX:-Unknown}"
    show "User" "$(id -un 2>/dev/null)"
    show "Hostname" "$(uname -n 2>/dev/null)"
    show "Refresh Rate" "1 second"

    printf '\n'
    rainbow "       LIVE MONITOR RUNNING"
    printf '\n'
    printf "${GRAY}       Press Q to exit${RESET}\n"
}

cleanup() {
    stty echo icanon 2>/dev/null
    printf '\033[0m\033[?25h\n'
    exit 0
}

trap cleanup INT TERM HUP

if [ -t 0 ]; then
    stty -echo -icanon min 0 time 0 2>/dev/null
fi

printf '\033[?25l'

while true; do
    cpu=$(cpu_usage)
    draw

    key=""
    if [ -t 0 ]; then
        key=$(dd bs=1 count=1 2>/dev/null)
    fi

    case "$key" in
        q|Q) cleanup ;;
    esac

    sleep 1
done
