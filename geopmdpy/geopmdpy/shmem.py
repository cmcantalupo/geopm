#
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

from geopmdpy._libgeopmd import ffi, lib
from . import error

def create_prof(shm_key, size, pid, uid, gid):
    shm_key_cstr = ffi.new("char[]", shm_key.encode())
    err = lib.geopm_shmem_create_prof(shm_key_cstr, size, pid, uid, gid)
    if err < 0:
        raise RuntimeError('geopm_shmem_create_prof() failed: {}'.format(error.message(err)))

def path_prof(shm_key, pid, uid, gid):
    name_max = 1024
    shm_key_cstr = ffi.new("char[]", shm_key.encode())
    result_cstr = ffi.new("char[]", name_max)
    err = lib.geopm_shmem_path_prof(shm_key_cstr, pid, uid, name_max, result_cstr)
    if err < 0:
        raise RuntimeError('geopm_shmem_path_prof() failed: {}'.format(error.message(err)))
    return ffi.string(result_cstr).decode()
