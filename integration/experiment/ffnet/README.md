Feed-Forward Net-Based Experiments
----------------------------------

The scripts in this directory are used to run and analyze application
runs that use the ffnet agent with a specified path to neural net and
frequency recommendation maps, optionally with a specified perf energy bias.

## Base Experiment Module

#### `ffnet.py`:

  Contains the helper function for launching an FFNet agent experiment.

  In addition to command line arguments common to all run scripts, the
  FFNet agent experiment script requires the following parameters:

  - `--perf-energy-bias`: (default=0) A bias [0-1] that indicates the amount of
                          performance degradation that is acceptable in order to
                          achieve an improvement in energy efficiency. A value
                          of 0 indicates that performance degradation is not
                          tolerated. A value of 1 indicates that energy efficiency
                          is of utmost importance. Note that there are no absolute
                          guarantees on the amount of performance degradation or
                          energy savings.

  The following environment variable must be set before running the FFNet agent:

  - `GEOPM_FFNET_PATH`: A directory containing the neural network and frequency
                        recommendation map JSON files. The directory must include:
                        - Neural net JSON files with the suffix `*_nn_cpu.json` and/or `*_nn_gpu.json`.
                        - Frequency recommendation map JSON files with the suffix `*_fmap_cpu.json` and/or `*_fmap_gpu.json`.

  Example:
  ```
  export GEOPM_FFNET_PATH=/path/to/ffnet/files
  ```

## Additional Experiment Module
#### `neural_net_sweep.py`:

  Contains the helper function for launching a frequency sweep experiment, the data from
  which can be used to generate neural net and region parameter json files. This function
  executes a CPU/GPU/uncore frequency sweep while gathering telemetry that is useful to 
  differentiate regions of interest.

  In addition to command line arguments common to all run scripts, this script also accepts
  options used by the `gpu_frequency_sweep` experiment. Note that for each domain
  (CPU/GPU/uncore), a sweep will not run unless both minimum and maximum frequencies are
  supplied and unequal to one another.

  **CPU Frequency Settings**

  - `--max-frequency`: the maximum CPU frequency setting for the sweep. If not
                       specified, a CPU frequency sweep will not run.

  - `--min-frequency`: the minimum CPU frequency setting for the sweep. If not
                       specified, a CPU frequency sweep will not run.

  - `--step-frequency`: (optional) the step size in hertz between CPU frequency
                        settings for the sweep. The default value is the CPU's
                        frequency step size.
 
  - `--run-max-turbo`: (optional, default=False) executes additional runs with 
                       max turbo frequency as the limit for the core frequency.

  **CPU Uncore Frequency Settings**
 
  - `--max-uncore-frequency`: the maximum uncore frequency setting for
                              the sweep. If not specified, an uncore
                              frequency sweep will not run.

  - `--min-uncore-frequency`: the minimum uncore frequency setting for
                              the sweep. If not specified, an uncore
                              frequency sweep will not run.

  - `--step-uncore-frequency`: the step size in hertz between uncore
                               frequency settings for the sweep. The default
                               value is the CPU's frequency step size.

  **GPU Frequency Settings**

  - `--max-gpu-frequency`: the maximum GPU frequency setting for the sweep. If not
                           specified, a GPU frequency sweep will not run.

  - `--min-gpu-frequency`: the minimum GPU frequency setting for the sweep. If not
                           specified, a GPU frequency sweep will not run.

  - `--step-gpu-frequency`: the step size in hertz between settings for the sweep.
                            By default, it uses the minimum supported step size
                            of GPUs on the node.

  Note that for any frequency domain, if the values above are not specified or if
  the min and max values are equal, a frequency sweep will not be executed across
  that domain.

## Supporting Files

#### `gen_hdf_from_fsweep.py`:

  Generates HDF files used to generate the neural net and frequency recommendation json files.
  This takes report and trace files from frequency sweep experiments as inputs, checks for
  required signals on CPU and GPU domains, annotates data with microbenchmark and node names,
  and outputs the HDFs. Two files are generated: The stats file contains per-region report
  information used to determine frequency recommendation for each region class. The trace file
  contains trace data that is used to create a neural net that determines region class 
  probabilities during a workload execution.

  This script requires the following positional inputs:

  - `output`: Prefix for output files `[output]_stats.h5` and `[output]_traces.h5`
  - `frequency_sweep_dirs`: Directories containing reports and traces from frequency sweeps

  Example:

   ```
   ./gen_hdf_from_fsweep.py example_output /path/to/fsweep
   ```
   This will generate `example_output_stats.h5` and `example_output_traces.h5`

