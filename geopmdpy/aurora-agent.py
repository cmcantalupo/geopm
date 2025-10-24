#!/usr/bin/env python3
#  Copyright (c) 2015 - 2025 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#
from geopmdpy.session import main
from geopmdpy.session import Agent
from geopmdpy.write import batch as write_batch
from geopmdpy.pio import save_control, restore_control, adjust, write_batch

_SIGNAL_CONFIG_OVERRIDE = """\
DRM::RPS_ACT_FREQ gpu_chip *
LEVELZERO::GPU_CORE_TEMPERATURE_MAXIMUM gpu_chip *
LEVELZERO::GPU_MEMORY_TEMPERATURE_MAXIMUM gpu_chip *
"""

def parse_batch_copy(input_stream):
    """Copy/pasted code for backward compatibility"""
    requests = [line.split() for line in input_stream.readlines()]
    ctl_idx = []
    settings = []
    control_names = pio.control_names()
    for rr in requests:
        if len(rr) == 0:
            continue # ignore empty lines
        if len(rr) != 4:
            raise RuntimeError(f'Number of words per line in configuration file must be 4, got {len(rr)}')
        name = rr[0]
        if name not in control_names:
            raise ValueError(f'Control name unknown: {name}')
        domain = topo.domain_type(rr[1])
        try:
            domain_idx = int(rr[2])
        except ValueError:
            raise ValueError(f'Could not convert domain index into a number: {rr[2]}')
        if domain_idx < 0 or domain_idx >= topo.num_domain(domain):
            raise ValueError(f'Domain index out of bounds: {domain_idx}')
        try:
            settings.append(float(rr[3]))
        except ValueError:
            raise ValueError(f'Could not convert setting to floating point number: "{rr[3]}"')
        ctl_idx.append(pio.push_control(name, domain, domain_idx))
    return zip(ctl_idx, settings)

try:
    from geopmdpy.write import parse_batch
except ImportError:
    parse_batch = parse_batch_copy

class AuroraOptAgent(Agent):
    """Agent to be used with geopmopt for energy efficiency on Aurora

    """
    def __init__(self):
        self._write_config = None
        self._first_loop = True
        self._adjust_par = None

    def update_parser(self, parser):
        parser.add_argument('--write-config',
                            help='Control values to write at start of session')
        return parser

    def update_args(self, args):
        self._write_config = args.write_config
        return args

    def help(self):
        return AuroraOptAgent.__doc__

    def signal_config_override(self):
        return _SIGNAL_CONFIG_OVERRIDE

    def run_begin(self):
        if self._write_config:
            save_control()
            with open(self._write_config) as fid:
                self._adjust_par = parse_batch(fid)

    def update_loop(self):
        if self._first_loop and self._adjust_par:
            for par in self._adjust_par:
                adjust(*par)
            write_batch()
        self._first_loop = False

    def run_end(self):
        if self._write_config:
            restore_control()

if __name__ == '__main__':
    main(AuroraOptAgent())
