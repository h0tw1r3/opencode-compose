#!/bin/bash

set -e

export WORKDIR="${PWD}"
if [ "${WORKDIR}" = "/must-be-set-at-runtime" ]; then
    echo >&2 "Error: Started without explicit working directory. Please set working directory to a mounted volume (e.g. use docker run --volume argument)."
    exit 1
fi

INVALID_WORKDIR_RE="^/(proc|sys|dev|run|var|tmp|etc|bin|sbin|usr|lib|lib64)(/|$)"
if [[ "$WORKDIR" =~ $INVALID_WORKDIR_RE ]]; then
    echo >&2 "Error: Unsupported working directory '$WORKDIR'."
    exit 1
fi

ACTUAL_RUID=$(id -ru)
ACTUAL_EUID=$(id -u)
ACTUAL_RGID=$(id -rg)

echo "Real UID (who started this): $ACTUAL_RUID:$ACTUAL_RGID"
echo "Effective UID (current power): $ACTUAL_EUID"

# Ensure we actually are root via SUID
if [ "$ACTUAL_EUID" -ne 0 ]; then
    echo "Error: Process is not running with root privileges (EUID: $ACTUAL_EUID)."
    exit 1
fi

# find the mount point for the working directory and ensure it's writable
CODE_PATH=""
while read -r mount; do
    if [ "$mount" = "$WORKDIR" ]; then
        if [ ! -w "$mount" ]; then
            echo >&2 "Error: Working directory volume '$mount' is not writable."
            exit 1
        fi
        CODE_PATH="$mount"
    fi
done < <(awk '{ print $2 }' /proc/mounts)

if [ -z "${CODE_PATH:-}" ]; then
    echo >&2 "Error: Working directory '$WORKDIR' not a volume. Working directory must mounted (e.g. use docker run --volume argument)."
    exit 1
fi

CODE_UID=$(stat -c "%u" "$CODE_PATH")
CODE_GID=$(stat -c "%g" "$CODE_PATH")

echo "Working directory: '$CODE_PATH' (Owner UID: $CODE_UID, GID: $CODE_GID)"

# change node user and group to match the owner of the code path
if [ "$CODE_UID" -eq 0 ]; then
    echo "Working directory is owned by root (common on Mac/Docker Desktop). Skipping usermod."
else
    echo "Updating 'node' user to match volume mount ($CODE_UID:$CODE_GID)..."
    usermod -u "$CODE_UID" -g "$CODE_GID" node
fi

# if no args, default to bash
if [ "$#" -eq 0 ]; then
    set -- bash
fi

# run as owner an group of the mount
exec setpriv --reuid=node --regid=node --init-groups \
    /bin/bash -l -c 'exec "$@"' -- "$@"
