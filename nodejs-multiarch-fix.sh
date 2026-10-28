#!/bin/sh
# Version: 7
# Date: 2026-10-28

set -eu

PROGRAM=${0##*/}
BACKUP_ROOT=/var/backups/nodejs-multiarch-fix
APT_DOWNLOAD_ROOT=/var/cache/apt/archives/partial

usage() {
    printf 'Usage: %s --check | --install\n' "$PROGRAM"
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

check_platform() {
    [ -r /etc/os-release ] || fail 'Cannot identify the operating system.'
    . /etc/os-release
    [ "${ID:-}" = debian ] || fail 'Only Debian 12 Bookworm and Debian 13 Trixie are supported.'
    case "${VERSION_CODENAME:-}" in
        bookworm|trixie) ;;
        *) fail 'Only Debian 12 Bookworm and Debian 13 Trixie are supported.' ;;
    esac
    case "$(dpkg --print-architecture)" in
        arm64|amd64) ;;
        *) fail 'Only arm64 and amd64 are supported.' ;;
    esac
}

installed_status() {
    dpkg-query -W -f='${Status}' nodejs 2>/dev/null || true
}

node_package_version() {
    dpkg-query -W -f='${Version}' nodejs 2>/dev/null || true
}

installed_multi_arch() {
    dpkg-query -W -f='${Multi-Arch}' nodejs 2>/dev/null || true
}

candidate_nodejs_version() {
    apt-cache policy nodejs | awk '
        /^  Candidate:/ { candidate = $2 }
        /^ \*\*\*/ { version = $2; in_candidate = (version == candidate); next }
        /^[[:space:]]+[0-9][^[:space:]]*[[:space:]]+[0-9]+[[:space:]]*$/ { version = $1; in_candidate = (version == candidate); next }
        in_candidate && /deb\.nodesource\.com\/node_/ { found = 1 }
        END { if (candidate != "" && candidate != "(none)" && found) print candidate }
    '
}

local_package_version() {
    printf '%s+asl1\n' "$1"
}

upstream_package_version() {
    case "$1" in
        *+asl1) printf '%s\n' "${1%+asl1}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

prepare_patched_package() {
    source_deb=$1
    output_deb=$2
    extract_dir=$3
    target_version=$4
    mkdir "$extract_dir"
    dpkg-deb -R "$source_deb" "$extract_dir"
    control="$extract_dir/DEBIAN/control"
    sed -i "s/^Version:.*/Version: $target_version/" "$control"
    if grep -q '^Multi-Arch:' "$control"; then
        sed -i 's/^Multi-Arch:.*/Multi-Arch: allowed/' "$control"
    else
        sed -i '/^Package: /a Multi-Arch: allowed' "$control"
    fi
    dpkg-deb --build "$extract_dir" "$output_deb" >/dev/null
    [ "$(dpkg-deb -f "$output_deb" Version)" = "$target_version" ] || fail 'The rebuilt package does not contain the expected local version revision.'
    [ "$(dpkg-deb -f "$output_deb" Multi-Arch)" = allowed ] || fail 'The rebuilt package does not contain Multi-Arch: allowed.'
}

find_installed_backup() {
    [ -d "$BACKUP_ROOT" ] || return 1
    find "$BACKUP_ROOT" -type f -name nodejs-multiarch-allowed.deb -print 2>/dev/null | while IFS= read -r package; do
        if [ "$(dpkg-deb -f "$package" Version 2>/dev/null || true)" = "$1" ] &&
            [ "$(dpkg-deb -f "$package" Multi-Arch 2>/dev/null || true)" = allowed ]; then
            printf '%s\n' "$package"
            exit 0
        fi
    done
}

download_package() {
    package_spec=$1
    output_path=$2
    [ -d "$APT_DOWNLOAD_ROOT" ] || fail "APT download staging directory is missing: $APT_DOWNLOAD_ROOT"
    download_dir=$(mktemp -d "$APT_DOWNLOAD_ROOT/nodejs-multiarch-fix.XXXXXX")
    chown _apt "$download_dir"
    chmod 0700 "$download_dir"
    if ! (cd "$download_dir" && apt-get download "$package_spec"); then
        rm -rf "$download_dir"
        download_dir=
        return 1
    fi
    downloaded=$(find "$download_dir" -maxdepth 1 -type f -name '*.deb' -print -quit)
    if [ -z "$downloaded" ]; then
        rm -rf "$download_dir"
        download_dir=
        return 1
    fi
    mv "$downloaded" "$output_path"
    rmdir "$download_dir"
    download_dir=
}

