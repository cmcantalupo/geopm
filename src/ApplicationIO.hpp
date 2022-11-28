/*
 * Copyright (c) 2015 - 2023, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef APPLICATIONIO_HPP_INCLUDE
#define APPLICATIONIO_HPP_INCLUDE

#include <cstdint>
#include <set>
#include <string>
#include <memory>
#include <vector>
#include <map>
#include <list>

#include "geopm_hint.h"

namespace geopm
{
    class Comm;
    class ServiceProxy;

    class ApplicationIO
    {
        public:
            ApplicationIO() = default;
            virtual ~ApplicationIO() = default;
            /// @brief Connect to the application via
            ///        shared memory.
            virtual void connect(void) = 0;
            /// @brief Returns true if the application has indicated
            ///        it is shutting down.
            virtual bool do_shutdown(void) = 0;
            /// @brief Returns the path to the report file.
            virtual std::string report_name(void) const = 0;
            /// @brief Returns the profile name to be used in the
            ///        report.
            virtual std::string profile_name(void) const = 0;
            /// @brief Returns the set of region names recorded by the
            ///        application.
            virtual std::set<std::string> region_name_set(void) const = 0;
            /// @brief Signal to the application that the Controller
            ///        is ready to begin receiving samples.
            virtual void controller_ready(void) = 0;
            /// @brief Signal to the application that the Controller
            ///        has failed critically.
            virtual void abort(void) = 0;
    };

    class ApplicationSampler;

    class ApplicationIOImp : public ApplicationIO
    {
        public:
            ApplicationIOImp();
            ApplicationIOImp(ApplicationSampler &application_sampler,
                             std::shared_ptr<ServiceProxy> service_proxy,
                             const std::string &profile_name,
                             const std::string &report_name,
                             int timeout);
            virtual ~ApplicationIOImp();
            void connect(void) override;
            bool do_shutdown(void) override;
            std::string report_name(void) const override;
            std::string profile_name(void) const override;
            std::set<std::string> region_name_set(void) const override;
            void controller_ready(void) override;
            void abort(void) override;
        private:
            std::set<int> get_profile_pids(void);
            static constexpr size_t M_SHMEM_REGION_SIZE = 2*1024*1024;

            bool m_is_connected;
            ApplicationSampler &m_application_sampler;
            std::shared_ptr<ServiceProxy> m_service_proxy;
            const std::string m_profile_name;
            const std::string m_report_name;
            const int m_timeout;
            const bool m_do_profile;
            std::set<int> m_profile_pids;
    };
}

#endif