#### `gen_neural_net.py`:

   Generates neural net json file(s) for CPU and/or GPU. This takes in the trace HDF file generated 
   from `gen_hdf_from_fsweep.py` which is annotated with region classes. Required signals are 
   specified within this script, per-domain. The script checks for the complete list of signals
   and generates the corresponding neural nets. Note that this script depends upon pytorch. 
   Pytorch can be installed using: `pip install pytorch`

   This script requires the following input:

   - `--data` : Data files to train on. This can take in multiple trace HDF files.

   and can take in the following optional inputs:

   - `--output`: Prefix of the output json file(s). Default="neural_net"
   - `--description`: Description of the neural net. Default="A neural net"
   - `--ignore` : A comma-separated list of region hashes to ignore. Default=None


   Example:

   ```
   ./gen_neural_net.py --output nnet --description "A neural net" --data example_output_traces.h5
   ```
   This will generate `nnet_cpu.json` and/or `nnet_gpu.json`

#### `gen_region_parameters.py`:

   Generates region-class frequency recommendation maps. This takes in the stats HDF file
   generated from `gen_hdf_from_fsweep.py`, which is annotated with region classes and
   contains runtime and per-domain energy information. This is used to generate a
   runtime-frequency relationship and determine the minimum energy point within an allowable
   performance degradation. For each region class, a list is generated which contains the 
   desired frequency for a region class for various `perf-energy-bias` values, from
   most perf-sensitive to most energy-sensitive.

   This script requires the following input:

   - `--data-file`: The stats HDF generated from `gen_hdf_from_fsweep.py`.

   and can take in the following optional input:

   - `--output`: Prefix of the output json file(s). Default="region_parameters"

   Example:

   ```
    ./gen_region_parameters.py --output fmap --data-file example_output_stats.h5
   ```

   This will generate `fmap_cpu.json` and/or `fmap_gpu.json`

#### `gen_sweep_to_ffnet.py`:

   Executes scripts referenced above to: Generate HDFs, generate neural nets, and generate
   region-class frequency recommendation maps.

   This script requires the following input:

   - `frequency_sweep_dirs`: Directories containing reports and traces from frequency sweeps

   and can take in the following optional inputs:

   - `output`: prefix of the output HDF and json file(s). Default="ffnet"
   - `description`: Description of the neural net. Default="A neural net."
   - `ignore` : A comma-separated list of region hashes to ignore. Default=None

   This will generate all HDFs and json files referenced above.

   Example:

   ```
   ./gen_sweep_to_ffnet.py --output test --description "Test" --frequency_sweep_dirs /path/to/fsweep
   ```
   This will generate the following files:
   - `test_stats.h5`
   - `test_traces.h5`
   - `test_nn_cpu.json`  and/or `test_nn_gpu.json`
   - `test_fmap_gpu.json` and/or `test_fmap_gpu.json`


## Scripts to Produce Neural Nets and Frequency Recommendation Maps

The end-to-end process for utilizing this experiment to improve energy efficiency can be conducted
using the following steps.

1. Conduct a frequency sweep on a set of microbenchmarks, gathering the required signals.
   This can be done using `neural_net_sweep.py`. Microbenchmarks that have been shown to
   generate useful results include Arithmetic Intensity Benchmark and geopmbench on CPU,
   and the PARRES suite (DGEMM and STREAM) on GPU.

2. Generate neural net JSON files and region frequency recommendation map files using
   `gen_sweep_to_ffnet.py`. 

   Example:
   ```
   ./gen_sweep_to_ffnet.py --output test --description "Test" --frequency_sweep_dirs /path/to/fsweep
   ```

   Resulting JSON files will output in the directory specified by `GEOPM_FFNET_PATH` and filenames
   will be prepended with the user-provided prefix. Example output files:

   - CPU Neural Net: `test_nn_cpu.json`
   - CPU Region Frequency Recommendation Map: `test_fmap_cpu.json`
   - GPU Neural Net: `test_nn_gpu.json`
   - GPU Region Frequency Recommendation Map: `test_fmap_gpu.json`

3. Set the `GEOPM_FFNET_PATH` environment variable to point to the directory containing the generated JSON files.

   Example:
   ```
   export GEOPM_FFNET_PATH=/path/to/generated/files
   ```

4. Run your workload with the FFNet agent.

## Analysis Scripts to Produce Summary Tables and Visualizations

#### `gen_phi_sweep_graph.py`:

  Generates a graph that shows performance degradation and energy savings for different
  values of `perf-energy-bias`.
