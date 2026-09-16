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
                    prefetch/prefetch-disable is NOT supported here: geopmopt
                    expands it into four ordered MSR prefetcher-disable
                    controls rather than one value, so baseline it manually
                    or omit --dimension for that dimension.
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

    # --list-controls reports each control's *native* domain and bounds for that
    # domain, so the settings must be written there too.  Writing a
    # package-derived value once at board under-caps a summed control: on a
    # two-package host cpu-power's listed max is one package's TDP, while a
    # board write would cap the whole board at that value and flatter the
    # campaign's apparent improvement.
    domain_counts=$(geopmread --domain 2>/dev/null) || {
        echo "geopm-check-workload.sh: could not read the platform's domain list" >&2
        echo "  (geopmread --domain), so --dimension cannot place its control writes." >&2
        exit 2
    }

    seen_dims=""
    for DIMENSION in "${DIMENSIONS[@]}"; do
        # --list-controls always keys its table by the short alias (grid.py's
        # _PREFERRED_ALIAS), even though --sweep also accepts these long dashed
        # spellings (_CONTROL_ALIASES).  Normalize before the lookup below, or a
        # long spelling never matches a row and is rejected as unusable.
        case "$DIMENSION" in
            cpu-frequency)        DIMENSION=cpu-freq ;;
            cpu-uncore-frequency) DIMENSION=uncore-freq ;;
            gpu-frequency)        DIMENSION=gpu-freq ;;
        esac

        # prefetch expands to four ordered MSR disable controls in grid.py
        # (prefetch_settings()), not a single MAX/MIN pair; replicating that
        # level-to-controls mapping here would duplicate policy this baseline
        # helper shouldn't own, so it is rejected rather than silently wrong.
        if [[ $DIMENSION == prefetch || $DIMENSION == prefetch-disable ]]; then
            echo "geopm-check-workload.sh: '$DIMENSION' is not supported by --dimension." >&2
            echo "  geopmopt expands it into four ordered MSR prefetcher-disable controls" >&2
            echo "  (grid.py's prefetch_settings()); baseline it manually, or omit --dimension" >&2
            echo "  and compare against a geopmopt run over this dimension directly." >&2
            exit 2
        fi

        if printf '%s\n' "$seen_dims" | grep -qx "$DIMENSION"; then
            echo "geopm-check-workload.sh: '$DIMENSION' given more than once." >&2
            exit 2
        fi
        seen_dims+="${DIMENSION}"$'\n'

        read -r ctl_domain ctl_min ctl_max ctl_step < <(
            printf '%s\n' "$controls" | awk -v d="$DIMENSION" 'NR>1 && $1==d {print $2, $4, $5, $6}')
        if [[ -z ${ctl_domain:-} || $ctl_domain == n/a || $ctl_min == n/a || $ctl_max == n/a || $ctl_step == n/a ]]; then
            echo "geopm-check-workload.sh: '$DIMENSION' is not usable on this platform" >&2
            echo "  (domain=${ctl_domain:-unknown} max=${ctl_max:-unknown} step=${ctl_step:-unknown})." >&2
            echo "  See --list-controls." >&2
            exit 2
        fi
        # A never-tuned uncore control can auto-detect its max bound from the
        # control's *current* value, which reads 0 on such a host; --list-controls
        # reports a real domain and numeric bounds in that case, so the n/a check
        # above does not catch it.  See references/sweep-dimensions.md.
        if ! awk -v mx="$ctl_max" 'BEGIN{exit !(mx > 0)}' 2>/dev/null; then
            echo "geopm-check-workload.sh: '$DIMENSION' reports a non-positive max bound" >&2
            echo "  (max=${ctl_max}), so there is no valid reference value.  See" >&2
            echo "  references/sweep-dimensions.md for the uncore-freq max=0 case." >&2
            exit 2
        fi
        if awk -v mn="$ctl_min" -v mx="$ctl_max" 'BEGIN{exit !(mn > mx)}' 2>/dev/null; then
            echo "geopm-check-workload.sh: '$DIMENSION' reports min (${ctl_min}) greater" >&2
            echo "  than max (${ctl_max}), so its bounds are invalid.  See --list-controls." >&2
            exit 2
        fi
        # ControlGrid.get_dimension_grid() rejects a non-positive step, so a
        # baseline here would otherwise claim a dimension the campaign cannot run.
        if ! awk -v st="$ctl_step" 'BEGIN{exit !(st > 0)}' 2>/dev/null; then
            echo "geopm-check-workload.sh: '$DIMENSION' reports a non-positive step" >&2
            echo "  (step=${ctl_step}), so geopmopt cannot build a grid for it and no" >&2
            echo "  campaign over this dimension can run.  See --list-controls." >&2
            exit 2
        fi

        # Must match grid.py exactly -- see geopm-gen-access.sh and
        # geopm-sensitivity.sh for the same mapping and why it matters.
        case "$DIMENSION" in
            cpu-freq)    CONTROL=CPU_FREQUENCY_MAX_CONTROL ;;
            uncore-freq) CONTROL=CPU_UNCORE_FREQUENCY_MAX_CONTROL ;;
            cpu-power)   CONTROL=POWERCAP::CPU_POWER_LIMIT ;;
            gpu-freq)    CONTROL=GPU_CORE_FREQUENCY_MAX_CONTROL ;;
            gpu-power)   CONTROL=GPU_POWER_LIMIT_CONTROL ;;
            board-power) CONTROL=BOARD_POWER_LIMIT_CONTROL ;;
            *) echo "geopm-check-workload.sh: no control mapping for '$DIMENSION'." >&2
               echo "  Supported: cpu-freq, uncore-freq, cpu-power, gpu-freq, gpu-power, board-power" >&2
               exit 2 ;;
        esac

        ref=$ctl_max
        if [[ $DIMENSION == cpu-freq ]]; then
            sticker=$(geopmread CPU_FREQUENCY_STICKER package 0 2>/dev/null)
            if [[ -n $sticker ]] && awk -v s="$sticker" -v m="$ctl_max" 'BEGIN{exit !(s > 0 && s < m)}'; then
                ref=$sticker
            fi
            # geopmopt writes this unconditionally for every cpu-freq sweep, so
            # skipping it would baseline under the current governor instead.
            if printf '%s\n' "$granted_controls" | grep -qx CPU_FREQUENCY_GOVERNOR_CONTROL; then
                GOVERNOR_LINE="CPU_FREQUENCY_GOVERNOR_CONTROL board 0 0"
            else
                echo "geopm-check-workload.sh: CPU_FREQUENCY_GOVERNOR_CONTROL is not granted to you." >&2
                echo "  geopmopt writes it for every cpu-freq sweep, so this baseline would run" >&2
                echo "  under your current governor while the campaign runs under 'performance'." >&2
                echo "  Grant it first; see the geopm-install skill (references/access-lists.md)." >&2
                exit 2
            fi
        fi

        dom_count=$(printf '%s\n' "$domain_counts" | awk -v d="$ctl_domain" '$1==d {print $2}')
        if ! [[ ${dom_count:-} =~ ^[0-9]+$ ]] || (( dom_count < 1 )); then
            echo "geopm-check-workload.sh: '$DIMENSION' reports native domain '${ctl_domain}'," >&2
            echo "  which geopmread --domain does not list as present on this platform." >&2
            exit 2
        fi
        for (( dom_idx = 0; dom_idx < dom_count; dom_idx++ )); do
            CTL_LINES+=("$(printf '%s %s %d %s' "$CONTROL" "$ctl_domain" "$dom_idx" "$ref")")
        done
        if [[ $CONTROL == *_MAX_CONTROL ]]; then
            min_control=${CONTROL/_MAX_/_MIN_}
            if [[ $min_control != "$CONTROL" && $min_control != CPU_FREQUENCY_MIN_CONTROL ]]; then
                # grid.py pairs this MIN only when it is in pio.control_names(),
                # which for a service-backed client is the granted list; an
                # ungranted MIN is dropped there too, so mirror that rather
                # than failing the session on an unwritable control.
                if printf '%s\n' "$granted_controls" | grep -qx "$min_control"; then
                    for (( dom_idx = 0; dom_idx < dom_count; dom_idx++ )); do
                        CTL_LINES+=("$(printf '%s %s %d %s' "$min_control" "$ctl_domain" "$dom_idx" "$ref")")
                    done
                fi
            fi
        fi
        DIM_SUMMARY+=("${DIMENSION} (${CONTROL}) at ${ref} on ${dom_count} ${ctl_domain}(s)")
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
        echo "  Note      : all ${#DIM_SUMMARY[@]} dimensions are constrained together, as a"
        echo "              campaign sweeping them would -- see sweep-dimensions.md"
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
