#
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

'''The gffi module provides a wrapper around the cffi interface

TODO REVIEW: The libgeopmd dependency on libgeopm is no longer true, right?

This module enables a single cffi.FFI() object to be used throughout
all of the GEOPM python modules and also enables us to enforce that
the libgeopm.so dynamic library is opened prior to libgeopmd.so.
This is required because libgeopmd.so allocates static objects that
depend on static objects defined in libgeopm.so (in particular
the geopm::ApplicationSampler).

'''

def get_dl_geopmd():
    '''Get the FFILibrary instance for libgeopmd.so

    Returns:
        FFILibrary: Object used to call functions defined in
                    libgeopmd.so

    '''
    global _dl_geopmd
    if type(_dl_geopmd) is OSError:
        raise _dl_geopmd
    return _dl_geopmd

def get_dl_geopm():
    '''Get the FFILibrary instance for libgeopm.so

    Returns:
        FFILibrary: Object used to call functions defined in
                    libgeopm.so

    '''
    global _dl_geopm
    if type(_dl_geopm) is OSError:
        raise _dl_geopm
    return _dl_geopm

# Enforce load order of libgeopm.so and libgeopmd.so by loading
# them together in this module.
try:
    from geopmpy._libgeopm import ffi as gffi, lib as _dl_geopm
except OSError as err:
    _dl_geopm = err

# Load libgeopmd.so after libgeopm.so
try:
    from geopmdpy._libgeopmd import ffi as gffi, lib as _dl_geopmd
except OSError as err:
    _dl_geopmd = err
