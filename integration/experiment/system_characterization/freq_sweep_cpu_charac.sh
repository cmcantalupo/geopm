#!/bin/bash

set -e
set -x

module load geopm-runtime

START_TIME=${SECONDS}

PROGRAM_NAME="bench_avx512"
BINARY_PATH_PLUS_FLAGS="/home/sidjana/projects/arithmetic-intensity/${PROGRAM_NAME} -i 50"
SWEEP_OUTPUT_DIR="/flare/Intel-Punchlist/sidjana/aib_avx512_out_cpubind"
NUM_NODE=$(wc -l ${PBS_NODEFILE} | cut -d\  -f1)

CORE_MIN_FREQ=$(geopmread CPU_FREQUENCY_MIN_AVAIL board 0)
CORE_MAX_FREQ=$(geopmread CPU_FREQUENCY_MAX_AVAIL board 0)
CORE_FREQ_STEP=$(geopmread  CPU_FREQUENCY_STEP board 0)
UNCORE_MIN_FREQ=$(geopmread CPU_UNCORE_FREQUENCY_MIN_CONTROL board 0)
UNCORE_MAX_FREQ=$(geopmread CPU_UNCORE_FREQUENCY_MAX_CONTROL board 0)
UNCORE_FREQ_STEP=100000000

TRIAL_COUNT=3
RANK_CONT=98

rm -rf $SWEEP_OUTPUT_DIR/*
mkdir -p "$SWEEP_OUTPUT_DIR"

echo "Writing logs and reports to ${SWEEP_OUTPUT_DIR}"

GEOPM_SIGNALS="MSR::QM_CTR_SCALED_RATE@package,CPU_UNCORE_FREQUENCY_STATUS@package,MSR::CPU_SCALABILITY_RATIO@package,CPU_FREQUENCY_MIN_CONTROL@package,CPU_UNCORE_FREQUENCY_MIN_CONTROL@package"

# Replace exhaustive search with 2D binary search logic with discrete frequency stepping
python3 <<EOF

import numpy as np
import subprocess # nosec

from geopmpy.io import RawReportCollection

def binary_search_2d(core_min, core_max, core_step, uncore_min, uncore_max, uncore_step, trials, output_dir, program_name, binary_flags, rank_cont, signals):
    core_values = np.arange(core_min, core_max + core_step, core_step)
    uncore_values = np.arange(uncore_min, uncore_max + uncore_step, uncore_step)

    core_low, core_high = 0, len(core_values) - 1
    uncore_low, uncore_high = 0, len(uncore_values) - 1

    while core_low <= core_high and uncore_low <= uncore_high:
        core_mid = (core_low + core_high) // 2
        uncore_mid = (uncore_low + uncore_high) // 2

        core_freq = core_values[core_mid]
        uncore_freq = uncore_values[uncore_mid]

        all_reports = []
        for trial in range(trials):
            init_controls_list = f"{output_dir}/init_controls_cpu_core_{core_freq}_uncore_{uncore_freq}.lst"
            with open(init_controls_list, "w") as f:
                f.write(f"MSR::PQR_ASSOC:RMID board 0 0\n")
                f.write(f"MSR::QM_EVTSEL:RMID board 0 0\n")
                f.write(f"MSR::QM_EVTSEL:EVENT_ID board 0 2\n")
                f.write(f"CPU_FREQUENCY_MIN_CONTROL board 0 {core_freq}\n")
                f.write(f"CPU_FREQUENCY_MAX_CONTROL board 0 {core_freq}\n")
                f.write(f"CPU_UNCORE_FREQUENCY_MIN_CONTROL board 0 {uncore_freq}\n")
                f.write(f"CPU_UNCORE_FREQUENCY_MAX_CONTROL board 0 {uncore_freq}\n")
            report_file = f"{output_dir}/{program_name}_core_{core_freq}_uncore_{uncore_freq}_trial_{trial}_cpusweep.report"
            all_reports.append(report_file)
            log_file = f"{output_dir}/{program_name}_core_{core_freq}_uncore_{uncore_freq}_trial_{trial}_cpusweep.log"
            cmd = [
                "geopmlaunch", "pals",
                "-n", str(rank_cont), "-ppn", str(rank_cont), "--cpu-bind", "list:0-207",
                "--geopm-init-control", init_controls_list,
                "--geopm-ctl=application", "--geopm-preload",
                "--geopm-profile", program_name,
                "--geopm-report", report_file,
                "--geopm-report-signals", signals,
                "--geopm-program-filter", program_name,
                "--", binary_flags
            ]
            with open(log_file, "w") as log:
                subprocess.run(cmd, stdout=log, stderr=log)
        raw_report = RawReportCollection(all_reports)
        df = raw_report.get_df()

        # Use extract_columns() to filter the dataframe
        from integration.experiment.uncore_frequency_sweep.gen_cpu_activity_constconfig_recommendation import extract_columns
        filtered_df = extract_columns(df)

        # Evaluate energy for the region "intensity_16"
        region_energy = filtered_df.loc[filtered_df['region'] == 'intensity_16', 'package-energy (J)'].mean()
        print(f"Total energy for region 'intensity_16': {region_energy} J")

        # Adjust search ranges based on results (placeholder logic)
        if np.random.rand() > 0.5:  # Placeholder condition for core frequency
            core_high = core_mid - 1
        else:
            core_low = core_mid + 1
        if np.random.rand() > 0.5:  # Placeholder condition for uncore frequency
            uncore_high = uncore_mid - 1
        else:
            uncore_low = uncore_mid + 1

binary_search_2d(
    core_min=${CORE_MIN_FREQ},
    core_max=${CORE_MAX_FREQ},
    core_step=${CORE_FREQ_STEP},
    uncore_min=${UNCORE_MIN_FREQ},
    uncore_max=${UNCORE_MAX_FREQ},
    uncore_step=${UNCORE_FREQ_STEP},
    trials=${TRIAL_COUNT},
    output_dir="${SWEEP_OUTPUT_DIR}",
    program_name="${PROGRAM_NAME}",
    binary_flags="${BINARY_PATH_PLUS_FLAGS}",
    rank_cont=${RANK_CONT},
    signals="${GEOPM_SIGNALS}"
)
EOF

END_TIME=${SECONDS}
SECONDS_ELAPSED=$(( ${END_TIME} - ${START_TIME} ))
MINUTES_ELAPSED=$(( ${SECONDS_ELAPSED} / 60 ))
HOURS=$(( ${MINUTES_ELAPSED} / 60 ))
MINUTES=$(( ${MINUTES_ELAPSED} % 60 ))
SECONDS=$(( ${SECONDS_ELAPSED} % 60 ))

echo "INFO: Job took ${HOURS} hours, ${MINUTES} minutes, and ${SECONDS} seconds."
echo "INFO: Complete."



