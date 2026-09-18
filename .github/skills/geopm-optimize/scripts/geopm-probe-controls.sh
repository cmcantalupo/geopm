#!/bin/bash
#  Copyright (c) 2015 - 2026 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#
#  Report which geopmopt sweep dimensions are actually usable on this system
#  and recommend a starting set.  Read-only: queries the platform and writes
#  nothing.

set -uo pipefail

VENV=""
WORKLOAD_KIND="unknown"

print_usage() {
    cat <<'USAGE'
Usage: geopm-probe-controls.sh [OPTION]...

Print the geopmopt sweep dimensions this platform supports, explain why the
others are unavailable, and suggest a starting --sweep set.

Options:
  --venv DIR        Use the GEOPM tools from DIR/bin.  geopmopt ships only in
                    development snapshots, so it usually lives in a virtual
                    environment rather than on the default PATH.
  --workload KIND   Tailor the suggestion.  One of: cpu-bound, memory-bound,
                    power-limited, gpu-bound, unknown (default).
  -h, --help        Print this help message and exit.

Exit status:
  0  at least one dimension is usable
  1  nothing is sweepable on this platform
  2  usage error
USAGE
}

while (( $# )); do
    case "$1" in
        --venv) [[ $# -ge 2 ]] || { echo "--venv requires an argument" >&2; exit 2; }
                VENV="$2"; shift ;;
        --workload) [[ $# -ge 2 ]] || { echo "--workload requires an argument" >&2; exit 2; }
                    WORKLOAD_KIND="$2"; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "geopm-probe-controls.sh: unknown option '$1'" >&2
           print_usage >&2; exit 2 ;;
    esac
    shift
done

if [[ -n $VENV ]]; then
    [[ -x "$VENV/bin/geopmopt" ]] || {
        echo "geopm-probe-controls.sh: no geopmopt in '$VENV/bin'" >&2
        exit 2
    }
    PATH="$VENV/bin:$PATH"
    export PATH
fi

if ! command -v geopmopt >/dev/null 2>&1; then
    cat >&2 <<'MSG'
geopm-probe-controls.sh: geopmopt not found on PATH.

geopmopt is not part of any tagged GEOPM release, so it normally lives in a
virtual environment built from the dev branch.  Pass --venv DIR, or see the
geopm-install skill (references/client-venv.md).
MSG
    exit 2
fi

controls_out=$(geopmopt --list-controls 2>&1)
controls_rc=$?
if (( controls_rc != 0 )); then
    echo "geopm-probe-controls.sh: geopmopt could not list controls." >&2
    printf '%s\n' "$controls_out" | tail -3 >&2
    exit 2
fi

echo "geopmopt sweep dimensions on $(hostname)"
echo "==============================================================="
printf '%s\n' "$controls_out"
echo

# A dimension is usable only when its native domain resolved and its bounds
# are numerically sane.  Unavailable power dimensions still print hardcoded
# default bounds next to an n/a domain, so an n/a check alone would give a
# false positive; a never-tuned uncore control can also auto-detect its max
# bound from the control's current value, which reads 0 on such a host, so a
# numeric max>0 and min<=max check is needed too.  A non-positive step is
# equally unusable: ControlGrid.get_dimension_grid() rejects it outright.  See
# references/sweep-dimensions.md for the uncore-freq max=0 case.
usable=$(printf '%s\n' "$controls_out" \
    | awk 'NR>1 && NF>=6 && $2!="n/a" && $4!="n/a" && $5!="n/a" && $6!="n/a" && ($5+0)>0 && ($4+0)<=($5+0) && ($6+0)>0 {print $1}')
unusable=$(printf '%s\n' "$controls_out" \
    | awk 'NR>1 && NF>=6 && !($2!="n/a" && $4!="n/a" && $5!="n/a" && $6!="n/a" && ($5+0)>0 && ($4+0)<=($5+0) && ($6+0)>0) {print $1}')

# Query the access lists once, up front: they are needed both to validate
# companion controls below and to tell an access-list problem from a hardware
# limitation further down.  A failed query is fatal, as it is in the
# sensitivity and baseline helpers: without it a cpu-freq row cannot be
# checked for its governor, so the probe would recommend a dimension whose
# campaign is guaranteed to fail.
if ! command -v geopmaccess >/dev/null 2>&1; then
    echo "geopm-probe-controls.sh: geopmaccess not found, so the access list cannot" >&2
    echo "  be checked.  A dimension's bounds can look fine while a control geopmopt" >&2
    echo "  writes for it is ungranted, so this probe would recommend a campaign that" >&2
    echo "  fails.  See the geopm-install skill." >&2
    exit 2
fi
if ! supported=$(geopmaccess --all --controls 2>/dev/null) \
   && ! supported=$(/usr/bin/geopmaccess --all --controls 2>/dev/null); then
    echo "geopm-probe-controls.sh: could not query the platform's supported control list." >&2
    echo "  If you are in a virtual environment, rebuild it with --system-site-packages" >&2
    echo "  so that PyGObject is visible; see the geopm-install skill." >&2
    exit 2
fi
if ! granted=$(geopmaccess --controls 2>/dev/null) \
   && ! granted=$(/usr/bin/geopmaccess --controls 2>/dev/null); then
    echo "geopm-probe-controls.sh: could not query your granted control list." >&2
    echo "  If you are in a virtual environment, rebuild it with --system-site-packages" >&2
    echo "  so that PyGObject is visible; see the geopm-install skill." >&2
    exit 2
fi

# geopmopt writes CPU_FREQUENCY_GOVERNOR_CONTROL for every cpu-freq sweep, so a
# cpu-freq row whose governor is missing -- unsupported or merely ungranted --
# cannot be swept at all, however healthy its own bounds look.  Drop it from
# the usable set here so nothing below recommends it and the exit status
# reflects it.  A MIN companion is different: grid.py legitimately sweeps
# MAX-only where the platform has no MIN, so a missing one only costs pinning.
declare -A dim_companion=(
    [cpu-freq]=CPU_FREQUENCY_GOVERNOR_CONTROL
    [uncore-freq]=CPU_UNCORE_FREQUENCY_MIN_CONTROL
    [gpu-freq]=GPU_CORE_FREQUENCY_MIN_CONTROL
)
blocking_companions=""
missing_companions=""
blocked_count=0
for dim in "${!dim_companion[@]}"; do
    # Only dimensions that are otherwise usable: an unavailable row is
    # diagnosed separately below, and describing it as "usable but losing
    # pinning" or as having healthy bounds would contradict that.
    printf '%s\n' "$usable" | grep -qx "$dim" || continue
    companion=${dim_companion[$dim]}
    printf '%s\n' "$granted" | grep -qx "$companion" && continue
    if [[ $companion == CPU_FREQUENCY_GOVERNOR_CONTROL ]]; then
        if printf '%s\n' "$supported" | grep -qx "$companion"; then
            blocking_companions+="  - ${dim} needs ${companion}, which is supported but not granted"$'\n'
        else
            blocking_companions+="  - ${dim} needs ${companion}, which this service does not expose"$'\n'
        fi
        usable=$(printf '%s\n' "$usable" | grep -vx "$dim" || true)
        blocked_count=$(( blocked_count + 1 ))
    elif printf '%s\n' "$supported" | grep -qx "$companion"; then
        missing_companions+="  - ${dim} also needs ${companion}, which is not granted"$'\n'
    fi
done

# prefetch is not one control: every level writes all four members of grid.py's
# _PREFETCHER_CONTROL_SEQUENCE, while --list-controls resolves the row's domain
# from the first alone.  Granting a subset therefore leaves a usable-looking
# row whose campaign fails on the first ungranted bit, so require the set.
PREFETCH_CONTROLS=(
    MSR::MISC_FEATURE_CONTROL:DCU_HW_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:L2_HW_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:DCU_IP_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:L2_ADJACENT_PREFETCHER_DISABLE
)
if printf '%s\n' "$usable" | grep -qx prefetch; then
    prefetch_missing=""
    for pctl in "${PREFETCH_CONTROLS[@]}"; do
        printf '%s\n' "$granted" | grep -qx "$pctl" && continue
        if printf '%s\n' "$supported" | grep -qx "$pctl"; then
            prefetch_missing+="  - prefetch needs ${pctl}, which is supported but not granted"$'\n'
        else
            prefetch_missing+="  - prefetch needs ${pctl}, which this service does not expose"$'\n'
        fi
    done
    if [[ -n $prefetch_missing ]]; then
        blocking_companions+="$prefetch_missing"
        usable=$(printf '%s\n' "$usable" | grep -vx prefetch || true)
        blocked_count=$(( blocked_count + 1 ))
    fi
fi

usable_count=$(printf '%s' "$usable" | grep -c . || true)

echo "Usable dimensions: ${usable_count}"
while IFS= read -r dim; do
    [[ -n $dim ]] && echo "  + ${dim}"
done <<< "$usable"

if [[ -n $unusable ]]; then
    echo
    echo "Unavailable, with the likely reason:"
    while IFS= read -r dim; do
        [[ -z $dim ]] && continue
        case "$dim" in
            gpu-freq|gpu-power)
                reason="no GPU detected by GEOPM, or built without LevelZero/NVML" ;;
            board-power)
                reason="platform exposes no board-level power limit" ;;
            uncore-freq)
                reason="uncore control unavailable, its bounds signals are not granted, or its max resolved to a degenerate 0 (never tuned on this platform)" ;;
            cpu-power)
                reason="RAPL package power limit unavailable, or bounds signals not granted" ;;
            cpu-freq)
                reason="frequency control unavailable, or CPU_FREQUENCY_*_AVAIL not granted" ;;
            prefetch)
                reason="prefetcher MSRs unavailable or not granted" ;;
            *)
                reason="control not implemented on this platform" ;;
        esac
        printf '  - %-14s %s\n' "$dim" "$reason"
    done <<< "$unusable"
