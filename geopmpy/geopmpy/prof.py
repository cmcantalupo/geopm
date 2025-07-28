#
#  Copyright (c) 2015 - 2025 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

from . import gffi
from geopmdpy import error

REGION_HINT_UNSET = gffi.dl_geopm.GEOPM_REGION_HINT_UNSET
REGION_HINT_UNKNOWN = gffi.dl_geopm.GEOPM_REGION_HINT_UNKNOWN
REGION_HINT_COMPUTE = gffi.dl_geopm.GEOPM_REGION_HINT_COMPUTE
REGION_HINT_MEMORY = gffi.dl_geopm.GEOPM_REGION_HINT_MEMORY
REGION_HINT_NETWORK = gffi.dl_geopm.GEOPM_REGION_HINT_NETWORK
REGION_HINT_IO = gffi.dl_geopm.GEOPM_REGION_HINT_IO
REGION_HINT_SERIAL = gffi.dl_geopm.GEOPM_REGION_HINT_SERIAL
REGION_HINT_PARALLEL = gffi.dl_geopm.GEOPM_REGION_HINT_PARALLEL
REGION_HINT_IGNORE = gffi.dl_geopm.GEOPM_REGION_HINT_IGNORE
REGION_HINT_INACTIVE = gffi.dl_geopm.GEOPM_REGION_HINT_INACTIVE
REGION_HINT_SPIN = gffi.dl_geopm.GEOPM_REGION_HINT_SPIN
NUM_REGION_HINT = gffi.dl_geopm.GEOPM_NUM_REGION_HINT

class Region:
    def __init__(self, name, hint=0, num_work_unit=0):
        """Create a new region for profiling.

        Args:
            name (str): Name of the region.
            hint (int): Hint for the region type, one of the REGION_HINT_* constants.
            num_work_unit (int): Number of work units for the region, used for time profiling
                (tprof). If set to 0, tprof is not initialized for this region
        """
        self._name = name
        self._hint = hint
        self._id = None
        self._num_unit = num_work_unit

    def __enter__(self):
        """Enter the region context, initializing profiling and time profiling if applicable.

        Raises:
            RuntimeError: If any of the geopm profiling calls fail.
        """
        name_ptr = gffi.gffi.new("char[]", self._name.encode())
        hint = self._hint
        id_ptr = gffi.gffi.new("uint64_t*")
        err = gffi.dl_geopm.geopm_prof_region(name_ptr, hint, id_ptr)
        if err != 0:
            raise RuntimeError(f'Call to geopm_prof_region() failed: {error.message(err)}')
        self._id = id_ptr[0]
        err = gffi.dl_geopm.geopm_prof_enter(self._id)
        if err != 0:
            raise RuntimeError(f'Call to geopm_prof_enter() failed: {error.message(err)}')
        if self._num_unit != 0:
            err = gffi.dl_geopm.geopm_tprof_init(self._num_unit)
            if err != 0:
                raise RuntimeError(f'Call to geopm_tprof_init() failed: {error.message(err)}')

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Exit the region context, finalizing profiling and time profiling if applicable.

        Args:
            exc_type: Exception type if an exception occurred.
            exc_val: Exception value if an exception occurred.
            exc_tb: Traceback object if an exception occurred.

        """
        err = gffi.dl_geopm.geopm_prof_exit(self._id)
        if err != 0:
            raise RuntimeError(f'Call to geopm_prof_exit() failed: {error.message(err)}')

    def post(self):
        """Post that one work unit has been completed.

        Raises:
            RuntimeError: If the geopm_tprof_post() call fails.
        """
        err = gffi.dl_geopm.geopm_tprof_post()
        if err != 0:
            raise RuntimeError(f'Call to geopm_tprof_post() failed: {error.message(err)}')


def prof_epoch():
    """Signal the beginning of an iterative loop.

    Used to mark the timing of a profiling epoch, which demarks
    the execution of the outer loop of an iterative process.

    Raises:
        RuntimeError: If the geopm_prof_epoch() call fails.
    """
    err = gffi.dl_geopm.geopm_prof_epoch()
    if err != 0:
        raise RuntimeError(f'Call to geopm_prof_epoch() failed: {error.message(err)}')


def prof_overhead(overhead_sec):
    """Set the overhead time for profiling.

    Args:
        overhead_sec (float): Overhead time in seconds.

    Raises:
        RuntimeError: If the geopm_prof_overhead() call fails.
    """
    err = gffi.dl_geopm.geopm_prof_overhead(overhead_sec)
    if err != 0:
        raise RuntimeError(f'Call to geopm_prof_overhead() failed: {error.message(err)}')

def prof_shutdown():
    """Signal the end of the profiling session.

    Raises:
        RuntimeError: If the geopm_prof_shutdown() call fails.
    """
    err = gffi.dl_geopm.geopm_prof_shutdown()
    if err != 0:
        raise RuntimeError(f'Call to geopm_prof_shutdown() failed: {error.message(err)}')
