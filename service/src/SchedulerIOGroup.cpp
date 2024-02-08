/*
 * Copyright (c) 2015 - 2024, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "config.h"

#include "SchedulerIOGroup.hpp"

#include <cmath>
#include <climits>
#include <cstring>
#include <unistd.h>
#include "geopm/Agg.hpp"
#include "geopm/ServiceProxy.hpp"
#include "BatchClient.hpp"
#include "geopm/Helper.hpp"
#include "geopm/PlatformTopo.hpp"
#include "geopm/PlatformIO.hpp"
#include "geopm_debug.hpp"

namespace geopm
{

    const std::string SchedulerIOGroup::M_PLUGIN_NAME = "SERVICE";

    SchedulerIOGroup::SchedulerIOGroup()
        : SchedulerIOGroup(platform_topo(),
                           ServiceProxy::make_unique())
    {

    }

    SchedulerIOGroup::SchedulerIOGroup(const PlatformTopo &platform_topo,
                                       std::shared_ptr<ServiceProxy> service_proxy)
        : m_platform_topo(platform_topo)
        , m_service_proxy(std::move(service_proxy))
        , m_signal_names({"SCHEDULER::PID", "PID"})
        , m_control_names({"SCHEDULER::RESET"})
    {
        m_service_proxy->platform_open_session();
        m_session_pid = getpid();
    }

    SchedulerIOGroup::~SchedulerIOGroup()
    {
        if (m_session_pid == getpid()) {
            m_service_proxy->platform_close_session();
        }
    }

    std::set<std::string> SchedlulerIOGroup::signal_names(void) const
    {
        return m_signal_names;
    }

    std::set<std::string> SchedlulerIOGroup::control_names(void) const
    {
        return m_control_names;
    }

    bool SchedlulerIOGroup::is_valid_signal(const std::string &signal_name) const
    {
        return (m_signal_names.find(signal_name) != m_signal_names.end());
    }

    bool SchedlulerIOGroup::is_valid_control(const std::string &control_name) const
    {
        return (m_control_names.find(control_name) != m_control_names.end());
    }

    int SchedlulerIOGroup::signal_domain_type(const std::string &signal_name) const
    {
        int result = GEOPM_DOMAIN_INVALID;
        auto it = m_signal_info.find(signal_name);
        if (it != m_signal_info.end()) {
            result = GEOPM_DOMAIN_CPU;
        }
        return result;
    }

    int SchedlulerIOGroup::control_domain_type(const std::string &control_name) const
    {
        int result = GEOPM_DOMAIN_INVALID;
        auto it = m_control_info.find(control_name);
        if (it != m_control_info.end()) {
            result = GEOPM_DOMAIN_CPU;
        }
        return result;
    }

    int SchedlulerIOGroup::push_signal(const std::string &signal_name,
                                       int domain_type,
                                       int domain_idx)
    {
        if (!is_valid_signal(signal_name)) {
            throw Exception("SchedlulerIOGroup::push_signal(): signal name \"" +
                            signal_name + "\" not found",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (domain_type != signal_domain_type(signal_name)) {
            throw Exception("SchedlulerIOGroup::push_signal(): domain_type requested does not match the domain of the signal (" + signal_name + ").",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (domain_idx < 0 || domain_idx >= m_platform_topo.num_domain(domain_type)) {
            throw Exception("SchedlulerIOGroup::push_signal(): domain_idx out of range",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        m_cpu_requests.push_back(domain_idx);
        return m_cpu_requests.size() - 1;
    }

    int SchedlulerIOGroup::push_control(const std::string &control_name,
                                        int domain_type,
                                        int domain_idx)
    {
        throw Exception("SchedlulerIOGroup::push_control(): not supported",
                        GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        return -1;
    }

    void SchedlulerIOGroup::read_batch(void)
    {

    }

    void SchedlulerIOGroup::write_batch(void)
    {

    }

    double SchedlulerIOGroup::sample(int sample_idx)
    {
        if (m_signal_requests.size() == 0) {
            throw Exception("SchedlulerIOGroup::sample() called prior to any calls to push_signal()",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (m_batch_samples.size() == 0) {
            throw Exception("SchedlulerIOGroup::sample() called prior to any calls to read_batch()",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (sample_idx < 0 || (unsigned)sample_idx >= m_batch_samples.size()) {
            throw Exception("SchedlulerIOGroup::sample() called with parameter that was not returned by push_signal()",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        return m_batch_samples[sample_idx];
    }

    void SchedlulerIOGroup::adjust(int control_idx,
                                   double setting)
    {
        throw Exception("SchedlulerIOGroup::push_control()/adjust(): not supported",
                        GEOPM_ERROR_INVALID, __FILE__, __LINE__);

    }

    double SchedlulerIOGroup::read_signal(const std::string &signal_name,
                                          int domain_type,
                                          int domain_idx)
    {
        if (!is_valid_signal(signal_name)) {
            throw Exception("SchedlulerIOGroup::read_signal(): signal name \"" +
                            signal_name + "\" not found",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (domain_type != signal_domain_type(signal_name)) {
            throw Exception("SchedlulerIOGroup::read_signal(): domain_type requested does not match the domain of the signal (" + signal_name + ").",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (domain_idx < 0 || domain_idx >= m_platform_topo.num_domain(domain_type)) {
            throw Exception("SchedlulerIOGroup::read_signal(): domain_idx out of range",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        return ;
    }

    void SchedlulerIOGroup::write_control(const std::string &control_name,
                                          int domain_type,
                                          int domain_idx,
                                          double setting)
    {
        if (!is_valid_control(control_name)) {
            throw Exception("SchedlulerIOGroup::write_control(): control name \"" +
                            control_name + "\" not found",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (domain_type != control_domain_type(control_name)) {
            throw Exception("SchedlulerIOGroup::write_control(): domain_type does not match the domain of the control.",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        if (domain_idx < 0 || domain_idx >= m_platform_topo.num_domain(domain_type)) {
            throw Exception("SchedlulerIOGroup::write_control(): domain_idx out of range",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
    }

    void SchedlulerIOGroup::save_control(void)
    {

    }

    void SchedlulerIOGroup::restore_control(void)
    {

    }

    std::function<double(const std::vector<double> &)> SchedlulerIOGroup::agg_function(const std::string &signal_name) const
    {
        return Agg::expect_same;
    }

    std::function<std::string(double)> SchedlulerIOGroup::format_function(const std::string &signal_name) const
    {
        auto it = m_signal_info.find(signal_name);
        if (it == m_signal_info.end()) {
            throw Exception("SchedlulerIOGroup::signal_behavior(): signal_name " + signal_name +
                            " not valid for SchedlulerIOGroup",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        return string_format_integer;
    }

    std::string SchedlulerIOGroup::signal_description(const std::string &signal_name) const
    {
        auto it = m_signal_info.find(signal_name);
        if (it == m_signal_info.end()) {
            throw Exception("SchedlulerIOGroup::signal_behavior(): signal_name " + signal_name +
                            " not valid for SchedlulerIOGroup",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        return "The tracked PID running on the CPU or NAN if no tracked PID is running on the CPU";
    }

    std::string SchedlulerIOGroup::control_description(const std::string &control_name) const
    {
        auto it = m_control_info.find(control_name);
        if (it == m_control_info.end()) {
            throw Exception("SchedlulerIOGroup::control_behavior(): control_name " + control_name +
                            " not valid for SchedlulerIOGroup",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        return "Query the GEOPM Service to update the list of tracked PIDs";
    }

    int SchedlulerIOGroup::signal_behavior(const std::string &signal_name) const
    {
        return GEOPM_
        auto it = m_signal_info.find(signal_name);
        if (it == m_signal_info.end()) {
            throw Exception("SchedlulerIOGroup::signal_behavior(): signal_name " + signal_name +
                            " not valid for SchedlulerIOGroup",
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        return M_SIGNAL_BEHAVIOR_LABEL;
    }

    void SchedlulerIOGroup::save_control(const std::string &save_path)
    {

    }

    void SchedlulerIOGroup::restore_control(const std::string &save_path)
    {

    }

    std::string SchedlulerIOGroup::strip_plugin_name(const std::string &name)
    {
        static const std::string key = M_PLUGIN_NAME + "::";
        static const size_t key_len = key.size();
        std::string result = name;
        if (string_begins_with(name, key)) {
            result = name.substr(key_len);
        }
        return result;
    }

    std::string SchedlulerIOGroup::name(void) const
    {
        return plugin_name();
    }

    std::string SchedlulerIOGroup::plugin_name(void)
    {
        return M_PLUGIN_NAME;
    }

    std::unique_ptr<IOGroup> SchedlulerIOGroup::make_plugin(void)
    {
        return geopm::make_unique<SchedlulerIOGroup>();
    }
}
