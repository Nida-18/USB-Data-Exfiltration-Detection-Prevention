#!/bin/bash

# =============================
# USB Data Exfiltration Prevention + Transfer Monitoring
# =============================

LOGFILE="./transfer_log.txt"
THRESHOLD=$((500 * 1024 * 1024))   # 500 MB delta limit
OVERWRITE_HASH="./overwrite.hash"
PASSWORD_HASH="./password.hash"
WHITELIST="./whitelist.txt"

declare -A BLOCKED_DEVS
declare -A MONITOR_PIDS

LOG() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOGFILE"
}

zen() {
    local target_user="${SUDO_USER:-$USER}"
    local uid
    uid=$(id -u "$target_user")
    sudo -u "$target_user" \
        DISPLAY="${DISPLAY:-:0}" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        zenity "$@" 2>/dev/null
}

verify_password() {
    local hashfile="$1"
    local prompt="$2"

    if [[ ! -f "$hashfile" ]]; then
        LOG "Hash file missing: $hashfile"
        return 1
    fi

    local password entered_hash stored_hash
    password=$(zen --password --title="Authentication Required" --text="$prompt") || return 1
    entered_hash=$(printf '%s' "$password" | sha256sum | awk '{print $1}')
    stored_hash=$(tr -d '[:space:]' < "$hashfile")

    [[ "$entered_hash" == "$stored_hash" ]]
}

# Returns full partition paths like /dev/sdb1
get_usb_partitions() {
    lsblk -nrpo NAME,TRAN,TYPE | awk '$2=="usb" && $3=="part" {print $1}'
}

monitor_transfer() {
    local mountdir="$1"
    local device="$2"
    local initial_used
    initial_used=$(df -B1 --output=used "$mountdir" 2>/dev/null | tail -n1 | tr -d '[:space:]')
    initial_used=${initial_used:-0}

    LOG "Monitoring transfer on $mountdir (Baseline: $initial_used bytes)"

    while mountpoint -q "$mountdir"; do
        local current_used delta
        current_used=$(df -B1 --output=used "$mountdir" 2>/dev/null | tail -n1 | tr -d '[:space:]')
        current_used=${current_used:-0}
        delta=$((current_used - initial_used))

        if (( delta > THRESHOLD )); then
            LOG "TRANSFER LIMIT BREACHED on $device: +$delta bytes"

            # Terminate active copy processes and force unmount
            fuser -km "$mountdir" 2>/dev/null
            umount -l "$mountdir" 2>/dev/null

            if verify_password "$OVERWRITE_HASH" "500MB+ transfer detected. Enter overwrite password:"; then
                LOG "Overwrite password accepted. Remounting $device..."
                mount "$device" "$mountdir" 2>/dev/null
                # Reset baseline so it doesn't immediately re-trigger
                initial_used=$(df -B1 --output=used "$mountdir" 2>/dev/null | tail -n1 | tr -d '[:space:]')
            else
                LOG "Wrong overwrite password. Blocking $device."
                udisksctl power-off -b "$device" 2>/dev/null
                return
            fi
        fi

        sleep 2
    done
}

# Cleanup background monitors on exit
trap 'kill ${MONITOR_PIDS[@]} 2>/dev/null; exit' INT TERM EXIT

touch "$WHITELIST"
LOG "USB Data Exfiltration Prevention Started"

while true; do
    current_devs=$(get_usb_partitions)

    # Clear blocked status for devices that were physically unplugged
    for tracked in "${!BLOCKED_DEVS[@]}"; do
        if ! grep -Fxq "$tracked" <<< "$current_devs"; then
            unset "BLOCKED_DEVS[$tracked]"
            LOG "Removed unplugged device $tracked from blocklist"
        fi
    done

    for device in $current_devs; do
        # Skip if already blocked or already mounted
        [[ -n "${BLOCKED_DEVS[$device]}" ]] && continue
        dev_name=$(basename "$device")
        mountdir="/mnt/usb_$dev_name"
        mountpoint -q "$mountdir" && continue

        uuid=$(lsblk -no UUID "$device" 2>/dev/null | tr -d '[:space:]')

        # Whitelist Check by UUID
        if [[ -n "$uuid" ]] && grep -Fxq "$uuid" "$WHITELIST"; then
            LOG "Whitelisted USB detected: $device (UUID: $uuid)"
        else
            LOG "Untrusted USB: $device (UUID: ${uuid:-none})"

            if verify_password "$PASSWORD_HASH" "Enter password to allow USB access ($dev_name):"; then
                LOG "Password accepted for $device"
            else
                LOG "Password wrong/cancelled — blocking $device until unplugged"
                BLOCKED_DEVS["$device"]=1
                umount -l "$device" 2>/dev/null
                udisksctl power-off -b "$device" 2>/dev/null
                continue
            fi
        fi

        # Mount with user write permissions (UID 1000) and start transfer monitor
        mkdir -p "$mountdir"
        target_uid=$(id -u "${SUDO_USER:-$USER}")
        if mount -o "uid=$target_uid,gid=$target_uid" "$device" "$mountdir" 2>/dev/null || mount "$device" "$mountdir" 2>/dev/null; then
            LOG "Mounted $device at $mountdir"
            monitor_transfer "$mountdir" "$device" &
            MONITOR_PIDS["$device"]=$!
        else
            LOG "Failed to mount $device"
            rmdir "$mountdir" 2>/dev/null
        fi
    done

    sleep 2
done
