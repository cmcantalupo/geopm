/*
 * Copyright (c) 2015 - 2025 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef POWERCAP_IOGROUP_HPP_INCLUDE
#define POWERCAP_IOGROUP_HPP_INCLUDE

#include "SysfsIOGroup.hpp"
#include "PowercapSysfsDriver.hpp"
#include <memory>
#include <chrono>

namespace geopm
{
    class PinkNoiseGenerator;

    class PowercapIOGroup : public SysfsIOGroup
    {
    public:
        PowercapIOGroup();
        PowercapIOGroup(std::shared_ptr<PowercapSysfsDriver> driver);
        double read_signal(const std::string &signal_name, int domain_type, int domain_idx) override;
        void read_batch(void) override;
        double sample_signal(const std::string &signal_name, int domain_idx) const override;

    private:
        PinkNoiseGenerator m_pink_noise_gen;
        std::chrono::steady_clock::time_point m_last_time;
        double m_last_noise;
    };
}

#endif