fi

if [[ -n $blocking_companions ]]; then
    echo
    echo "NOT sweepable despite healthy bounds: geopmopt writes these controls"
    echo "unconditionally for their dimension -- the governor on every cpu-freq"
    echo "sweep, all four prefetcher bits on every prefetch level -- so the"
    echo "campaign fails outright without them.  Excluded from the usable set above:"
    printf '%s' "$blocking_companions"
    echo "  Ask an administrator; see the geopm-install skill."
fi

if [[ -n $missing_companions ]]; then
    echo
    echo "Usable, but pinning will be lost: a control that geopmopt pairs with"
    echo "these is not granted, so geopmopt drops the companion and silently"
    echo "sweeps a MAX-only cap instead of the pinned setting you expect:"
    printf '%s' "$missing_companions"
    echo "  Ask an administrator; see the geopm-install skill."
fi

if (( usable_count == 0 )); then
    # Four distinct failures reach here.  Only a row with every bound present
    # yet numerically degenerate (e.g. uncore-freq's max=0) is a platform
    # configuration problem; an n/a bound is an availability/access problem and
    # must fall through to the access-list diagnosis below instead.
    bad_bounds=$(printf '%s\n' "$controls_out" \
        | awk 'NR>1 && NF>=6 && $2!="n/a" && $4!="n/a" && $5!="n/a" && $6!="n/a" && !(($5+0)>0 && ($4+0)<=($5+0) && ($6+0)>0) {print $1}')
    bad_bounds_count=$(printf '%s' "$bad_bounds" | grep -c . || true)
    resolved_count=$(printf '%s\n' "$controls_out" | awk 'NR>1 && NF>=6 && $2!="n/a"' | grep -c . || true)
    if (( blocked_count > 0 )); then
        cat <<MSG

