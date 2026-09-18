#!/bin/bash
#  Copyright (c) 2015 - 2026 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#
#  Run a workload once at default settings to establish a baseline before a
#  tuning campaign: how long it takes, whether it succeeds, and whether the
#  proposed metric regex matches its output.  Changes no hardware settings
#  unless --dimension is given.

set -uo pipefail

REGEX=""
BASELINE_RUNS=1
KEEP_OUTPUT=""
VENV=""
DIMENSIONS=()

# Campaigns are run as --sweep DIM@board, so the baseline applies its settings
# and resolves its bounds at the same domain.
BASELINE_DOMAIN="board"

print_usage() {
    cat <<'USAGE'
Usage: geopm-check-workload.sh [OPTION]... -- COMMAND [ARG]...

Run COMMAND at default hardware settings and report what a geopmopt campaign
needs to know: exit status, wall time, a recommended --application-timeout,
and whether --metric-regex would match.

Options:
  --regex PATTERN   Candidate --metric-regex.  Must contain one capturing
                    group.  Reported but not required.
  --runs N          Repeat N times to gauge run-to-run variation (default 1).
                    Two or three runs are enough to spot a noisy workload.
  --save-output FILE  Keep the last run's stdout for regex development.
  --dimension DIM   Measure under the same conditions a geopmopt campaign
                    sweeping DIM would actually use, instead of the
                    unconstrained default settings.  For cpu-freq/
                    cpu-frequency this forces the performance governor and
                    caps the frequency at the sticker, mirroring geopmopt and
                    geopm-sensitivity.sh exactly, so this baseline is a valid
                    reference point for judging that campaign's results
                    instead of comparing against faster, unconstrained
                    turbo-range numbers the campaign can never reach.
                    REPEATABLE.  A campaign sweeping several dimensions
                    constrains all of them on every trial, so pass every
                    dimension the campaign will sweep to get one combined
                    baseline.  Baselining them one at a time leaves the other
                    controls unconstrained, and no such run is a reference the
                    campaign can reproduce.
                    An optional =REF or =MIN:MAX:STEP suffix sets the reference
                    setting explicitly (raw units, no GHz/W suffix), for when
                    the campaign overrides the default range with its own
                    --sweep DIM=MIN:MAX:STEP; the baseline then caps at that
                    range's MAX instead of the auto-detected default, so it
                    stays inside the campaign's search space.
                    prefetch/prefetch-disable is NOT supported here: geopmopt
                    expands it into four ordered MSR prefetcher-disable
                    controls rather than one value.  This helper leaves the
                    prefetchers untouched, so a baseline taken with it does
                    not constrain them.
                    Requires geopmopt/geopmsession/geopmread on PATH.  See
                    --list-controls for available dimension names.
  --venv DIR        Use GEOPM tools from DIR/bin (only meaningful with
                    --dimension).
  -h, --help        Print this help message and exit.

No hardware settings are changed and no GEOPM session is opened, unless
--dimension is given.

Exit status:
  0  the workload ran and, if a regex was given, it matched
  1  the workload failed, or the regex did not match
  2  usage error
USAGE
}

