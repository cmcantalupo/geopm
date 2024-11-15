#!/usr/bin/env python3
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

"""Use batch interface to write controls
    Examples:

        printf 'CPU_FREQUENCY_MAX_CONTROL board 0 2e9\\nCPU_FREQUENCY_MIN_CONTROL board 0 2e9\\n' > batch-config.txt
        ./geopmwritebatch.py batch-config.txt

            or

        printf 'CPU_FREQUENCY_MAX_CONTROL board 0 2e9\\nCPU_FREQUENCY_MIN_CONTROL board 0 2e9\\n' | ./geopmwritebatch.py
"""

import sys
from geopmdpy import pio
from geopmdpy import __version_str__
from mpi4py import MPI
import socket


def run(comm, input_string):
    requests = [line.strip().split() for line in input_string.splitlines()]
    ctl_idx = [pio.push_control(rr[0], rr[1], int(rr[2])) for rr in requests]
    sig_idx = [pio.push_signal(rr[0], rr[1], int(rr[2])) for rr in requests]
    for ii, rr in enumerate(requests):
        pio.adjust(ctl_idx[ii], float(rr[3]))
    pio.write_batch()
    pio.read_batch()
    names = [rr[0] for rr in requests]
    names = ['hostname'] + names
    sigs = [str(pio.sample(idx)) for idx in sig_idx]
    sigs = [socket.gethostname()] + sigs
    if comm.rank == 0:
        print(','.join(names))
        sys.stdout.flush()
    comm.barrier()
    print(','.join(sigs))

def read_stream(comm, input_stream):
    if MPI.COMM_WORLD.rank == 0:
        input_string = input_stream.read()
    else:
        input_string = None
    input_string = comm.bcast(input_string, root=0)
    return input_string

def main(comm):
    if len(sys.argv) > 1:
        if sys.argv[1] == '--help':
            print(__doc__)
            return 0
        if sys.argv[1] == '--version':
            print(__version_str__)
            return 0
        with open(sys.argv[1]) as input_stream:
            input_string = read_stream(comm, input_stream)
    else:
        input_string = read_stream(comm, sys.stdin)
    run(comm, input_string)

if __name__ == '__main__':
    comm = MPI.COMM_WORLD.Split_type(MPI.COMM_TYPE_SHARED)
    color = 0 if comm.rank == 0 else 1
    comm = MPI.COMM_WORLD.Split(color)
    if color == 0:
        main(comm)
    MPI.COMM_WORLD.barrier()