cleanup() {
    [ -z "${download_dir:-}" ] || rm -rf "$download_dir"
    [ -z "${work:-}" ] || rm -rf "$work"
}

check_mode() {
    check_platform
    [ "$(installed_status)" = 'install ok installed' ] || fail 'Node.js is not installed as a Debian package.'
    version=$(node_package_version)
    candidate=$(candidate_nodejs_version)
    multi_arch=$(installed_multi_arch)
    upstream_version=$(upstream_package_version "$version")
    printf 'OS: Debian %s (%s)\n' "${VERSION_ID:-unknown}" "$VERSION_CODENAME"
    printf 'Architecture: %s\n' "$(dpkg --print-architecture)"
    printf 'Node.js package version: %s\n' "$version"
    printf 'NodeSource candidate version: %s\n' "${candidate:-not found}"
    printf 'Installed Multi-Arch metadata: %s\n' "${multi_arch:-unset}"
    [ -n "$candidate" ] || fail 'The APT candidate is not available from the configured NodeSource repository.'
    case "$candidate" in
        *nodesource*) ;;
        *) fail 'The APT candidate does not identify a NodeSource build.' ;;
    esac
    if [ "$multi_arch" = allowed ] && [ "$candidate" = "$upstream_version" ] && [ "$version" != "$upstream_version" ]; then
        printf 'PASS: nodejs can satisfy nodejs:any dependencies and is current. No changes made.\n'
        return 0
    fi
    if [ "$multi_arch" != allowed ]; then
        printf 'NEEDS PATCH: installed nodejs metadata is not Multi-Arch: allowed. No changes made.\n'
    fi
    if [ "$candidate" != "$upstream_version" ]; then
        printf 'NEEDS UPDATE: NodeSource candidate %s differs from installed version %s. No changes made.\n' "$candidate" "$version"
    fi
    if [ "$version" = "$upstream_version" ]; then
        printf 'NEEDS REPACK: the installed version lacks the local +asl1 revision that prevents APT from reinstalling NodeSource metadata. No changes made.\n'
    fi
}

