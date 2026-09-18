#!/bin/bash
#  Copyright (c) 2015 - 2026 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#
#  Decide whether this system is ready for a GEOPM tuning campaign.  Every
#  check is read-only unless --write-probe is given.  Exits 0 only when the
#  readiness gate is met, so a caller can branch on the exit status.

set -uo pipefail

VENV=""
WRITE_PROBE=0
QUIET=0

# Controls a tuning campaign may sweep, in the order the report lists them.
# cpu-power is POWERCAP::CPU_POWER_LIMIT, not the similarly named
# CPU_POWER_LIMIT_CONTROL alias: grid.py's cpu-power dimension writes the
# POWERCAP-iogroup control specifically, and the two are different controls
# (different iogroup) despite sharing a description.
CANDIDATE_CONTROLS=(
    CPU_FREQUENCY_MAX_CONTROL
    CPU_UNCORE_FREQUENCY_MAX_CONTROL
    POWERCAP::CPU_POWER_LIMIT
    GPU_CORE_FREQUENCY_MAX_CONTROL
    GPU_POWER_LIMIT_CONTROL
    BOARD_POWER_LIMIT_CONTROL
)

# grid.py's _PREFETCHER_CONTROL_SEQUENCE.  Every prefetch level writes all four,
# so the dimension is ready only when the whole set is granted.
PREFETCH_CONTROLS=(
    MSR::MISC_FEATURE_CONTROL:DCU_HW_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:L2_HW_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:DCU_IP_PREFETCHER_DISABLE
    MSR::MISC_FEATURE_CONTROL:L2_ADJACENT_PREFETCHER_DISABLE
)

# A frequency sweep is meant to pin rather than cap: geopmopt mirrors a *_MAX_*
# setting onto the matching *_MIN_* control, but only when that MIN is in
# pio.control_names() -- the granted list for a service-backed client.  So a
# granted MAX without its MIN does not fail loudly; geopmopt drops the
# companion and silently sweeps a MAX-only cap, which is why this gate has to
# catch it.  cpu-freq's companion is CPU_FREQUENCY_GOVERNOR_CONTROL rather than
# a MIN control: geopmopt forces the governor to 'performance' whenever
# cpu-freq is swept, and that one does fail the campaign outright when missing.
declare -A COMPANION_CONTROLS=(
    [CPU_UNCORE_FREQUENCY_MAX_CONTROL]=CPU_UNCORE_FREQUENCY_MIN_CONTROL
    [GPU_CORE_FREQUENCY_MAX_CONTROL]=GPU_CORE_FREQUENCY_MIN_CONTROL
    [CPU_FREQUENCY_MAX_CONTROL]=CPU_FREQUENCY_GOVERNOR_CONTROL
)

print_usage() {
    cat <<'USAGE'
Usage: geopm-verify-install.sh [OPTION]...

Verify that GEOPM is installed, that the Access Service is reachable, and that
this user may write at least one control that a tuning campaign would sweep.

Options:
  --venv DIR        Use the GEOPM tools from DIR/bin in preference to $PATH.
                    geopmopt ships only in development snapshots, so it usually
                    lives in a virtual environment rather than in /usr/bin.
  --write-probe     Additionally prove writability by writing one control back
                    to the value it already has.  The value is unchanged and
                    the GEOPM session restores it on exit, but this does open a
                    write session, so it is off by default.
  --quiet           Suppress the report and communicate only via exit status.
  -h, --help        Print this help message and exit.

Exit status:
  0  ready: the readiness gate is met
  1  not ready: at least one gate criterion failed
  2  usage error
USAGE
}