while (( $# )); do
    case "$1" in
        --regex) [[ $# -ge 2 ]] || { echo "--regex requires an argument" >&2; exit 2; }
                 REGEX="$2"; shift ;;
        --runs) [[ $# -ge 2 ]] || { echo "--runs requires an argument" >&2; exit 2; }
                BASELINE_RUNS="$2"; shift ;;
        --save-output) [[ $# -ge 2 ]] || { echo "--save-output requires an argument" >&2; exit 2; }
                       KEEP_OUTPUT="$2"; shift ;;
        --dimension) [[ $# -ge 2 ]] || { echo "--dimension requires an argument" >&2; exit 2; }
                     DIMENSIONS+=("$2"); shift ;;
        --venv) [[ $# -ge 2 ]] || { echo "--venv requires an argument" >&2; exit 2; }
                VENV="$2"; shift ;;
        --) shift; break ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "geopm-check-workload.sh: unknown option '$1'" >&2
           print_usage >&2; exit 2 ;;
    esac
    shift
done

if (( $# == 0 )); then
    echo "geopm-check-workload.sh: no command given after --" >&2
    print_usage >&2
    exit 2
fi

if ! [[ $BASELINE_RUNS =~ ^[0-9]+$ ]] || (( BASELINE_RUNS < 1 )); then
    echo "geopm-check-workload.sh: --runs must be a positive integer" >&2
    exit 2
fi

if [[ -n $REGEX ]]; then
    # Distinguish a missing interpreter from a bad pattern: reporting "invalid
    # regex" for an absent python3 sends the user looking in the wrong place.
    if ! command -v python3 >/dev/null 2>&1; then
        echo "geopm-check-workload.sh: python3 is required to match --regex," >&2
        echo "  because geopmopt uses Python regular expression syntax." >&2
        echo "  Install python3, or omit --regex to time the workload only." >&2
        exit 2
    fi
    if ! python3 -c "
import re, sys
p = re.compile(sys.argv[1])
sys.exit(0 if p.groups == 1 else 1)
" "$REGEX" 2>/dev/null; then
        echo "geopm-check-workload.sh: --regex must be valid and have exactly one" >&2
        echo "  capturing group.  Example: 'GFLOPS: ([0-9.]+)'" >&2
        exit 2
    fi
fi

# --dimension mirrors geopm-sensitivity.sh's condition-matching so this
# baseline is a valid reference point for the campaign it precedes, rather
# than a faster, unconstrained number the campaign can never reach.  Every
# dimension given is applied together, because a campaign sweeping several
# constrains all of them on every trial.
GOVERNOR_LINE=""
sig_conf=""
ctl_conf=""
CTL_LINES=()
DIM_SUMMARY=()
if (( ${#DIMENSIONS[@]} )); then
    if [[ -n $VENV ]]; then
        [[ -x "$VENV/bin/geopmopt" ]] || { echo "geopm-check-workload.sh: no geopmopt in '$VENV/bin'" >&2; exit 2; }
        PATH="$VENV/bin:$PATH"; export PATH
    fi
    for tool in geopmopt geopmsession geopmread; do
        command -v "$tool" >/dev/null 2>&1 || {
            echo "geopm-check-workload.sh: $tool not found on PATH.  --dimension requires GEOPM; see the geopm-install skill." >&2
            exit 2
        }
    done

    controls=$(geopmopt --list-controls 2>&1) || {
        echo "geopm-check-workload.sh: could not list controls." >&2
        exit 2
    }

    # Writability is decided by the granted *control* list, not by whether a
    # same-named signal is readable: GEOPM grants signals and controls
    # separately, so geopmread would both accept a readable-but-unwritable
    # control and reject a writable one whose signal alias was never granted.
    # An unreadable list is fatal rather than empty: an empty one would drop
    # MIN companions silently and misreport the governor as ungranted.
    if ! granted_controls=$(geopmaccess --controls 2>/dev/null) \
       && ! granted_controls=$(/usr/bin/geopmaccess --controls 2>/dev/null); then
        echo "geopm-check-workload.sh: could not query the access list with geopmaccess." >&2
        echo "  --dimension needs it to decide which controls geopmopt would write, so" >&2
        echo "  this baseline cannot be shown to mirror campaign conditions.  If you are" >&2
        echo "  in a virtual environment, rebuild it with --system-site-packages so that" >&2
        echo "  PyGObject is visible; see the geopm-install skill." >&2
        exit 2
    fi
    # Distinguishes "supported but not granted" from "unsupported" below.
    if ! supported_controls=$(geopmaccess --all --controls 2>/dev/null) \
       && ! supported_controls=$(/usr/bin/geopmaccess --all --controls 2>/dev/null); then
        echo "geopm-check-workload.sh: could not query the platform's supported control list." >&2
        echo "  See the geopm-install skill." >&2
        exit 2
    fi

    # A campaign is run as --sweep DIM@board, and ControlGrid resolves a sweep's
    # bounds by reading the bound signals at the *requested* domain (grid.py
    # _get_range).  --list-controls prints NATIVE-domain bounds, which differ for
    # a sum-aggregated control: CPU_POWER_LIMIT_DEFAULT reads one package's limit
    # at package and the board sum at board.  Read them at board so the baseline
    # applies the same reference the campaign resolves.  Mirrors grid.py's
    # _CLI_FLAG_TO_CONTROL bound table.
    read_bound() {
        local signal=$1 fallback=${2:-} value
        if value=$(geopmread "$signal" "$BASELINE_DOMAIN" 0 2>/dev/null) && [[ -n $value ]]; then
            printf '%s' "$value"; return 0
        fi
        [[ -n $fallback ]] && { printf '%s' "$fallback"; return 0; }
        return 1
    }

    seen_dims=""
    for raw_dim in "${DIMENSIONS[@]}"; do
        # An optional =REF or =MIN:MAX:STEP suffix pins the reference to the
        # campaign's actual range instead of the auto-detected default.
        ref_override=""
        DIMENSION="$raw_dim"
        if [[ $raw_dim == *=* ]]; then
            DIMENSION="${raw_dim%%=*}"
            ref_override="${raw_dim#*=}"
            # MIN:MAX:STEP -> the baseline caps at MAX, the top of the sweep.
            [[ $ref_override == *:* ]] && ref_override=$(printf '%s' "$ref_override" | cut -d: -f2)
            if ! awk -v v="$ref_override" 'BEGIN{exit !(v+0==v && v+0>0)}' 2>/dev/null; then
                echo "geopm-check-workload.sh: '$raw_dim' reference must be a positive number" >&2
                echo "  in raw units (no GHz/W suffix); MIN:MAX:STEP is also accepted." >&2
                exit 2
            fi
        fi
        # --list-controls always keys its table by the short alias (grid.py's
        # _PREFERRED_ALIAS), even though --sweep also accepts these long dashed
        # spellings (_CONTROL_ALIASES).  Normalize before the lookup below, or a
        # long spelling never matches a row and is rejected as unusable.
        case "$DIMENSION" in
            cpu-frequency)        DIMENSION=cpu-freq ;;
            cpu-uncore-frequency) DIMENSION=uncore-freq ;;
            gpu-frequency)        DIMENSION=gpu-freq ;;
            prefetch-disable)     DIMENSION=prefetch ;;
        esac

        # prefetch is a level, not a value: grid.py expands it into four ordered
        # MSR writes (prefetch_settings()), so it has no single control to cap
        # here.  It is also not a default sweep dimension -- see
        # references/sweep-dimensions.md.
        if [[ $DIMENSION == prefetch ]]; then
            echo "geopm-check-workload.sh: '$DIMENSION' is not supported by --dimension." >&2
            echo "  geopmopt expands it into four ordered MSR prefetcher-disable controls" >&2
            echo "  (grid.py's prefetch_settings()), which this helper does not write." >&2
            echo "  prefetch is not a default sweep dimension; if you are sweeping it" >&2
            echo "  deliberately, this baseline cannot constrain it and its contribution" >&2
            echo "  to any improvement is unverified." >&2
            exit 2
        fi

        if printf '%s\n' "$seen_dims" | grep -qx "$DIMENSION"; then
            echo "geopm-check-workload.sh: '$DIMENSION' given more than once." >&2
            exit 2
        fi
        seen_dims+="${DIMENSION}"$'\n'

        read -r ctl_domain < <(
            printf '%s\n' "$controls" | awk -v d="$DIMENSION" 'NR>1 && $1==d {print $2}')
        if [[ -z ${ctl_domain:-} || $ctl_domain == n/a ]]; then
            echo "geopm-check-workload.sh: '$DIMENSION' is not usable on this platform" >&2
            echo "  (its native domain did not resolve).  See --list-controls." >&2
            exit 2
        fi

        case "$DIMENSION" in
            cpu-freq)
                CONTROL=CPU_FREQUENCY_MAX_CONTROL
                ctl_min=$(read_bound CPU_FREQUENCY_MIN_AVAIL)
                ctl_max=$(read_bound CPU_FREQUENCY_STICKER)
                ctl_step=$(read_bound CPU_FREQUENCY_STEP) ;;
            uncore-freq)
                CONTROL=CPU_UNCORE_FREQUENCY_MAX_CONTROL
                ctl_min=$(read_bound CPU_FREQUENCY_MIN_AVAIL)
                ctl_max=$(read_bound CPU_UNCORE_FREQUENCY_MAX_CONTROL)
                ctl_step=$(read_bound CPU_FREQUENCY_STEP) ;;
            cpu-power)
                CONTROL=POWERCAP::CPU_POWER_LIMIT
                ctl_min=$(read_bound CPU_POWER_MIN_AVAIL)
                ctl_max=$(read_bound CPU_POWER_LIMIT_DEFAULT)
                ctl_step=1 ;;
            gpu-freq)
                CONTROL=GPU_CORE_FREQUENCY_MAX_CONTROL
                ctl_min=$(read_bound GPU_CORE_FREQUENCY_MIN_AVAIL)
                ctl_max=$(read_bound GPU_CORE_FREQUENCY_MAX_AVAIL)
                ctl_step=$(read_bound GPU_CORE_FREQUENCY_STEP) ;;
            gpu-power)
                CONTROL=GPU_POWER_LIMIT_CONTROL
                ctl_min=$(read_bound LEVELZERO::GPU_POWER_LIMIT_MIN_AVAIL 200)
                ctl_max=$(read_bound LEVELZERO::GPU_POWER_LIMIT_DEFAULT)
                [[ -z ${ctl_max:-} ]] && ctl_max=$(read_bound GPU_POWER_LIMIT_CONTROL)
                ctl_step=1 ;;
            board-power)
                CONTROL=BOARD_POWER_LIMIT_CONTROL
                ctl_min=200; ctl_max=6000; ctl_step=1 ;;
            *) echo "geopm-check-workload.sh: no control mapping for '$DIMENSION'." >&2
               echo "  Supported: cpu-freq, uncore-freq, cpu-power, gpu-freq, gpu-power, board-power" >&2
               exit 2 ;;
        esac

        if [[ -z ${ctl_min:-} || -z ${ctl_max:-} || -z ${ctl_step:-} ]]; then
            echo "geopm-check-workload.sh: could not resolve '$DIMENSION' bounds at ${BASELINE_DOMAIN}." >&2
            echo "  The bounds signals are probably not granted; see the geopm-install skill." >&2
            exit 2
        fi
        # A never-tuned uncore control resolves its max from the control's
        # *current* value, which reads 0 on such a host.  ControlGrid also
        # rejects a non-positive step outright.
        if ! awk -v mn="$ctl_min" -v mx="$ctl_max" -v st="$ctl_step" \
                'BEGIN{exit !(mx > 0 && mn <= mx && st > 0)}' 2>/dev/null; then
            echo "geopm-check-workload.sh: '$DIMENSION' has an invalid grid at ${BASELINE_DOMAIN}" >&2
            echo "  (min=${ctl_min} max=${ctl_max} step=${ctl_step}): needs max>0, min<=max, step>0." >&2
            echo "  See references/sweep-dimensions.md for the uncore-freq max=0 case." >&2
            exit 2
        fi

        ref=$ctl_max
        if [[ $DIMENSION == cpu-freq ]]; then
            # geopmopt writes this unconditionally for every cpu-freq sweep, so
            # skipping it would baseline under the current governor instead.
            if printf '%s\n' "$granted_controls" | grep -qx CPU_FREQUENCY_GOVERNOR_CONTROL; then
                GOVERNOR_LINE="CPU_FREQUENCY_GOVERNOR_CONTROL ${BASELINE_DOMAIN} 0 0"
            elif printf '%s\n' "$supported_controls" | grep -qx CPU_FREQUENCY_GOVERNOR_CONTROL; then
                echo "geopm-check-workload.sh: CPU_FREQUENCY_GOVERNOR_CONTROL is supported but not" >&2
                echo "  granted to you.  geopmopt writes it for every cpu-freq sweep, so this" >&2
                echo "  baseline would run under your current governor while the campaign runs" >&2
                echo "  under 'performance'.  Grant it first; see the geopm-install skill" >&2
                echo "  (references/access-lists.md)." >&2
                exit 2
            else
                echo "geopm-check-workload.sh: CPU_FREQUENCY_GOVERNOR_CONTROL is not exposed by" >&2
                echo "  this platform, so geopmopt cannot force the performance governor and" >&2
                echo "  cpu-freq cannot be swept as the campaign would.  Choose another dimension." >&2
                exit 2
            fi
        fi

        # An explicit campaign range overrides the auto-detected reference, but
        # must still be a real setting on this platform.
        if [[ -n $ref_override ]]; then
            if awk -v r="$ref_override" -v mn="$ctl_min" 'BEGIN{exit !(r < mn)}' 2>/dev/null; then
                echo "geopm-check-workload.sh: '$DIMENSION' reference ${ref_override} is below the" >&2
                echo "  platform minimum ${ctl_min}, so no campaign could use it.  See --list-controls." >&2
                exit 2
            fi
            ref=$ref_override
        fi

        CTL_LINES+=("$(printf '%s %s 0 %s' "$CONTROL" "$BASELINE_DOMAIN" "$ref")")
        if [[ $CONTROL == *_MAX_CONTROL ]]; then
            min_control=${CONTROL/_MAX_/_MIN_}
            if [[ $min_control != "$CONTROL" && $min_control != CPU_FREQUENCY_MIN_CONTROL ]]; then
                # grid.py pairs this MIN only when the platform exposes it.  If
                # it does but the grant is missing, geopmopt would silently
                # sweep a MAX-only cap; the probe, verifier and sensitivity
                # helper all reject that, so fail here too rather than measure a
                # baseline that claims to mirror a campaign it does not.  A MIN
                # the platform does not expose at all is a legitimate MAX-only
                # sweep, so it is omitted without error.
                if printf '%s\n' "$granted_controls" | grep -qx "$min_control"; then
                    CTL_LINES+=("$(printf '%s %s 0 %s' "$min_control" "$BASELINE_DOMAIN" "$ref")")
                elif printf '%s\n' "$supported_controls" | grep -qx "$min_control"; then
                    echo "geopm-check-workload.sh: ${min_control} is supported but not granted to you." >&2
                    echo "  geopmopt pins it alongside ${CONTROL} for ${DIMENSION}; without the grant" >&2
                    echo "  the campaign silently sweeps a MAX-only cap, so this baseline would not" >&2
                    echo "  mirror it.  Grant it first; see the geopm-install skill." >&2
                    exit 2
                fi
            fi
        fi
        DIM_SUMMARY+=("${DIMENSION} (${CONTROL}) at ${ref} on ${BASELINE_DOMAIN}")
    done

    sig_conf=$(mktemp) || exit 1
    ctl_conf=$(mktemp) || exit 1
    printf 'TIME board 0\n' > "$sig_conf"
    {
        # One governor line regardless of how many dimensions asked for it.
        [[ -n $GOVERNOR_LINE ]] && printf '%s\n' "$GOVERNOR_LINE"
        printf '%s\n' "${CTL_LINES[@]}"
    } > "$ctl_conf"
