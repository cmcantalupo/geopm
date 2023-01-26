/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "config.h"
#include "SysfsIOGroup.hpp"
#include "SysfsIO.hpp"

namespace geopm
{
    SysfsIOGroup::SysfsIOGroup()
        : SysfsIOGroup(driver(), description_json())
    {

    }

    SysfsIOGroup(const std::string &driver, const std::string &description_json)
        : m_sysfsio(SysfsIO::make_unique(driver))
        , m_description(parse_json(description_json))
    {

    }
}

#endif
