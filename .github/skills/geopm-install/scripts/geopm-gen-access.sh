#!/bin/bash
#  Copyright (c) 2015 - 2026 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#
#  Generate reviewable geopmaccess commands that grant a Unix group the
#  signals and controls a tuning campaign needs.  This script never modifies
#  an access list: it only prints commands for an administrator to inspect
#  and run.  Requested names are filtered against what the platform actually
#  supports and validated with 'geopmaccess --write --dry-run', which needs no
#  privileges.

set -uo pipefail

GROUP=""
OUT_DIR="."
EXTRA_SIGNALS=()
EXTRA_CONTROLS=()

# Controls a campaign may sweep, and the signals needed to measure the result.
# A frequency sweep is meant to pin rather than cap: geopmopt mirrors a *_MAX_*
# control onto the matching *_MIN_* control, but only when that MIN is in
# pio.control_names() -- which, for a service-backed client, is the granted
# list.  Granting only the MAX therefore does not raise a permission error; the
# companion is silently dropped and the campaign sweeps a MAX-only cap, losing
# the pinning it was supposed to have.  Request both.  CPU_FREQUENCY_MIN_CONTROL
# is the one exception, deliberately excluded by grid.py, so it is not
# requested here.
#
# CPU_FREQUENCY_GOVERNOR_CONTROL is requested unconditionally because geopmopt
# forces it to 'performance' whenever cpu-freq is swept, regardless of whether
# cpu-freq is in this particular request; omitting it fails
# geopm-verify-install.sh's readiness gate, and only fails partway through a
# campaign if that check is skipped.
#
# cpu-power is granted as POWERCAP::CPU_POWER_LIMIT, not the similarly named
# CPU_POWER_LIMIT_CONTROL alias: grid.py's cpu-power dimension writes the
# POWERCAP-iogroup control specifically, and the two names are different
# controls (different iogroup) despite sharing a description.
#
# The four MSR prefetcher-disable controls are one set: every prefetch level
# writes all four (grid.py's prefetch_settings()), so granting a subset leaves
# the dimension unusable.  The supported-name filtering below drops them
# safely on platforms that do not expose them.
DEFAULT_CONTROLS=(
    CPU_FREQUENCY_MAX_CONTROL
    CPU_FREQUENCY_GOVERNOR_CONTROL
    CPU_UNCORE_FREQUENCY_MAX_CONTROL
    CPU_UNCORE_FREQUENCY_MIN_CONTROL
    POWERCAP::CPU_POWER_LIMIT
    GPU_CORE_FREQUENCY_MAX_CONTROL
    GPU_CORE_FREQUENCY_MIN_CONTROL
    GPU_POWER_LIMIT_CONTROL
    BOARD_POWER_LIMIT_CONTROL
)
# The four prefetcher-disable controls are one atomic set: every prefetch level
# writes all four (grid.py's prefetch_settings()), so a partial grant is
# useless.  They are added below only when the whole set is supported, not
# filtered independently like the controls above.
PREFETCH_CONTROLS=(
    MSR::MISC_FEATURE_CONTROL:DCU_HW_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:L2_HW_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:DCU_IP_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:L2_ADJACENT_PREFETCHER_DISABLE
)
# Every bound signal grid.py uses to resolve a dimension's range is granted as
# a *signal*, including the two controls it reads back as a bound
# (CPU_UNCORE_FREQUENCY_MAX_CONTROL, GPU_POWER_LIMIT_CONTROL).  Without them a
# freshly granted control still reports n/a bounds and the dimension is
# unusable.  Unsupported names are dropped by the filtering below.
DEFAULT_SIGNALS=(
    TIME
    CPU_POWER
    CPU_ENERGY
    CPU_FREQUENCY_STATUS
    CPU_FREQUENCY_MAX_AVAIL
    CPU_FREQUENCY_MIN_AVAIL
    CPU_FREQUENCY_STICKER
    CPU_FREQUENCY_STEP
    CPU_UNCORE_FREQUENCY_MAX_CONTROL
    CPU_POWER_LIMIT_DEFAULT
    CPU_POWER_MIN_AVAIL
    CPU_POWER_MAX_AVAIL
    GPU_POWER
    GPU_ENERGY
    GPU_CORE_FREQUENCY_MIN_AVAIL
    GPU_CORE_FREQUENCY_MAX_AVAIL
    GPU_CORE_FREQUENCY_STEP
    GPU_POWER_LIMIT_CONTROL
    LEVELZERO::GPU_POWER_LIMIT_MIN_AVAIL
    LEVELZERO::GPU_POWER_LIMIT_DEFAULT
    BOARD_POWER
    BOARD_ENERGY
)

