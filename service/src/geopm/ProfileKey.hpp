/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef PROFILESHMEM_HPP_INCLUDE
#define PROFILESHMEM_HPP_INCLUDE

#include <string>
#include <memory>
#include "geopm_pio.h"

namespace geopm
{
    class ProfileKey
    {
        public:
            static constexpr size_t M_RECORD_LOG_BUFFER_SIZE = 49192;
            static constexpr size_t M_CONTROL_MESSAGE_BUFFER_SIZE = 4026;

            static std::unique_ptr<ProfileKey> make_unique(const std::string &name);
            ProfileKey() = default;
            virtual ~ProfileKey() = default;
            virtual std::string key_path(int key_type) const = 0;
            virtual std::string key_path(int key_type, int pid) const = 0;
            virtual size_t key_size(int key_type) const = 0;
    };

    class ProfileKeyImp : public ProfileKey
    {
        public:
            ProfileKeyImp(const std::string &name);
            ProfileKeyImp(const std::string &name, int num_cpu,
                          const std::string &base_path);
            virtual ~ProfileKeyImp() = default;
            std::string key_path(int key_type) const override;
            std::string key_path(int key_type, int pid) const override;
            size_t key_size(int key_type) const override;
        private:
            const std::string m_profile_name;
            const int m_num_cpu;
            const std::string m_base_path;
    };
}

#endif
