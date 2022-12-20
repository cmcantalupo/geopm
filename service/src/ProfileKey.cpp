/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "config.h"
#include "geopm/ProfileKey.hpp"

#include <unistd.h>
#include <cstring>

#include "geopm/PlatformTopo.hpp"
#include "geopm/Helper.hpp"
#include "geopm/Exception.hpp"

namespace geopm
{

    ProfileKeyImp::ProfileKeyImp(const std::string &name)
        : ProfileKeyImp(name,
                        platform_topo().num_domain(GEOPM_DOMAIN_CPU),
                        "/dev/shm/geopm-shm-" + std::to_string(geteuid()))
    {

    }

    ProfileKeyImp::ProfileKeyImp(const std::string &name, int num_cpu,
                                 const std::string &base_path)
        : m_profile_name(name)
        , m_num_cpu(num_cpu)
        , m_base_path(base_path)
    {

    }

    std::unique_ptr<ProfileKey> ProfileKey::make_unique(const std::string &name)
    {
        return geopm::make_unique<ProfileKeyImp>(name);
    }


    std::string ProfileKeyImp::key_path(int key_type) const
    {
        std::string result;
        switch (key_type) {
            case GEOPM_PROFILE_KEY_TYPE_STATUS:
                result = m_base_path + "-status";
                break;
            case GEOPM_PROFILE_KEY_TYPE_CONTROL_MESSAGE:
                result = m_base_path + "-sample";
                break;
            case GEOPM_PROFILE_KEY_TYPE_RECORD_LOG:
                throw Exception("ProfileKeyImp::key_path(): Must specify pid parameter with the GEOPM_PROFILE_KEY_TYPE_RECORD_LOG type",
                                GEOPM_ERROR_INVALID, __FILE__, __LINE__);
                break;
            default:
                throw Exception("ProfileKeyImp::key_path(): Unknown key_type: " + std::to_string(key_type),
                                GEOPM_ERROR_INVALID, __FILE__, __LINE__);
                break;
        }
        return result;
    }

    std::string ProfileKeyImp::key_path(int key_type, int pid) const
    {
        std::string result;
        switch (key_type) {
            case GEOPM_PROFILE_KEY_TYPE_STATUS:
            case GEOPM_PROFILE_KEY_TYPE_CONTROL_MESSAGE:
                result = key_path(key_type);
                break;
            case GEOPM_PROFILE_KEY_TYPE_RECORD_LOG:
                result = m_base_path + "-record-log-" + std::to_string(pid);
                break;
            default:
                throw Exception("ProfileKeyImp::key_path(): Unknown key_type: " + std::to_string(key_type),
                                GEOPM_ERROR_INVALID, __FILE__, __LINE__);
                break;
        }
        return result;
    }

    size_t ProfileKeyImp::key_size(int key_type) const
    {
        size_t result = 0;
        switch (key_type) {
            case GEOPM_PROFILE_KEY_TYPE_STATUS:
                result = m_num_cpu * geopm::hardware_destructive_interference_size;
                break;
            case GEOPM_PROFILE_KEY_TYPE_CONTROL_MESSAGE:
                result = M_CONTROL_MESSAGE_BUFFER_SIZE;
                break;
            case GEOPM_PROFILE_KEY_TYPE_RECORD_LOG:
                result = M_RECORD_LOG_BUFFER_SIZE;
                break;
            default:
                throw Exception("ProfileKeyImp::key_size(): Unknown key_type: " + std::to_string(key_type),
                                GEOPM_ERROR_INVALID, __FILE__, __LINE__);
                break;
        }
        return result;
    }
}


int geopm_pio_profile_key(const char *profile_name,
                          int key_type,
                          int pid,
                          int key_path_max,
                          char *key_path,
                          size_t *key_size)
{
    int err = 0;
    try {
        auto profile_key = geopm::ProfileKey::make_unique(profile_name);
        std::string key_path_string = profile_key->key_path(key_type, pid);
        *key_size = profile_key->key_size(key_type);
        if ((size_t)key_path_max > key_path_string.size()) {
            strncpy(key_path, key_path_string.c_str(), key_path_max);
        }
        else {
            *key_path = '\0';
            throw geopm::Exception("geopm_profile_key(): key_path_max is too small",
                                   GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
    }
    catch (...) {
        err = geopm::exception_handler(std::current_exception(), true);
    }
    return err;
}
