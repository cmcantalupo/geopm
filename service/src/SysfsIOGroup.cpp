/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "config.h"
#include "SysfsIOGroup.hpp"
#include "SysfsIO.hpp"

namespace geopm
{
    SysfsIOGroup::SysfsIOGroup(std::shared_ptr<SysfsIO> sysfsio)
        : m_sysfsio(std::move(sysfsio))
    {

    }

    // TODO: implement an IOGroup around the sysfsio interface.
}

#endif
