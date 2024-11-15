#!/bin/bash
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

set -e

if [ -z "$MPI_DIR" ]; then
	echo "To select a different MPI directory location export MPI_DIR"
	MPI_DIR=$(dirname $(dirname $(which mpicc)))
fi
echo "MPI_DIR=$MPI_DIR"

echo "[mpi]
mpi_dir = $MPI_DIR
mpicc   = %(mpi_dir)s/bin/mpicc
mpicxx  = %(mpi_dir)s/bin/mpicxx
include_dirs         = %(mpi_dir)s/include
libraries            = mpi
library_dirs         = %(mpi_dir)s/lib
runtime_library_dirs = %(library_dirs)s" > mpi.cfg

MPI4PY_BUILD_MPICFG=$PWD/mpi.cfg python3 -m pip install mpi4py
set +x
echo "--------------------------------------------------------------------------"
echo "SUCCESS"
echo "--------------------------------------------------------------------------"
