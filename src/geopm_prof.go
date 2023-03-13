//
// Copyright (c) 2015 - 2023, Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//

// Go wrapper for the GEOPM profiling interface

// #cgo LDFLAGS: -lgeopm
// #cgo #include <geopm_prof.h>
import "C"


func geopm_prof_region(region_name string, hint uint64) uint64
{
    var result uint64 = 0
    region_name_cstr = C.CString(region_name)
    C.geopm_prof_region(region_name_cstr, hint, &result) 
    C.free(unsafe.Pointer(region_name_cstr)
    return result
}

func geopm_prof_enter(region_id uint64)
{
    C.geopm_prof_enter(region_id)
}

func geopm_prof_exit(region_id uint64)
{
    C.geopm_prof_exit(region_id)
}

func geopm_prof_epoch()
{
    C.geopm_prof_epoch()
}

func geopm_prof_shutdown()
{
    C.geopm_prof_shutdown()
}

func geopm_tprof_init(num_work_unit uint32)
{
    C.geopm_tprof_init(num_work_unit)
}

func geopm_tprof_post()
{
    C.geopm_tprof_post()
}

// Proposal for sidecar interface to enable an OpenTelemetry collector
// to communicate with a GEOPM controller.
//
// C APIs referenced below do not yet exist

func geopm_prof_region(region_name string, hint uint64) uint64
{
    var result uint64 = 0
    region_name_cstr = C.CString(region_name)
    C.geopm_prof_region(region_name_cstr, hint, &result) 
    C.free(unsafe.Pointer(region_name_cstr)
    return result
}

func geopm_prof_enter(region_id uint64, app_pid int)
{
    C.geopm_prof_enter(region_id, app_pid)
}

func geopm_prof_exit(region_id uint64, app_pid int)
{
    C.geopm_prof_exit(region_id, app_pid)
}

func geopm_prof_epoch(app_pid int)
{
    C.geopm_prof_epoch(app_pid)
}

func geopm_prof_shutdown(app_pid int)
{
    C.geopm_prof_shutdown(app_pid)
}

func geopm_tprof_init(num_work_unit uint32, app_pid)
{
    C.geopm_tprof_init(num_work_unit, app_pid)
}

func geopm_tprof_post(app_pid)
{
    C.geopm_tprof_post(app_pid)
}
