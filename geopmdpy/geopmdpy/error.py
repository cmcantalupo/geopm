#
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#


import sys
from geopmdpy._libgeopmd import ffi, lib

ERROR_RUNTIME = lib.GEOPM_ERROR_RUNTIME
ERROR_LOGIC = lib.GEOPM_ERROR_LOGIC
ERROR_INVALID = lib.GEOPM_ERROR_INVALID
ERROR_FILE_PARSE = lib.GEOPM_ERROR_FILE_PARSE
ERROR_LEVEL_RANGE = lib.GEOPM_ERROR_LEVEL_RANGE
ERROR_NOT_IMPLEMENTED = lib.GEOPM_ERROR_NOT_IMPLEMENTED
ERROR_PLATFORM_UNSUPPORTED = lib.GEOPM_ERROR_PLATFORM_UNSUPPORTED
ERROR_MSR_OPEN = lib.GEOPM_ERROR_MSR_OPEN
ERROR_MSR_READ = lib.GEOPM_ERROR_MSR_READ
ERROR_MSR_WRITE = lib.GEOPM_ERROR_MSR_WRITE
ERROR_AGENT_UNSUPPORTED = lib.GEOPM_ERROR_AGENT_UNSUPPORTED
ERROR_AFFINITY = lib.GEOPM_ERROR_AFFINITY
ERROR_NO_AGENT = lib.GEOPM_ERROR_NO_AGENT

def message(err_number):
    """Return the error message associated with the error code.  Positive
    error codes are interpreted as system error numbers, and
    negative error codes are interpreted as GEOPM error numbers.

    Args:
        err_number (int): Error code to be interpreted.

    Returns:
        str: Error message associated with error code.

    """
    path_max = 4096
    result_cstr = ffi.new("char[]", path_max)
    lib.geopm_error_message(err_number, result_cstr, path_max)
    return ffi.string(result_cstr).decode()
