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
            SysfsIO() = default;
            virtual ~SysfsIO() = default;
            static std::unique_ptr<SysfsIO> make_unique(const std::string &driver);
            virtual std::vector<std::string> signal_names(void) const = 0;
            virtual std::vector<std::string> control_names(void) const = 0;
            virtual int signal_domain_type(const std::string &signal_name) const = 0;
            virtual int control_domain_type(const std::string &control_name) const = 0;
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
    };
}

#endif
