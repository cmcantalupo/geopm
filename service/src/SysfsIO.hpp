/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SYSFSIO_HPP_INCLUDE
#define SYSFSIO_HPP_INCLUDE

#include <string>
#include <memory>

namespace geopm
{
    class SysfsIO
    {
        public:
            struct metadata_s {
                int native_domain, // geopm_domain_e
                int units, // IOGroup::m_units_e
                int behavior, // IOGroup::m_signal_behavior_e
                int aggregation, // Agg::m_type_e
                std::string descrption,
                std::string alias,
            };
            SysfsIO() = default;
            virtual ~SysfsIO() = default;
            virtual std::vector<std::string> signal_names(void) const = 0;
            virtual std::vector<std::string> control_names(void) const = 0;
            virtual std::string signal_path(const std::string &signal_name,
                                            int domain_type,
                                            int domain_idx) = 0;
            virtual std::string control_path(const std::string &control_name,
                                             int domain_type,
                                             int domain_idx) const = 0;
            virtual double signal_parse(const std::string &signal_name,
                                        int domain_type,
                                        int domain_idx,
                                        const std::string &content) const = 0;
            virtual std::string control_gen(const std::string &signal_name,
                                            int domain_type,
                                            int domain_idx,
                                            double setting) const = 0;
            virtual std::string driver(void) const = 0;
            virtual struct metadata_s metadata(const std::string &name) const = 0;
            virtual std::string metadata_json(void) const = 0;
    };
}

#endif