Nothing is left to sweep: ${blocked_count} otherwise-usable dimension(s) were
excluded because a control geopmopt writes unconditionally is missing, as
listed above.  This is an access-list or platform-support problem, not a
bounds problem -- granting the named control makes them sweepable again.
MSG
    elif (( bad_bounds_count > 0 )); then
        cat <<MSG

${bad_bounds_count} dimension(s) report a resolved domain and complete bounds
that are nonetheless invalid (max<=0, min>max, or step<=0) -- see the table
above.  That subset is a platform configuration issue (a control that was
never explicitly tuned), not a hardware or access-list limitation.  See
references/sweep-dimensions.md.
MSG
    elif (( resolved_count > 0 )); then
        cat <<MSG

${resolved_count} dimension(s) have a resolved domain, but at least one of
their min/max/step bounds is n/a, so geopmopt has no search space.  The
bounds signals are usually the missing piece -- see the access-list
diagnosis below and the geopm-install skill.
MSG
    else
        cat <<'MSG'

Nothing can be swept on this platform.  Every dimension reports an unresolved
domain, so geopmopt has no search space.  This is normal in a virtual machine,
a container without hardware access, or WSL, none of which expose RAPL or the
frequency controls.  Use a bare-metal host.
MSG
    fi
    # Fall through to the access-list diagnosis rather than exiting here: a
    # withheld grant is the most common cause and naming it is the whole point.
    probe_failed=1
else
    probe_failed=0
fi

