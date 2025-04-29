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
for ((p="$CORE_MIN_FREQ"; p<="$CORE_MAX_FREQ"; p=p+"$CORE_FREQ_STEP")); do
    for ((u="$UNCORE_MIN_FREQ"; u<="$UNCORE_MAX_FREQ"; u=u+"$UNCORE_FREQ_STEP")); do

      # Create a file with list of controls 
      INIT_CONTROLS_LIST="${SWEEP_OUTPUT_DIR}/init_controls_cpu_core_${p}_uncore_${u}.lst"
      printf "MSR::PQR_ASSOC:RMID board 0 0\nMSR::QM_EVTSEL:RMID board 0 0\nMSR::QM_EVTSEL:EVENT_ID board 0 2\nCPU_FREQUENCY_MIN_CONTROL board 0 ${p}\nCPU_FREQUENCY_MAX_CONTROL board 0 ${p}\nCPU_UNCORE_FREQUENCY_MIN_CONTROL board 0 ${u}\nCPU_UNCORE_FREQUENCY_MAX_CONTROL board 0 ${u}\n" \
             > $INIT_CONTROLS_LIST
      # Launch characterizing application over multiple trials
      for ((t=0; t<"$TRIAL_COUNT"; t++)); do

          echo "================= Trial $t, CPU CORE $p UNCORE $u FREQ SWEEP ================="

          geopmlaunch pals \
            -n ${RANK_CONT} -ppn ${RANK_CONT}   --cpu-bind list:0-207 \
            --geopm-init-control=$INIT_CONTROLS_LIST \
            --geopm-ctl=application \
            --geopm-preload \
            --geopm-profile="${PROGRAM_NAME}" \
            --geopm-report="${SWEEP_OUTPUT_DIR}/${PROGRAM_NAME}_core_${p}_uncore_${u}_trial_${t}_cpusweep.report" \
            --geopm-report-signals=${GEOPM_SIGNALS} \
            --geopm-program-filter=${PROGRAM_NAME} \
            -- ${BINARY_PATH_PLUS_FLAGS} 2>&1 \
            > "${SWEEP_OUTPUT_DIR}/${PROGRAM_NAME}_core_${p}_uncore_${u}_trial_${t}_cpusweep.log"
   
         sleep 5
      done
    done
done

#sleep 45


END_TIME=${SECONDS}
SECONDS_ELAPSED=$(( ${END_TIME} - ${START_TIME} ))
MINUTES_ELAPSED=$(( ${SECONDS_ELAPSED} / 60 ))
HOURS=$(( ${MINUTES_ELAPSED} / 60 ))
MINUTES=$(( ${MINUTES_ELAPSED} % 60 ))
SECONDS=$(( ${SECONDS_ELAPSED} % 60 ))

echo "INFO: Job took ${HOURS} hours, ${MINUTES} minutes, and ${SECONDS} seconds."
echo "INFO: Complete."