while (( $# )); do
    case "$1" in
        --venv) [[ $# -ge 2 ]] || { echo "--venv requires an argument" >&2; exit 2; }
                VENV="$2"; shift ;;
        --write-probe) WRITE_PROBE=1 ;;
        --quiet) QUIET=1 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "geopm-verify-install.sh: unknown option '$1'" >&2
           print_usage >&2; exit 2 ;;
    esac
    shift
done

if [[ -n $VENV ]]; then
    if [[ ! -x "$VENV/bin/geopmread" ]]; then
        echo "geopm-verify-install.sh: no geopmread in '$VENV/bin'" >&2
        exit 2
    fi
    PATH="$VENV/bin:$PATH"
    export PATH
fi

say() { (( QUIET )) || printf '%s\n' "$*"; }

PASS_MARK="  [ok]  "
FAIL_MARK="  [FAIL]"
WARN_MARK="  [warn]"

FAILURES=()
fail() { FAILURES+=("$1"); }

say "GEOPM readiness check: $(hostname)"
say "==============================================================="

## 1. Client tools present

if ! command -v geopmread >/dev/null 2>&1; then
    say "${FAIL_MARK} geopmread not found on PATH"
    fail "GEOPM is not installed, or its virtual environment is not active.
       Install the Access Service, then create a client virtual environment.
       See references/distro-packages.md and references/client-venv.md."
    say
    say "Cannot continue without geopmread."
    exit 1
fi
say "${PASS_MARK} geopmread: $(command -v geopmread)"

geopm_version=$(geopmread --version 2>&1 | head -1)
say "${PASS_MARK} version: ${geopm_version}"

## 2. Access Service reachable

if command -v systemctl >/dev/null 2>&1; then
    geopmd_state=$(systemctl is-active geopm 2>/dev/null)
    [[ -z $geopmd_state ]] && geopmd_state=unknown
    if [[ $geopmd_state == active ]]; then
        say "${PASS_MARK} geopmd is active"
    else
        say "${FAIL_MARK} geopmd is ${geopmd_state}"
        fail "The Access Service is not running.  Ask an administrator to run
       'sudo systemctl start geopm' (and 'enable' it to survive reboot).
       Without it, unprivileged users cannot read signals or write controls."
    fi
fi

## 3. Basic signal read

if geopmread TIME board 0 >/dev/null 2>&1; then
    say "${PASS_MARK} signal read: TIME board 0"
else
    say "${FAIL_MARK} cannot read TIME board 0"
    fail "The most basic signal read failed.  Either geopmd is not running or
       the access list grants this user nothing.  See references/access-lists.md."
fi

## 4. Real telemetry

power_value=$(geopmread CPU_POWER board 0 2>/dev/null)
power_rc=$?
if (( power_rc == 0 )) && [[ -n $power_value ]]; then
    # A board reading of zero or negative Watts indicates a signal that exists
    # but is not actually wired to hardware on this platform.
    if awk -v v="$power_value" 'BEGIN{exit !(v > 0)}' 2>/dev/null; then
        say "${PASS_MARK} telemetry: CPU_POWER board 0 = ${power_value} W"
    else
        say "${FAIL_MARK} CPU_POWER board 0 returned implausible ${power_value}"
        fail "CPU_POWER reads but is not a plausible positive wattage, so energy
       objectives will not work.  The platform may lack RAPL support."
    fi
else
    say "${FAIL_MARK} cannot read CPU_POWER board 0"
    fail "Power telemetry is unavailable, so energy and efficiency objectives
       cannot be used.  Confirm CPU_POWER is in this user's access list and
       that the platform exposes RAPL."
fi

## 5. Controls granted to this user

granted_controls=""
access_ok=0
if command -v geopmaccess >/dev/null 2>&1; then
    if granted_controls=$(geopmaccess --controls 2>/dev/null); then
        access_ok=1
    else
        # A virtual environment built without --system-site-packages cannot
        # import PyGObject, which dasbus needs, so geopmaccess fails there even
        # though the access list itself is fine.  Falling back to the system
        # copy is the expected arrangement, not a misconfiguration: geopmaccess
        # only queries the daemon and need not match the client tool version.
        if [[ -x /usr/bin/geopmaccess ]] && granted_controls=$(/usr/bin/geopmaccess --controls 2>/dev/null); then
            access_ok=1
            say "${PASS_MARK} access list via /usr/bin/geopmaccess (expected inside a venv)"
        fi
    fi
fi

if (( ! access_ok )); then
    say "${FAIL_MARK} cannot query the access list"
    fail "geopmaccess could not run, so granted controls are unknown.  If you are
       using a virtual environment, rebuild it with --system-site-packages so
       that PyGObject is visible.  See references/client-venv.md."
fi

# Needed both to size the companion check below (a MIN control that does not
# exist on this platform at all is not required, per grid.py) and to name
# controls when nothing is writable.  A failed query is a gate failure, not an
# empty platform: treating it as empty would silently classify every missing
# MIN as unsupported and report READY without having verified the requirement.
supported_controls=""
if (( access_ok )) \
   && ! supported_controls=$(geopmaccess --all --controls 2>/dev/null) \
   && ! supported_controls=$(/usr/bin/geopmaccess --all --controls 2>/dev/null); then
    access_ok=0
    say "${FAIL_MARK} cannot query the platform's supported control list"
    fail "geopmaccess --all --controls could not run, so a companion control that is
       missing cannot be told apart from one this platform does not have.  The
       readiness gate cannot be verified.  See references/client-venv.md."
fi

writable=()
complete=(); incomplete=()
for control in "${CANDIDATE_CONTROLS[@]}"; do
    if printf '%s\n' "$granted_controls" | grep -qx "$control"; then
        writable+=("$control")
    fi
done

# prefetch is a set rather than a candidate control, but a machine whose only
# sweepable dimension is prefetch can still run a campaign, so track it
# separately rather than failing before the dimension check in section 6.
prefetch_granted=1
for pctl in "${PREFETCH_CONTROLS[@]}"; do
    printf '%s\n' "$granted_controls" | grep -qx "$pctl" || prefetch_granted=0
done

if (( ${#writable[@]} || prefetch_granted )); then
    if (( ${#writable[@]} )); then
        say "${PASS_MARK} writable controls: ${#writable[@]} of ${#CANDIDATE_CONTROLS[@]} candidates"
        for control in "${writable[@]}"; do
            say "           - ${control}"
        done
    fi
    (( prefetch_granted )) && say "${PASS_MARK} all ${#PREFETCH_CONTROLS[@]} prefetcher-disable controls granted (prefetch)"
    # Nothing downstream reports a missing MIN companion: grid.py drops it and
    # the campaign silently sweeps a MAX-only cap, so this gate is the only
    # place it surfaces.  A MIN the platform does not expose at all is not
    # required (geopmopt sweeps MAX-only there by design); the governor
    # companion has no such exception -- geopmopt writes it unconditionally
    # for every cpu_frequency dimension and the campaign fails outright.
    # The verdict is deferred to section 6: a control can be companion-complete
    # while its --list-controls bounds are n/a, and vice versa, so readiness is
    # the intersection of the two rather than either alone.
    for control in "${writable[@]}"; do
        companion=${COMPANION_CONTROLS[$control]:-}
        if [[ -z $companion ]]; then
            complete+=("$control")
            continue
        fi
        if [[ $companion != CPU_FREQUENCY_GOVERNOR_CONTROL ]] \
           && ! printf '%s\n' "$supported_controls" | grep -qx "$companion"; then
            complete+=("$control")
            continue
        fi
        if printf '%s\n' "$granted_controls" | grep -qx "$companion"; then
            complete+=("$control")
        else
            incomplete+=("$control")
            say "${WARN_MARK} ${control} is granted but ${companion} is not"
            if [[ $companion == CPU_FREQUENCY_GOVERNOR_CONTROL ]]; then
                say "           sweeping it fails outright; geopmopt writes ${companion}"
                say "           for every cpu-freq sweep.  Ask for it alongside ${control}."
            else
                say "           sweeping it is supposed to pin ${control} by also writing"
                say "           ${companion}.  Without that grant geopmopt drops the"
                say "           companion and silently sweeps a MAX-only cap -- no error,"
                say "           but weaker constraints than intended."
            fi
        fi
    done
    # prefetch has no companion of its own -- the complete four-control set IS
    # the requirement -- so count it here, or a prefetch-only install records a
    # permanent failure while section 6 simultaneously calls it ready.
    (( prefetch_granted )) && complete+=("prefetch")
    if (( ${#complete[@]} == 0 )); then
        fail "Every granted control is missing a companion geopmopt needs:
       $(printf '%s ' "${incomplete[@]}")
       No dimension can be swept as intended.  Generate the exact grant
       commands with scripts/geopm-gen-access.sh, or see
       references/access-lists.md."
    elif (( ${#incomplete[@]} )); then
        say "${PASS_MARK} companion-complete controls: ${#complete[@]} (${#incomplete[@]} incomplete, see warnings)"
    fi
elif (( access_ok )); then
    say "${FAIL_MARK} no sweepable control is granted to this user"
    # Name the controls, and separate a platform limitation from an access
    # problem: "not supported here" and "not granted to you" need different
    # people to fix them.
    ungranted=(); unsupported=()
    for control in "${CANDIDATE_CONTROLS[@]}"; do
        if printf '%s\n' "$supported_controls" | grep -qx "$control"; then
            ungranted+=("$control")
        else
            unsupported+=("$control")
        fi
    done
    for control in "${ungranted[@]}"; do
        say "           - ${control}: supported here, NOT granted to you"
    done
    for control in "${unsupported[@]}"; do
        say "           - ${control}: not supported on this platform"
    done
    if (( ${#ungranted[@]} )); then
        fail "These controls exist on this system but are not in your access list:
       $(printf '%s ' "${ungranted[@]}")
       An administrator must grant at least one.  Generate the exact commands
       with scripts/geopm-gen-access.sh, or see references/access-lists.md."
    else
        fail "None of the controls a campaign would sweep exist on this platform.
       This is a hardware or build limitation, not an access-list problem, and
       no administrator can grant them.  Typical of a virtual machine, a
       container without hardware access, or WSL.  Use a bare-metal host."
    fi
fi

## 6. geopmopt available and usable

# geopmopt is absent from every tagged release to date; it ships only in
# development snapshots, so a virtual environment is the expected home for it.
if ! command -v geopmopt >/dev/null 2>&1; then
    say "${FAIL_MARK} geopmopt not found on PATH"
    fail "geopmopt is not installed.  It is not part of a tagged GEOPM release,
       so install a development snapshot into a virtual environment:
       see references/client-venv.md.  Pass --venv DIR to check that
       environment with this script."
else
    opt_out=$(geopmopt --list-controls 2>&1)
    opt_rc=$?
    if (( opt_rc != 0 )); then
        say "${FAIL_MARK} geopmopt cannot run"
        if [[ $opt_out == *'scikit-optimize is required'* ]]; then
            fail "geopmopt is installed but scikit-optimize is missing.  Do not add
       it to the system Python; build a virtual environment from the dev
       branch instead.  See references/client-venv.md."
        else
            fail "geopmopt exited ${opt_rc}.  First line of the error was:
       $(printf '%s\n' "$opt_out" | tail -1)"
        fi
    else
        say "${PASS_MARK} geopmopt: $(command -v geopmopt)"
        # A dimension is usable only when the platform resolved a native domain
        # and reported real, numerically sane bounds.  Bounds alone are not
        # enough: unavailable power dimensions still print hardcoded defaults
        # next to an n/a domain, and a never-tuned uncore control can
        # auto-detect its max bound from the control's current value, which
        # reads 0 on such a host.  A non-positive step is equally unusable:
        # ControlGrid.get_dimension_grid() rejects it outright.  See
        # references/sweep-dimensions.md.
        usable=$(printf '%s\n' "$opt_out" | awk 'NR>1 && NF>=6 && $2!="n/a" && $4!="n/a" && $5!="n/a" && $6!="n/a" && ($5+0)>0 && ($4+0)<=($5+0) && ($6+0)>0 {print $1}')
        usable_count=$(printf '%s' "$usable" | grep -c . || true)
        if (( usable_count > 0 )); then
            say "${PASS_MARK} sweepable dimensions: ${usable_count}"
            while IFS= read -r dim; do
                [[ -n $dim ]] && say "           - ${dim}"
            done <<< "$usable"
            # Readiness is the intersection: a control can be
            # companion-complete while its bounds are n/a, and a dimension can
            # have healthy bounds while its companion is ungranted.  Either
            # alone would report READY for a campaign that cannot run.
            declare -A dim_control=(
                [cpu-freq]=CPU_FREQUENCY_MAX_CONTROL
                [uncore-freq]=CPU_UNCORE_FREQUENCY_MAX_CONTROL
                [cpu-power]=POWERCAP::CPU_POWER_LIMIT
                [gpu-freq]=GPU_CORE_FREQUENCY_MAX_CONTROL
                [gpu-power]=GPU_POWER_LIMIT_CONTROL
                [board-power]=BOARD_POWER_LIMIT_CONTROL
            )
            ready_dims=()
            while IFS= read -r dim; do
                [[ -z $dim ]] && continue
                if [[ $dim == prefetch ]]; then
                    (( prefetch_granted )) && ready_dims+=("$dim")
                    continue
                fi
                control=${dim_control[$dim]:-}
                [[ -z $control ]] && continue
                for candidate in ${complete[@]+"${complete[@]}"}; do
                    if [[ $candidate == "$control" ]]; then
                        ready_dims+=("$dim")
                        break
                    fi
                done
            done <<< "$usable"
            if (( ${#ready_dims[@]} )); then
                say "${PASS_MARK} ready to sweep: $(printf '%s ' "${ready_dims[@]}")"
            else
                say "${FAIL_MARK} no dimension is both usable and fully granted"
                fail "Some dimensions have usable bounds and some controls have all their
       companions granted, but no single dimension has both, so no campaign
       can run as intended.  Compare the sweepable dimensions listed above
       against the companion warnings, and generate the missing grants with
       scripts/geopm-gen-access.sh."
            fi
        else
            say "${FAIL_MARK} no sweep dimension has usable bounds"
            # Three distinct failures reach here.  Only a row with every bound
            # present yet numerically degenerate (e.g. uncore-freq's max=0) is
            # a platform configuration problem; an n/a bound is usually a
            # missing bounds-signal grant, which an administrator can fix.
            bad_bounds_count=$(printf '%s\n' "$opt_out" \
                | awk 'NR>1 && NF>=6 && $2!="n/a" && $4!="n/a" && $5!="n/a" && $6!="n/a" && !(($5+0)>0 && ($4+0)<=($5+0) && ($6+0)>0)' | grep -c . || true)
            resolved_count=$(printf '%s\n' "$opt_out" | awk 'NR>1 && NF>=6 && $2!="n/a"' | grep -c . || true)
            if (( bad_bounds_count > 0 )); then
                fail "geopmopt runs and ${bad_bounds_count} dimension(s) report complete but
       invalid bounds (max<=0, min>max, or step<=0) -- see --list-controls.
       That subset is a platform configuration issue (a control that was
       never explicitly tuned), not a hardware or access-list limitation.
       See references/sweep-dimensions.md."
            elif (( resolved_count > 0 )); then
                fail "geopmopt runs and ${resolved_count} dimension(s) have a resolved domain,
       but at least one of their min/max/step bounds is n/a, so there is
       nothing to search.  The bounds signals are usually the missing piece
       (cpu-freq needs CPU_FREQUENCY_MIN_AVAIL, CPU_FREQUENCY_STICKER -- which
       grid.py uses as the default maximum, not CPU_FREQUENCY_MAX_AVAIL -- and
       CPU_FREQUENCY_STEP); an administrator can grant them.  See
       references/access-lists.md."
            else
                fail "geopmopt runs but every dimension reports n/a bounds, so there is
       nothing to search.  The platform may not expose the frequency and
       power limits GEOPM needs."
            fi
        fi
    fi
fi

## 7. Optional write probe

if (( WRITE_PROBE )); then
    # A prefetch-only install has nothing in writable, but the set is granted
    # and the gate can pass on it, so probe one of its controls rather than
    # skipping the write and still reporting READY.
    probe_control=""
    if (( ${#writable[@]} )); then
        probe_control="${writable[0]}"
    elif (( prefetch_granted )); then
        probe_control="${PREFETCH_CONTROLS[0]}"
    fi
    if [[ -z $probe_control ]]; then
        say "${WARN_MARK} skipping write probe: no candidate control is granted"
    else
        # --control-domain is a geopmwrite option; geopmread spells it
        # --signal-domain and would reject the query.
        probe_domain=$(geopmwrite --control-domain "$probe_control" 2>/dev/null)
        probe_domain=${probe_domain:-board}
        current=$(geopmread "$probe_control" "$probe_domain" 0 2>/dev/null)
        if [[ -z $current ]]; then
            say "${WARN_MARK} write probe: cannot read current ${probe_control}"
        elif geopmwrite "$probe_control" "$probe_domain" 0 "$current" >/dev/null 2>&1; then
            say "${PASS_MARK} write probe: ${probe_control} rewritten to its current ${current}"
        else
            say "${FAIL_MARK} write probe: writing ${probe_control} was denied"
            fail "Writing ${probe_control} failed even though it appears in the access
       list.  Check that geopmd is running and that the list was applied."
        fi
    fi
fi

## Verdict

say
if (( ${#FAILURES[@]} == 0 )); then
    say "READY.  The readiness gate is met:"
    say "  - geopmopt lists at least one dimension with real bounds"
    say "  - geopmread returns a plausible power reading"
    say "  - at least one sweepable control is writable by this user"
    say
    say "Proceed to the geopm-optimize assistant."
    exit 0
fi

say "NOT READY.  ${#FAILURES[@]} issue(s) must be resolved:"
say
for issue in "${FAILURES[@]}"; do
    say "  * ${issue}"
    say
done
exit 1
