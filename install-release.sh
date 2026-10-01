#!/usr/bin/env ash
# shellcheck shell=dash

set -euo pipefail

# 本仓库的 owner/repo（Release Assets 宿主），按实际修改。
# 也可运行时覆盖：REPO=foo/bar ./install-release.sh
REPO="${REPO:-bbw3000/Xray-AlpineInstall}"
BASE_URL="https://github.com/$REPO/releases/latest/download"

pkg_manager() {
    local OP="$1" PM=apk
    shift
    if [ -f /etc/gentoo-release ]; then
        PM=emerge
        case "$OP" in
        add)
            OP='-v'
            ;;
        del)
            OP='-C'
            ;;
        esac
    fi
    if [ $# -eq 0 ]; then
        echo "$PM $OP"
    else
        $PM "$OP" "$@"
    fi
}

check_distro() {
    if [ -z "$(command -v rc-service)" ]; then
        echo "No OpenRC init-system detected."
        return 1
    fi
    if [ -f /etc/alpine-release ] || [ -f /etc/gentoo-release ]; then
        return 0
    else
        return 1
    fi
}

check_if_running_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    else
        echo "error: You must run this script as root!"
        return 1
    fi
}

identify_architecture() {
    if [ "$(uname)" != 'Linux' ]; then
        echo "error: This operating system is not supported."
        return 1
    fi
    case "$(uname -m)" in
    'amd64' | 'x86_64')
        ;;
    *)
        echo "error: This script (low-memory build) only supports amd64/x86_64."
        return 1
        ;;
    esac
    if [ ! -f '/etc/os-release' ]; then
        echo "error: Don't use outdated Linux distributions."
        return 1
    fi
}

install_dependencies() {
    if [ -n "$(command -v curl)" ]; then
        return
    fi
    if [ "$(command -v apk)" ]; then
        echo "Installing required dependencies..."
        pkg_manager add curl # low-memory build: no unzip needed
    else
        echo "error: The script does not support the package manager in this operating system."
        exit 1
    fi
}

download_xray() {
    echo "Downloading Xray files (pre-extracted bare binaries)..."
    for f in xray geoip.dat geosite.dat xray.sha256 geoip.dat.sha256 geosite.dat.sha256; do
        if ! curl -f -L -H 'Cache-Control: no-cache' -o "$TMP_DIRECTORY$f" "$BASE_URL/$f" -#; then
            echo 'error: Download failed! Please check your network or try again.'
            exit 1
        fi
    done
}

verification_xray() {
    (cd "$TMP_DIRECTORY" && sha256sum -c xray.sha256) || {
        echo 'error: SHA256 check failed for xray! Please check your network or try again.'
        return 1
    }
    (cd "$TMP_DIRECTORY" && sha256sum -c geoip.dat.sha256) || {
        echo 'error: SHA256 check failed for geoip.dat! Please check your network or try again.'
        return 1
    }
    (cd "$TMP_DIRECTORY" && sha256sum -c geosite.dat.sha256) || {
        echo 'error: SHA256 check failed for geosite.dat! Please check your network or try again.'
        return 1
    }
    chmod +x "${TMP_DIRECTORY}xray"
}

is_it_running() {
    XRAY_RUNNING='0'
    if [ -n "$(pgrep xray)" ]; then
        rc-service xray stop
        XRAY_RUNNING='1'
    fi
}

install_xray() {
    install -m 755 "${TMP_DIRECTORY}xray" "/usr/local/bin/xray"
    install -d /usr/local/share/xray/
    install -m 644 "${TMP_DIRECTORY}geoip.dat" "/usr/local/share/xray/geoip.dat"
    install -m 644 "${TMP_DIRECTORY}geosite.dat" "/usr/local/share/xray/geosite.dat"
}

install_confdir() {
    CONFDIR='0'
    if [ ! -d '/usr/local/etc/xray/' ]; then
        install -d /usr/local/etc/xray/
        for BASE in 00_log 01_api 02_dns 03_routing 04_policy 05_inbounds 06_outbounds 07_transport 08_stats 09_reverse; do
            echo '{}' >"/usr/local/etc/xray/$BASE.json"
        done
        CONFDIR='1'
    fi
}

install_log() {
    LOG='0'
    if [ ! -d '/var/log/xray/' ]; then
        install -d -m 755 -o 0 -g 0 /var/log/xray/
        install -m 600 -o nobody -g nobody /dev/null /var/log/xray/access.log
        install -m 600 -o nobody -g nobody /dev/null /var/log/xray/error.log
        LOG='1'
    else
        chown 0:0 /var/log/xray/
        chmod 755 /var/log/xray/
        chown nobody:nobody /var/log/xray/*.log
        chmod 600 /var/log/xray/*.log
    fi
}

install_startup_service_file() {
    OPENRC='0'
    if [ ! -f '/etc/init.d/xray' ]; then
        mkdir "${TMP_DIRECTORY}init.d/"
        if ! curl -f -L -o "${TMP_DIRECTORY}init.d/xray" https://github.com/XTLS/Xray-install/raw/main/alpinelinux/init.d/xray -sS; then
            echo 'error: Failed to start service file download! Please check your network or try again.'
            exit 1
        fi
        install -m 755 "${TMP_DIRECTORY}init.d/xray" /etc/init.d/xray
        OPENRC='1'
    fi
}

information() {
    echo 'installed: /usr/local/bin/xray'
    echo 'installed: /usr/local/share/xray/geoip.dat'
    echo 'installed: /usr/local/share/xray/geosite.dat'
    if [ "$CONFDIR" -eq '1' ]; then
        echo 'installed: /usr/local/etc/xray/00_log.json'
        echo 'installed: /usr/local/etc/xray/01_api.json'
        echo 'installed: /usr/local/etc/xray/02_dns.json'
        echo 'installed: /usr/local/etc/xray/03_routing.json'
        echo 'installed: /usr/local/etc/xray/04_policy.json'
        echo 'installed: /usr/local/etc/xray/05_inbounds.json'
        echo 'installed: /usr/local/etc/xray/06_outbounds.json'
        echo 'installed: /usr/local/etc/xray/07_transport.json'
        echo 'installed: /usr/local/etc/xray/08_stats.json'
        echo 'installed: /usr/local/etc/xray/09_reverse.json'
    fi
    if [ "$LOG" -eq '1' ]; then
        echo 'installed: /var/log/xray/'
    fi
    if [ "$OPENRC" -eq '1' ]; then
        echo 'installed: /etc/init.d/xray'
    fi
    rm -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    echo "You may need to execute a command to remove dependent software: $(pkg_manager del) curl"
    if [ "$XRAY_RUNNING" -eq '1' ]; then
        rc-service xray start
    else
        echo 'Please execute the command: rc-update add xray; rc-service xray start'
    fi
    echo "info: Xray is installed."
}

main() {
    check_distro || return 1
    check_if_running_as_root || return 1
    identify_architecture || return 1
    install_dependencies

    TMP_DIRECTORY="$(mktemp -d)/"

    download_xray
    verification_xray
    is_it_running
    install_xray
    install_confdir
    install_log
    install_startup_service_file || return 1
    information
}

main