print_usage() {
    cat <<'USAGE'
Usage: geopm-gen-access.sh --group GROUP [OPTION]...

Print the geopmaccess commands that grant GROUP the access a GEOPM tuning
campaign requires, together with the commands that undo them.  Nothing is
executed and no file is written outside --out-dir.

Options:
  --group GROUP     Unix group to grant access to.  Required.  Granting a
                    dedicated group is preferred over editing the default
                    list, because it can be revoked cleanly afterwards.
  --signal NAME     Request an extra signal.  Repeatable.
  --control NAME    Request an extra control.  Repeatable.
  --out-dir DIR     Where to write the generated list files (default: .).
  -h, --help        Print this help message and exit.

The generated commands must be run by an administrator.  Review them first:
they change what every member of GROUP may do to the hardware.
USAGE
}

while (( $# )); do
    case "$1" in
        --group) [[ $# -ge 2 ]] || { echo "--group requires an argument" >&2; exit 2; }
                 GROUP="$2"; shift ;;
        --signal) [[ $# -ge 2 ]] || { echo "--signal requires an argument" >&2; exit 2; }
                  EXTRA_SIGNALS+=("$2"); shift ;;
        --control) [[ $# -ge 2 ]] || { echo "--control requires an argument" >&2; exit 2; }
                   EXTRA_CONTROLS+=("$2"); shift ;;
        --out-dir) [[ $# -ge 2 ]] || { echo "--out-dir requires an argument" >&2; exit 2; }
                   OUT_DIR="$2"; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "geopm-gen-access.sh: unknown option '$1'" >&2
           print_usage >&2; exit 2 ;;
    esac
    shift
done

if [[ -z $GROUP ]]; then
    echo "geopm-gen-access.sh: --group is required" >&2
    print_usage >&2
    exit 2
fi

if ! command -v geopmaccess >/dev/null 2>&1 && [[ ! -x /usr/bin/geopmaccess ]]; then
    echo "geopm-gen-access.sh: geopmaccess not found on PATH" >&2
    exit 1
fi

# Resolve ONE working geopmaccess up front and use it for every query.  A
# virtual environment built without --system-site-packages cannot import
# PyGObject, which dasbus needs, so the venv copy is on PATH but fails; the
# system copy still works.  Discovery, validation and the existing-list reads
# must all use the same working executable, or discovery can succeed via the
# fallback while validation then aborts on the broken bare command.
GEOPMACCESS=""
if geopmaccess --all >/dev/null 2>&1; then
    GEOPMACCESS=geopmaccess
elif /usr/bin/geopmaccess --all >/dev/null 2>&1; then
    GEOPMACCESS=/usr/bin/geopmaccess
fi
if [[ -z $GEOPMACCESS ]]; then
    echo "geopm-gen-access.sh: could not run geopmaccess (PATH copy or /usr/bin)." >&2
    echo "  Is geopmd running?  Try: systemctl is-active geopm" >&2
    echo "  If you are in a virtual environment, rebuild it with" >&2
    echo "  --system-site-packages so PyGObject is visible, or run this from a" >&2
    echo "  shell that can reach /usr/bin/geopmaccess." >&2
    exit 1
fi

if ! getent group "$GROUP" >/dev/null 2>&1; then
    echo "geopm-gen-access.sh: Unix group '$GROUP' does not exist." >&2
    echo "  Create it first, for example:  sudo groupadd $GROUP" >&2
    exit 1
fi

mkdir -p "$OUT_DIR" || exit 1

# Both discovery queries use the resolved executable and must both succeed:
# treating a failed controls query as empty data would drop every control from
# the grant and give incorrect guidance.
if ! supported_signals=$($GEOPMACCESS --all 2>/dev/null) || [[ -z $supported_signals ]]; then
    echo "geopm-gen-access.sh: could not query supported signals." >&2
    echo "  Is geopmd running?  Try: systemctl is-active geopm" >&2
    exit 1
fi
if ! supported_controls=$($GEOPMACCESS --all --controls 2>/dev/null) || [[ -z $supported_controls ]]; then
    echo "geopm-gen-access.sh: could not query supported controls." >&2
    echo "  Is geopmd running?  Try: systemctl is-active geopm" >&2
    exit 1
fi

# Keep only names this platform actually implements.  Requesting anything else
# makes geopmaccess reject the whole list, so filtering here keeps the grant
# minimal and valid.
select_supported() {
    local -n requested=$1
    local supported=$2
    local -n kept=$3
    local -n dropped=$4
    local name
    for name in "${requested[@]}"; do
        if printf '%s\n' "$supported" | grep -qx -- "$name"; then
            kept+=("$name")
        else
            dropped+=("$name")
        fi
    done
}

# shellcheck disable=SC2034  # both are read by select_supported through a nameref
want_controls=("${DEFAULT_CONTROLS[@]}" ${EXTRA_CONTROLS+"${EXTRA_CONTROLS[@]}"})
# shellcheck disable=SC2034
want_signals=("${DEFAULT_SIGNALS[@]}" ${EXTRA_SIGNALS+"${EXTRA_SIGNALS[@]}"})

keep_controls=(); drop_controls=()
keep_signals=();  drop_signals=()
select_supported want_controls "$supported_controls" keep_controls drop_controls
select_supported want_signals  "$supported_signals"  keep_signals  drop_signals

# prefetch is all-or-nothing: add the four controls only when every one is
# supported, so the generated grant never contains a partial, unusable set.
prefetch_supported=1
for name in "${PREFETCH_CONTROLS[@]}"; do
    printf '%s\n' "$supported_controls" | grep -qx -- "$name" || prefetch_supported=0
done
if (( prefetch_supported )); then
    keep_controls+=("${PREFETCH_CONTROLS[@]}")
else
    echo "geopm-gen-access.sh: prefetch is unavailable here (not all four" >&2
    echo "  prefetcher-disable controls are supported), so it is omitted from the" >&2
    echo "  grant.  geopmopt cannot sweep prefetch on this platform." >&2
fi

# A granted control is implicitly readable under the same name, but the signal
# list must still name it for tools that read the current setting explicitly.
for name in "${keep_controls[@]}"; do
    if printf '%s\n' "$supported_signals" | grep -qx -- "$name" \
       && ! printf '%s\n' "${keep_signals[@]}" | grep -qx -- "$name"; then
        keep_signals+=("$name")
    fi
done

if (( ${#keep_controls[@]} == 0 )); then
    echo "geopm-gen-access.sh: none of the requested controls are supported here." >&2
    echo "  This platform cannot be tuned by geopmopt." >&2
    exit 1
fi

signal_file="$OUT_DIR/geopm-access-signals-$GROUP.txt"
control_file="$OUT_DIR/geopm-access-controls-$GROUP.txt"
printf '%s\n' "${keep_signals[@]}"  | sort -u > "$signal_file"
printf '%s\n' "${keep_controls[@]}" | sort -u > "$control_file"

# Validate before an administrator is asked to run anything.  --dry-run checks
# the names against the service without touching configuration, and needs no
# privileges.
validate() {
    local file=$1 kind=$2 err
    if [[ $kind == controls ]]; then
        err=$($GEOPMACCESS --write --dry-run --controls < "$file" 2>&1)
    else
        err=$($GEOPMACCESS --write --dry-run < "$file" 2>&1)
    fi
    local rc=$?
    if (( rc != 0 )); then
        echo "geopm-gen-access.sh: generated ${kind} list failed validation:" >&2
        printf '%s\n' "$err" >&2
        return 1
    fi
    return 0
}

validate "$signal_file" signals   || exit 1
validate "$control_file" controls || exit 1

existing_signals=$($GEOPMACCESS --group "$GROUP" 2>/dev/null)
existing_controls=$($GEOPMACCESS --group "$GROUP" --controls 2>/dev/null)
existing_signal_count=$(printf '%s' "$existing_signals" | grep -c . || true)
existing_control_count=$(printf '%s' "$existing_controls" | grep -c . || true)

cat <<EOF
# ============================================================================
# GEOPM access grant for Unix group: $GROUP
# Generated on $(hostname) at $(date -Is)
#
# REVIEW BEFORE RUNNING.  These commands change what every member of
# '$GROUP' may do to this machine's hardware.  They require root.
#
# Validated with 'geopmaccess --write --dry-run': every name below is
# supported by the service on this host.
# ============================================================================

# Requested and supported:
#   ${#keep_controls[@]} control(s), ${#keep_signals[@]} signal(s)
EOF

if (( ${#drop_controls[@]} )); then
    echo "#"
    echo "# Dropped, not supported on this platform:"
    printf '#   %s\n' "${drop_controls[@]}"
fi
if (( ${#drop_signals[@]} )); then
    (( ${#drop_controls[@]} )) || echo "#"
    printf '#   %s\n' "${drop_signals[@]}"
fi

cat <<EOF

# Group '$GROUP' currently has ${existing_signal_count} signal(s) and \
${existing_control_count} control(s) granted.
EOF

if (( existing_signal_count > 0 || existing_control_count > 0 )); then
    cat <<EOF
#
# WARNING: 'geopmaccess --write' REPLACES a list, it does not add to it.
# Save the current lists first so the grant can be undone exactly:
#
#   geopmaccess --group $GROUP            > $OUT_DIR/backup-signals-$GROUP.txt
#   geopmaccess --group $GROUP --controls > $OUT_DIR/backup-controls-$GROUP.txt
#
# and merge them into the generated files before writing if the existing
# entries are still needed.
EOF
fi

cat <<EOF

# --- Grant -------------------------------------------------------------------

sudo geopmaccess --write --group $GROUP < $signal_file
sudo geopmaccess --write --group $GROUP --controls < $control_file

# --- Verify (run as a member of $GROUP) --------------------------------------

geopmaccess --group $GROUP --controls
./geopm-verify-install.sh --venv ~/geopm-venv

# --- Revoke ------------------------------------------------------------------
EOF

if (( existing_signal_count > 0 || existing_control_count > 0 )); then
    cat <<EOF
# The group already had entries, so removing the list outright would take away
# access that predates this campaign.  Restore the saved backups instead:
#
#   sudo geopmaccess --write --group $GROUP            < $OUT_DIR/backup-signals-$GROUP.txt
#   sudo geopmaccess --write --group $GROUP --controls < $OUT_DIR/backup-controls-$GROUP.txt
EOF
else
    cat <<EOF
# The group had no prior entries, so deleting its lists restores the original
# state exactly.  Note --delete removes an entire list; it cannot drop
# individual names.

sudo geopmaccess --delete --group $GROUP
sudo geopmaccess --delete --group $GROUP --controls
EOF
fi

cat <<EOF

# Membership, if the user is not already in the group:
#
#   sudo usermod -aG $GROUP USERNAME     # user must log out and back in
# ============================================================================
EOF

exit 0
