#
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#


from geopmdpy.gffi import gffi
from geopmdpy.gffi import get_dl_geopm
from geopmdpy import error

gffi.cdef("""
#include <stddef.h>
#include <stdint.h>

int geopm_prof_region(const char *region_name, uint64_t hint, uint64_t *region_id);

int geopm_prof_enter(uint64_t region_id);

int geopm_prof_exit(uint64_t region_id);

int geopm_prof_epoch(void);

int geopm_prof_shutdown(void);

int geopm_tprof_init(uint32_t num_work_unit);

int geopm_tprof_post(void);

""")
try:
    _dl = get_dl_geopm()
except OSError as ee:
    raise OSError('This module requires libgeopm.so to be present in your LD_LIBRARY_PATH.') from ee

def region(region_name, hint):
    global gffi
    global _dl

    region_name_cstr = gffi.new("char[]", region_name.encode())
    region_id = gffi.gffi.new("unsigned long*")
    err = _dl.geopm_prof_region(region_name_cstr, hint, region_id)
    if err != 0:
        raise RuntimeError('geopm_prof_region() failed: {}'.format(error.message(err)))
    return region_id[0]

def enter(region_id):
    global gffi
    global _dl

    err = _dl.geopm_prof_enter(region_id)
    if err != 0:
        raise RuntimeError('geopm_prof_enter() failed: {}'.format(error.message(err)))

def exit(region_id):
    global gffi
    global _dl

    err = _dl.geopm_prof_exit(region_id)
    if err != 0:
        raise RuntimeError('geopm_prof_exit() failed: {}'.format(error.message(err)))

def epoch():
    global gffi
    global _dl

    err = _dl.geopm_prof_epoch()
    if err != 0:
        raise RuntimeError('geopm_prof_epoch() failed: {}'.format(error.message(err)))

def shutdown():
    global gffi
    global _dl

    err = _dl.geopm_prof_shutdown()
    if err != 0:
        raise RuntimeError('geopm_prof_shutdown() failed: {}'.format(error.message(err)))

def tinit(num_work_unit):
    global gffi
    global _dl

    err = _dl.geopm_tprof_init(num_work_unit)
    if err != 0:
        raise RuntimeError('geopm_tprof_init() failed: {}'.format(error.message(err)))

def tpost():
    global gffi
    global _dl

    err = _dl.geopm_tprof_post()
    if err != 0:
        raise RuntimeError('geopm_tprof_post() failed: {}'.format(error.message(err)))
