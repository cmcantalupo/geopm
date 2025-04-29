#!/bin/bash

set -e
set -x


module load geopm-runtime

START_TIME=${SECONDS}

PROGRAM_NAME="nstream-onemkl"
BINARY_PATH_PLUS_FLAGS="/home/sidjana/projects/geopm/integration/apps/parres/Kernels/Cxx11/${PROGRAM_NAME} 9999 900000000"
SWEEP_OUTPUT_DIR="/flare/Intel-Punchlist/sidjana/parres_onemkl_out"
NUM_NODE=$(wc -l ${PBS_NODEFILE} | cut -d\  -f1)

GPU_CORE_MIN_FREQ=$(geopmread GPU_CORE_FREQUENCY_MIN_AVAIL board 0)
GPU_CORE_MAX_FREQ=$(geopmread GPU_CORE_FREQUENCY_MAX_AVAIL board 0)
GPU_CORE_FREQ_STEP=$(geopmread GPU_CORE_FREQUENCY_STEP board 0)

TRIAL_COUNT=2

mkdir -p "$SWEEP_OUTPUT_DIR"
rm -rf $SWEEP_OUTPUT_DIR/*

echo "Writing logs and reports to ${SWEEP_OUTPUT_DIR}"

GEOPM_SIGNALS="GPU_CORE_FREQUENCY_STATUS@board,GPU_CORE_FREQUENCY_MIN_CONTROL@board"
for ((p="$GPU_CORE_MIN_FREQ"; p<="$GPU_CORE_MAX_FREQ"; p=p+"$GPU_CORE_FREQ_STEP")); do

      # Create a file with list of controls 
      INIT_CONTROLS_LIST="${SWEEP_OUTPUT_DIR}/init_controls_gpu_core_${p}.lst"
      printf "GPU_CORE_FREQUENCY_MIN_CONTROL board 0 ${p}\nGPU_CORE_FREQUENCY_MAX_CONTROL board 0 ${p}\n" \
             > $INIT_CONTROLS_LIST
      # Launch characterizing application over multiple trials
      for ((t=0; t<"$TRIAL_COUNT"; t++)); do

          echo "================= Trial $t, GPU CORE $p FREQ SWEEP ================="

          geopmlaunch pals \
            -n ${NUM_NODE} -ppn 1 \
            --geopm-init-control=$INIT_CONTROLS_LIST \
            --geopm-ctl=application \
            --geopm-preload \
            --geopm-profile="${PROGRAM_NAME}" \
            --geopm-report="${SWEEP_OUTPUT_DIR}/${PROGRAM_NAME}_core_${p}_trial_${t}_gpusweep.report" \
            --geopm-report-signals=${GEOPM_SIGNALS} \
            --geopm-program-filter=${PROGRAM_NAME} \
            -- ${BINARY_PATH_PLUS_FLAGS} 2>&1 \
            > "${SWEEP_OUTPUT_DIR}/${PROGRAM_NAME}_core_${p}_trial_${t}_gpusweep.log"
   
         sleep 5
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



