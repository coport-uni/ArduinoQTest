#!/bin/bash
# Keeps ADB TCP mode armed on the phone that drives the MyHyundai app.
#
# The myhyundai_aircon integration reaches the phone over ADB on TCP
# 5555, but adbd falls back to USB-only on every phone boot and
# nothing on the phone side re-enables it. Left alone, the config
# entry sits in setup_retry and away-car-aircon.yaml stops firing
# silently -- its condition on switch.myhyundai_aircon can never be
# true while the entity is unavailable.
#
# This script probes the port and re-arms it over the USB cable the
# phone already hangs off, but only when the port is actually shut.
# The happy path is a single TCP connect, so it is cheap enough to
# run from a short-interval timer.

set -u

phone_serial="${PHONE_SERIAL:-R3CR80H1GBN}"
phone_host="${PHONE_HOST:-192.168.31.113}"
adb_port="${ADB_PORT:-5555}"

probe_timeout_s=5
adb_timeout_s=30
settle_after_tcpip_s=5

# The board carries a standalone adb extracted from .debs, because
# Debian's adb package conflicts with the preinstalled Arduino
# android libraries. It only runs with its own libraries on the path.
adb_root=/home/arduino/adb-local/rootfs
adb_bin="$adb_root/usr/bin/adb"
export LD_LIBRARY_PATH="$adb_root/usr/lib/aarch64-linux-gnu/android"

# Reports whether the phone accepts an ADB connection over TCP.
is_tcp_armed() {
    timeout "$probe_timeout_s" bash -c \
        "cat < /dev/null > /dev/tcp/$phone_host/$adb_port" 2> /dev/null
}

# Reports whether the phone is attached over USB and still
# authorised. An unauthorised phone lists as "unauthorized" and
# cannot be commanded, so it must not count as ready.
is_usb_ready() {
    timeout "$adb_timeout_s" "$adb_bin" devices < /dev/null 2> /dev/null \
        | grep -q "^$phone_serial[[:space:]]\+device$"
}

if [ ! -x "$adb_bin" ]; then
    echo "adb client missing at $adb_bin." >&2
    exit 1
fi

if is_tcp_armed; then
    exit 0
fi

echo "ADB TCP $phone_host:$adb_port is shut; re-arming over USB."

if ! is_usb_ready; then
    echo "Phone $phone_serial is not attached and authorised over" \
         "USB, so TCP cannot be re-armed. Check the cable and the" \
         "USB debugging prompt on the phone." >&2
    exit 1
fi

if ! timeout "$adb_timeout_s" "$adb_bin" -s "$phone_serial" \
        tcpip "$adb_port" < /dev/null; then
    echo "adb tcpip $adb_port failed." >&2
    exit 1
fi

sleep "$settle_after_tcpip_s"

if is_tcp_armed; then
    echo "ADB TCP $phone_host:$adb_port is armed again."
    exit 0
fi

echo "Re-arm ran but $phone_host:$adb_port is still shut." >&2
exit 1