fi

echo "Workload baseline check"
echo "==============================================================="
echo "  Command : $*"
[[ -n $REGEX ]] && echo "  Regex   : $REGEX"
echo "  Runs    : $BASELINE_RUNS"
if (( ${#DIMENSIONS[@]} )); then
    for entry in "${DIM_SUMMARY[@]}"; do
        echo "  Dimension : ${entry}"
    done
    [[ -n $GOVERNOR_LINE ]] && echo "  Governor  : performance (forced, mirrors geopmopt)"
    if (( ${#DIM_SUMMARY[@]} > 1 )); then
        echo "  Note      : all ${#DIM_SUMMARY[@]} dimensions are constrained together, the way a"
        echo "              campaign that swept them jointly would apply them on every"
        echo "              trial -- see sweep-dimensions.md"
    else
        echo "  Note      : this baseline reflects campaign conditions, not"
        echo "              unconstrained defaults -- see sweep-dimensions.md"
    fi
fi
echo

stdout_file=$(mktemp) || exit 1
times_file=$(mktemp) || exit 1
values_file=$(mktemp) || exit 1
trap 'rm -f "$stdout_file" "$times_file" "$values_file" "$sig_conf" "$ctl_conf"' EXIT

failures=0
for (( run = 1; run <= BASELINE_RUNS; run++ )); do
    start=$(date +%s.%N)
    if (( ${#DIMENSIONS[@]} )); then
        geopmsession -i "$sig_conf" --control-config "$ctl_conf" -o /dev/null \
            -- "$@" > "$stdout_file" 2>&1
    else
        "$@" > "$stdout_file" 2>&1
    fi
    rc=$?
    end=$(date +%s.%N)
    elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", e - s}')
    echo "$elapsed" >> "$times_file"

    if (( rc != 0 )); then
        printf '  run %d: FAILED, exit %d after %ss\n' "$run" "$rc" "$elapsed"
        failures=$((failures + 1))
        continue
    fi

    if [[ -n $REGEX ]]; then
        value=$(python3 -c "
import re, sys
pattern = re.compile(sys.argv[1])
text = open(sys.argv[2], errors='replace').read()
matches = pattern.findall(text)
# Take the last match: workloads often print per-iteration values and the
# final one is the summary figure.
print(matches[-1] if matches else '')
" "$REGEX" "$stdout_file" 2>/dev/null)
        if [[ -n $value ]]; then
            printf '  run %d: ok, %ss, metric = %s\n' "$run" "$elapsed" "$value"
            echo "$value" >> "$values_file"
        else
            printf '  run %d: ok, %ss, REGEX DID NOT MATCH\n' "$run" "$elapsed"
            failures=$((failures + 1))
        fi
    else
        printf '  run %d: ok, %ss\n' "$run" "$elapsed"
    fi
done

[[ -n $KEEP_OUTPUT ]] && cp "$stdout_file" "$KEEP_OUTPUT"

echo
mean_time=$(awk '{s+=$1; n++} END{if(n) printf "%.3f", s/n; else print 0}' "$times_file")
max_time=$(awk 'NR==1||$1>m{m=$1} END{printf "%.3f", m+0}' "$times_file")
echo "  Mean wall time : ${mean_time}s"

if (( BASELINE_RUNS > 1 )); then
    spread=$(awk -v mean="$mean_time" '
        NR==1{min=max=$1}
        {if($1<min)min=$1; if($1>max)max=$1}
        END{if(mean>0) printf "%.1f", 100*(max-min)/mean; else print 0}' "$times_file")
    echo "  Time spread    : ${spread}% of mean"
fi

if [[ -s $values_file ]] && (( BASELINE_RUNS > 1 )); then
    metric_spread=$(awk '
        NR==1{min=max=$1}
        {s+=$1; n++; if($1<min)min=$1; if($1>max)max=$1}
        END{if(n && s/n>0) printf "%.1f", 100*(max-min)/(s/n); else print 0}' "$values_file")
    echo "  Metric spread  : ${metric_spread}% of mean"
fi

# Give the optimizer generous headroom.  The worst-case trial runs at the bottom
# of the swept range, so the slowdown approaches the ratio of the highest to the
# lowest setting.  Measured on a 3.7 GHz part swept down to 1.0 GHz, a workload
# went from 17.0s to 49.0s, a factor of 2.9, so a 3x margin leaves almost
# nothing spare.  4x is the safer default; a timeout is scored as a failed
# trial rather than a slow one.
timeout_rec=$(awk -v t="$max_time" 'BEGIN{v=t*4; if(v<60) v=60; printf "%d", v+0.5}')
echo "  Suggested      : --application-timeout ${timeout_rec}"

echo
echo "  Assessment:"

if (( failures > 0 )); then
    echo "  - ${failures} of ${BASELINE_RUNS} run(s) failed or did not produce the metric."
    echo "    Fix this before starting a campaign; every trial would fail the"
    echo "    same way."
    if [[ -n $REGEX ]]; then
        echo "    Inspect the real output with --save-output and test the pattern"
        echo "    against it before spending trials."
    fi
fi

short=$(awk -v t="$mean_time" 'BEGIN{print (t < 10) ? 1 : 0}')
long=$(awk -v t="$mean_time" 'BEGIN{print (t > 1800) ? 1 : 0}')

if (( short )); then
    echo "  - Under 10s per run.  Startup cost and measurement noise will"
    echo "    likely swamp the effect of a frequency or power change.  Increase"
    echo "    the problem size or iteration count so a run takes 30s or more."
fi

if (( long )); then
    hours=$(awk -v t="$mean_time" 'BEGIN{printf "%.1f", 30*t/3600}')
    echo "  - Over 30 minutes per run.  A 30-trial campaign would take about"
    echo "    ${hours} hours.  Consider a shorter representative configuration."
fi

if (( BASELINE_RUNS > 1 )) && [[ -s $values_file ]]; then
    noisy=$(awk '
        NR==1{min=max=$1}
        {s+=$1; n++; if($1<min)min=$1; if($1>max)max=$1}
        END{if(n && s/n>0) print (100*(max-min)/(s/n) > 5) ? 1 : 0; else print 0}' "$values_file")
    if (( noisy )); then
        echo "  - Metric varies more than 5% between identical runs.  The"
        echo "    optimizer cannot distinguish a real improvement from noise"
        echo "    smaller than this, so treat close results as ties."
    fi
fi

if (( failures == 0 && ! short && ! long )); then
    est30=$(awk -v t="$mean_time" 'BEGIN{printf "%.1f", 30*t/60}')
    echo "  - Suitable for a campaign.  30 trials would take roughly"
    echo "    ${est30} minutes at baseline speed, and longer in practice"
    echo "    because reduced settings slow each run."
fi

(( failures > 0 )) && exit 1
exit 0
