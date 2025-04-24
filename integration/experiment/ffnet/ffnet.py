#!/usr/bin/env python3
#
#  Copyright (c) 2015 - 2024, Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

'''
Helper functions for running CPU activity agent experiments.
'''

import argparse
import os
import glob

import geopmpy.agent

from integration.experiment import launch_util
from integration.experiment import common_args
from integration.experiment import machine

def setup_run_args(parser):
    common_args.setup_run_args(parser)
    parser.add_argument('--perf-energy-bias', dest='perf_energy_bias', type=float,
                        action='store', default=0,
                        help='Perf-Energy Bias [0-1] where 0 is perf-sensitive and 1 is energy-efficient')
    parser.add_argument('--cpu-nn-path', dest='cpu_nn_path',
                        action='store', default=None,
                        help='Full path for the CPU NN')
    parser.add_argument('--gpu-nn-path', dest='gpu_nn_path',
                        action='store', default=None,
                        help='Full path for the GPU NN')
    parser.add_argument('--cpu-fmap-path', dest='cpu_fmap_path',
                        action='store', default=None,
                        help='Full path for the CPU Frequency Recommender Map')
    parser.add_argument('--gpu-fmap-path', dest='gpu_fmap_path',
                        action='store', default=None,
                        help='Full path for the GPU Frequency Recommender Map')

def report_signals():
    return []

def trace_signals():
    return []

def setup_env_paths(args):
    ffnet_path = os.getenv("GEOPM_FFNET_PATH")
    if not ffnet_path:
        raise RuntimeError("GEOPM_FFNET_PATH environment variable is not set.")

    cpu_nn_files = glob.glob(os.path.join(ffnet_path, "*_nn_cpu.json"))
    cpu_fmap_files = glob.glob(os.path.join(ffnet_path, "*_fmap_cpu.json"))
    gpu_nn_files = glob.glob(os.path.join(ffnet_path, "*_nn_gpu.json"))
    gpu_fmap_files = glob.glob(os.path.join(ffnet_path, "*_fmap_gpu.json"))

    if cpu_nn_files and cpu_fmap_files:
        args.cpu_nn_path = cpu_nn_files[0]
        args.cpu_fmap_path = cpu_fmap_files[0]
    if gpu_nn_files and gpu_fmap_files:
        args.gpu_nn_path = gpu_nn_files[0]
        args.gpu_fmap_path = gpu_fmap_files[0]

    if not (cpu_nn_files and cpu_fmap_files) and not (gpu_nn_files and gpu_fmap_files):
        raise RuntimeError("No valid neural net or frequency map files found in GEOPM_FFNET_PATH.")

def launch_configs(output_dir, app_conf, perf_energy_bias=0):
    mach = machine.init_output_dir(output_dir)

    if perf_energy_bias > 1 or perf_energy_bias < 0:
        raise ValueError('perf-energy-bias must be between 0 and 1 for ffnet experiment.')

    agent = 'ffnet'
    targets = []
    options = {"PERF_ENERGY_BIAS": perf_energy_bias}
    name = f'{perf_energy_bias}peb'

    config_file = os.path.join(output_dir, f'{agent}_agent_{name}.config'.format(agent))
    agent_conf = geopmpy.agent.AgentConf(config_file, agent, options)
    targets.append(launch_util.LaunchConfig(app_conf=app_conf,
                                            agent_conf=agent_conf,
                                            name=name))
    return targets

def launch(app_conf, args, experiment_cli_args):
    output_dir = os.path.abspath(args.output_dir)
    extra_cli_args = launch_util.geopm_signal_args(report_signals=report_signals(),
                                                   trace_signals=trace_signals())
    extra_cli_args += experiment_cli_args

    setup_env_paths(args)

    targets = launch_configs(output_dir, app_conf, args.perf_energy_bias)

    # Set and initialize required counters
    init_control_path = os.path.join(output_dir, 'ffnet_init.controls')
    with open(init_control_path, 'w') as outfile:
        outfile.write("MSR::PQR_ASSOC:RMID board 0 0\n"
                      "# Assigns all cores to resource monitoring association ID 0\n"
                      "# Next, assign resource monitoring ID for QM events to match\n"
                      "MSR::QM_EVTSEL:RMID board 0 0\n"
                      "# Then determine Xeon Uncore Utilization\n"
                      "MSR::QM_EVTSEL:EVENT_ID board 0 0")

    launch_util.launch_all_runs(targets=targets,
                                num_nodes=args.node_count,
                                iterations=args.trial_count,
                                extra_cli_args=extra_cli_args,
                                output_dir=output_dir,
                                cool_off_time=args.cool_off_time,
                                enable_traces=args.enable_traces,
                                enable_profile_traces=args.enable_profile_traces,
                                init_control_path=init_control_path)

def main(app_conf, **defaults):
    parser = argparse.ArgumentParser()
    setup_run_args(parser)
    parser.set_defaults(**defaults)
    args, extra_args = parser.parse_known_args()
    launch(app_conf=app_conf, args=args,
           experiment_cli_args=extra_args)