# Distinguish an access-list problem from a hardware limitation, since the two
# look identical from --list-controls alone.  The companion checks already ran
# above, where they can still affect the usable set; this only names the
# dimensions whose own primary control is withheld.
if [[ -n $unusable ]]; then
    withheld=""
    for pair in "cpu-freq:CPU_FREQUENCY_MAX_CONTROL" \
                "uncore-freq:CPU_UNCORE_FREQUENCY_MAX_CONTROL" \
                "cpu-power:POWERCAP::CPU_POWER_LIMIT" \
                "gpu-freq:GPU_CORE_FREQUENCY_MAX_CONTROL" \
                "gpu-power:GPU_POWER_LIMIT_CONTROL" \
                "board-power:BOARD_POWER_LIMIT_CONTROL"; do
        dim="${pair%%:*}"; ctl="${pair#*:}"
        printf '%s\n' "$unusable" | grep -qx "$dim" || continue
        if printf '%s\n' "$supported" | grep -qx "$ctl" \
           && ! printf '%s\n' "$granted" | grep -qx "$ctl"; then
            withheld+="  - ${dim} (${ctl})"$'\n'
        fi
    done
    if [[ -n $withheld ]]; then
        echo
        echo "These are supported by the service but NOT granted to you."
        echo "This is an access-list problem, not a hardware limitation:"
        printf '%s' "$withheld"
        echo "  Ask an administrator; see the geopm-install skill."
    fi
fi

(( probe_failed )) && exit 1

echo
echo "Suggested starting point:"

has() { printf '%s\n' "$usable" | grep -qx "$1"; }

suggest=""
case "$WORKLOAD_KIND" in
    cpu-bound)
        has cpu-freq    && suggest+=" --sweep cpu-freq@board"
        has uncore-freq && suggest+=" --sweep uncore-freq@board" ;;
    memory-bound)
        has uncore-freq && suggest+=" --sweep uncore-freq@board"
        has cpu-freq    && suggest+=" --sweep cpu-freq@board" ;;
    power-limited)
        has cpu-power   && suggest+=" --sweep cpu-power@board"
        has cpu-freq    && suggest+=" --sweep cpu-freq@board" ;;
    gpu-bound)
        has gpu-freq    && suggest+=" --sweep gpu-freq@board"
        has gpu-power   && suggest+=" --sweep gpu-power@board" ;;
    *)
        has cpu-freq    && suggest+=" --sweep cpu-freq@board"
        has uncore-freq && suggest+=" --sweep uncore-freq@board" ;;
esac

if [[ -z $suggest ]]; then
    # Fall back to whatever is usable when the workload kind matched nothing.
    # prefetch is deliberately excluded from every default suggestion: the
    # baseline and sensitivity helpers cannot constrain it, so recommending it
    # here would propose a campaign the rest of the workflow cannot support.
    while IFS= read -r dim; do
        [[ -z $dim || $dim == prefetch ]] && continue
        suggest+=" --sweep ${dim}@board"
    done <<< "$usable"
fi

dims=$(printf '%s' "$suggest" | grep -o -- '--sweep' | grep -c . || true)
if (( dims == 0 )); then
    # Reachable when prefetch is the only usable dimension: it is filtered out
    # of every suggestion, so emitting the command template anyway would print
    # a geopmopt invocation with no --sweep at all.
    cat <<'MSG'
  No default dimension is available on this platform.
MSG
    if printf '%s\n' "$usable" | grep -qx prefetch; then
        cat <<'MSG'
  prefetch is usable, but it is not a default dimension: the baseline and
  sensitivity helpers cannot constrain it, so a campaign over it has no
  reference point and no screening.  Sweep it only as a deliberate opt-in
  (--sweep prefetch), and treat its contribution as unverified.
MSG
    fi
    echo "  Otherwise there is nothing to tune here; see the geopm-install skill."
    exit 1
fi

echo "  geopmopt${suggest} \\"
echo "           --trials $(( dims <= 1 ? 20 : dims == 2 ? 40 : 60 )) --verbosity 2 \\"
echo "           -- ./your-workload.sh"
echo
echo "  ${dims} dimension(s).  Budget roughly 20 trials for one dimension,"
echo "  40 for two, 60 or more for three.  Estimate total wall time as"
echo "  trials x single-run time BEFORE starting."

if printf '%s\n' "$usable" | grep -qx prefetch; then
    echo
    echo "  prefetch is available on this platform but is NOT suggested above."
    echo "  geopmopt can sweep it, but geopm-check-workload.sh and"
    echo "  geopm-sensitivity.sh cannot constrain it, so it has no baseline and"
    echo "  no sensitivity screening -- its result could not be judged against a"
    echo "  reference the campaign reproduces.  Add it only deliberately, for a"
    echo "  memory-bound code where freeing prefetch bandwidth is the hypothesis,"
    echo "  and treat its contribution as unverified."
fi

exit 0
