#!/usr/bin/env bash
# files/zfs-mount.sh - Robust automount and decrypt ZFS pool hdd_zfs
# Can be safely executed multiple times (e.g., from cron).

set -euo pipefail

# Configuration
POOL="hdd_zfs"
BLOCK_UUID="206d8801-6af1-4857-90b0-cc7a030e8ae8"
KEY_FILE="/data/archive/${BLOCK_UUID}.lek"
MOUNT_POINT="/hdd_zfs/backup"

# Logging helper
log() {
    local level="$1"
    local msg="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" >&2
    logger -t "zfs-mount.sh" "[${level}] $msg"
}

# Ensure required commands exist
for cmd in cryptsetup zpool mountpoint; do
    if ! command -v "$cmd" &>/dev/null; then
        log "ERROR" "Required command '$cmd' not found in PATH."
        exit 127
    fi
done

# 1. Check that the mapper device does not already exist
if [[ -e "/dev/mapper/${POOL}" ]]; then
    log "INFO" "Mapper device /dev/mapper/${POOL} already exists – assuming pool is ready."
else
    # 2. Verify key file presence
    if [[ ! -f "${KEY_FILE}" ]]; then
        log "ERROR" "Key file '${KEY_FILE}' not found."
        exit 1
    fi

    # 3. Open LUKS container
    log "INFO" "Opening LUKS device ${BLOCK_UUID} -> /dev/mapper/${POOL}"
    cryptsetup luksOpen "/dev/disk/by-uuid/${BLOCK_UUID}" "${POOL}" --key-file "${KEY_FILE}"
fi

# 4. Ensure the ZFS pool is imported
if ! zpool list -H "${POOL}" &>/dev/null; then
    log "INFO" "Pool ${POOL} not imported – attempting import from by-id"
    # Import using persistent by-id path; ignore failure if already present
    if ! zpool import -d "/dev/disk/by-id" "${POOL}"; then
        log "ERROR" "Failed to import ZFS pool '${POOL}'."
        exit 2
    fi
fi

# 5. Verify mount point is not mounted yet
if mountpoint -q "${MOUNT_POINT}"; then
    log "WARN" "Mount point ${MOUNT_POINT} already mounted – skipping mount."
else
    # Mount the pool (assuming dataset is directly under /hdd_zfs/backup)
    log "INFO" "Mounting ZFS pool '${POOL}' to ${MOUNT_POINT}"
    mkdir -p "${MOUNT_POINT}"
    mount -t zfs "${POOL}" "${MOUNT_POINT}"
fi

log "INFO" "ZFS pool '${POOL}' is ready and mounted at ${MOUNT_POINT}."
exit 0