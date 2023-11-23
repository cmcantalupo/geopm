/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "CpufreqSysfsIOGroup.hpp"

namespace geopm
{
    CpufreqSysfsIOGroup::CpufreqSysfsIOGroup()
	: SysfsIOGroup(std::make_shared<CpufreqSysfsIO>())
    {

    }
}