install_mode() {
    [ "$(id -u)" -eq 0 ] || fail 'Run --install with sudo or as root.'
    check_platform
    [ "$(installed_status)" = 'install ok installed' ] || fail 'Node.js is not installed as a Debian package.'

    installed_version=$(node_package_version)
    installed_upstream_version=$(upstream_package_version "$installed_version")
    candidate=$(candidate_nodejs_version)
    multi_arch=$(installed_multi_arch)
    target_version=$(local_package_version "$candidate")
    [ -n "$candidate" ] || fail 'The APT candidate is not available from the configured NodeSource repository.'
    case "$candidate" in
        *nodesource*) ;;
        *) fail 'The APT candidate does not identify a NodeSource build; refusing to alter it.' ;;
    esac
    if [ "$multi_arch" = allowed ] && [ "$candidate" = "$installed_upstream_version" ] && [ "$installed_version" != "$installed_upstream_version" ]; then
        printf 'PASS: nodejs is Multi-Arch: allowed and current. No changes made.\n'
        return 0
    fi
    command -v apt-get >/dev/null 2>&1 || fail 'apt-get is required.'
    command -v dpkg-deb >/dev/null 2>&1 || fail 'dpkg-deb is required.'

    arch=$(dpkg --print-architecture)
    node_before=$(node --version 2>/dev/null) || fail 'The node command is unavailable.'
    [ -d /home/asl ] || fail 'The ASL user home /home/asl is required for disk-backed staging.'
    work=$(mktemp -d /home/asl/.nodejs-multiarch-fix.XXXXXX)
    download_dir=
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    cd "$work"

    candidate_deb="$work/nodejs_${candidate}_${arch}_original.deb"
    printf 'Downloading NodeSource nodejs package %s for %s...\n' "$candidate" "$arch"
    download_package "nodejs:${arch}=${candidate}" "$candidate_deb" || fail 'APT could not download the NodeSource nodejs candidate package.'

    deb_package=$(dpkg-deb -f "$candidate_deb" Package)
    deb_version=$(dpkg-deb -f "$candidate_deb" Version)
    deb_arch=$(dpkg-deb -f "$candidate_deb" Architecture)
    installed_size_kb=$(dpkg-deb -f "$candidate_deb" Installed-Size)
    [ "$deb_package" = nodejs ] || fail "Downloaded package name is '$deb_package', expected nodejs."
    [ "$deb_version" = "$candidate" ] || fail "Downloaded version '$deb_version' differs from APT candidate '$candidate'."
    [ "$deb_arch" = "$arch" ] || fail "Downloaded architecture '$deb_arch' differs from system architecture '$arch'."
    case "$installed_size_kb" in
        ''|*[!0-9]*) fail 'Downloaded package has no valid Installed-Size field.' ;;
    esac
    package_size_bytes=$(wc -c < "$candidate_deb" | tr -d '[:space:]')
    package_size_kb=$(((package_size_bytes + 1023) / 1024))
    available_kb=$(df -Pk /home/asl | awk 'NR == 2 { print $4 }')
    required_kb=$((2 * installed_size_kb + 5 * package_size_kb + 102400))
    [ -n "$available_kb" ] || fail 'Could not determine free space on /home/asl.'
    [ "$available_kb" -ge "$required_kb" ] || fail "Insufficient free space on /home/asl: need about ${required_kb} KiB, have ${available_kb} KiB."

    patched_deb="$work/nodejs_${target_version}_${arch}_multiarch.deb"
    prepare_patched_package "$candidate_deb" "$patched_deb" "$work/package" "$target_version"

    stamp=$(date '+%Y%m%d-%H%M%S')
    install -d -m 0700 "$BACKUP_ROOT"
    backup_dir=$(mktemp -d "$BACKUP_ROOT/install-${stamp}.XXXXXX")
    chmod 0700 "$backup_dir"
    cp -p "$candidate_deb" "$backup_dir/nodejs-original-candidate.deb"
    cp -p "$patched_deb" "$backup_dir/nodejs-multiarch-allowed.deb"
    rollback_deb=
    if [ "$installed_version" != "$candidate" ]; then
        rollback_deb=$(find_installed_backup "$installed_version" || true)
        if [ -n "$rollback_deb" ]; then
            cp -p "$rollback_deb" "$backup_dir/nodejs-previous-multiarch-allowed.deb"
            rollback_deb="$backup_dir/nodejs-previous-multiarch-allowed.deb"
        else
            printf 'Downloading installed Node.js version %s to prepare a rollback package...\n' "$installed_version"
            previous_original="$work/nodejs-previous-original.deb"
            if download_package "nodejs:${arch}=${installed_version}" "$previous_original"; then
                if [ "$(dpkg-deb -f "$previous_original" Version)" = "$installed_version" ]; then
                    cp -p "$previous_original" "$backup_dir/nodejs-previous-original.deb"
                    prepare_patched_package "$previous_original" "$backup_dir/nodejs-previous-multiarch-allowed.deb" "$work/previous-package" "$installed_version"
                    rollback_deb="$backup_dir/nodejs-previous-multiarch-allowed.deb"
                fi
            fi
        fi
        [ -n "$rollback_deb" ] || fail 'No rollback package for the installed Node.js version could be prepared; no package was changed.'
    else
        cp -p "$candidate_deb" "$backup_dir/nodejs-original.deb"
        rollback_deb="$backup_dir/nodejs-original.deb"
    fi
    printf 'Backup directory: %s\n' "$backup_dir"
    printf 'Installing Node.js %s as local package version %s with Multi-Arch: allowed.\n' "$candidate" "$target_version"

    if ! dpkg -i "$backup_dir/nodejs-multiarch-allowed.deb"; then
        printf 'Install failed; attempting to restore the previous Node.js package.\n' >&2
        dpkg -i "$rollback_deb" || true
        fail "Install failed. Rollback package: $rollback_deb"
    fi

    node_after=$(node --version 2>/dev/null || true)
    multi_arch_after=$(installed_multi_arch)
    expected_node_version="v${candidate%%-*}"
    installed_after=$(node_package_version)
    if [ "$node_after" != "$expected_node_version" ] || [ "$multi_arch_after" != allowed ] || [ "$installed_after" != "$target_version" ]; then
        printf 'Verification failed; restoring the previous Node.js package.\n' >&2
        dpkg -i "$rollback_deb" || true
        fail "Post-install verification failed. Rollback package: $rollback_deb"
    fi

    printf 'PASS: Node.js is %s, package version is %s, and metadata is Multi-Arch: allowed.\n' "$node_after" "$installed_after"
    printf 'If a later NodeSource update is held back, rerun --check and then --install to apply its candidate safely.\n'
}

case "${1:-}" in
    --check) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; check_mode ;;
    --install) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; install_mode ;;
    *) usage >&2; exit 2 ;;
esac
