/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "config.h"
#include "SysfsIO.hpp"


namespace geopm
{

    class CpufreqSysfsIO: public SysfsIO
    {
        public:
            CpufreqSysfsIO();
            CpufreqSysfsIO(const std::string base_path);
            virtual ~CpufreqSysfsIO() = default;
            std::vector<std::string> signal_names(void) override;
            std::vector<std::string> control_names(void) override;
            std::string signal_path(const std::string &signal_name,
                                    int domain_type,
                                    int domain_idx) const override;
            std::string control_path(const std::string &control_name,
                                     int domain_type,
                                     int domain_idx) const override;
            double signal_parse(const std::string &signal_name,
                                int domain_type,
                                int domain_idx,
                                const std::string &content) const override;
            std::string control_gen(const std::string &signal_name,
                                    int domain_type,
                                    int domain_idx,
                                    double setting) const override;
            std::string driver(void) const;
            struct metadata_s metadata(const std::string &name) const;
            struct std::string metadata_json(void) const;
        private:
            const std::string m_base_path;
            const std::string m_signal_prefix;
            const std::vector<std::string> m_signal_paths;
            const double m_factor;
            const std::map<std::string, m_metadata> m_metadata;

            std::string key_to_name(std::string key);
            std::string name_to_key(std::string name);
    }

    CpufreqSysfsIO::CpufreqSysfsIO()
        : CpufreqSysfsIO("/sys/bus/cpu/devices")
    {

    }

    CpufreqSysfsIO::CpufreqSysfsIO(const std::string base_path)
        : m_base_path(base_path)
        , m_signal_prefix("CPUFREQ::")
        , m_signal_paths {"base_frequency",
                          "cpuinfo_max_freq",
                          "cpuinfo_min_freq",
                          "cpuinfo_transition_latency",
                          "scaling_cur_freq",
                          "scaling_max_freq",
                          "scaling_min_freq",
                          "scaling_setspeed"}
        , m_factor(1e3) // in units of kHz
        , m_metadata {{"CPUFREQ::BASE_FREQUENCY",
                           {GEOPM_DOMAIN_CPU,
                            IOGroup::M_UNITS_HERTZ,
                            IOGroup::M_SIGNAL_BEHAVIOR_CONSTANT,
                            Agg:M_EXPECT_SAME,
                            "CPU base frequency",
                            "CPU_FREQUENCY_STICKER"}},
                      {"CPUFREQ::CPUINFO_MAX_FREQ",
                           {GEOPM_DOMAIN_CPU,
                            IOGroup::M_UNITS_HERTZ,
                            IOGroup::M_SIGNAL_BEHAVIOR_CONSTANT,
                            Agg:M_EXPECT_SAME,
                            "CPU maximum frequency",
                            "CPU_FREQUENCY_MAX_AVAIL"}},
                      {"CPUFREQ::CPUINFO_MIN_FREQ",
                           {GEOPM_DOMAIN_CPU,
                            IOGroup::M_UNITS_HERTZ,
                            IOGroup::M_SIGNAL_BEHAVIOR_CONSTANT,
                            Agg:M_EXPECT_SAME,
                            "CPU minimum frequency",
                            "CPU_FREQUENCY_MIN_AVAIL"}},
                      {"CPUFREQ::CPUINFO_TRANSITION_LATENCY",
                           {GEOPM_DOMAIN_CPU,
                            IOGroup::M_UNITS_SECONDS,
                            IOGroup::M_SIGNAL_BEHAVIOR_CONSTANT,
                            Agg:M_EXPECT_SAME,
                            "CPU frequency control transition latency",
                            ""}}} // TODO: Finish filling in the metadata
    {

    }

    std::string CpufreqSysfsIO::key_to_name(std::string key) const
    {
        std::tranform(key.begin(), key.end(), key.begin(), std::toupper);
        std::string name = m_signal_prefix + key;
        return result;
    }


    std::string CpufreqSysfsIO::name_to_key(std::string name) const
    {
        if (string_begins_with(name, m_signal_prefix)) {
            name = name.substring(m_signal_prefix.len());
        }
        std::tranform(name.begin(), name.end(), name.begin(), std::tolower);
        return result;
    }

    std::vector<std::string> CpufreqSysfsIO::signal_names(void) const
    {
        std::vector<std::string> result;
        for (const auto &path : m_signal_paths) {
            result.push_back(key_to_name(path));
        }
        return result;
    }

    std::vector<std::string> CpufreqSysfsIO::control_names(void) const
    {
        return {};
    }

    std::string CpufreqSysfsIO::signal_path(const std::string &signal_name,
                                             int domain_type,
                                             int domain_idx)
    {
        std::string key = name_to_key(signal_name);
        std::ostringstream path;
        path << m_base_path << "/cpu"  << domain_idx << "/" << key;
        return path.str(); 
    }

    std::string CpufreqSysfsIO::control_path(const std::string &control_name,
                                             int domain_type,
                                             int domain_idx)
    {
        return "";
    }

    double CpufreqSysfsIO::signal_parse(const std::string &signal_name,
                                        int domain_type,
                                        int domain_idx,
                                        const std::string &content) const
    {
        return m_factor * stod(content);
    }

    std::string CpufreqSysfsIO::control_gen(const std::string &signal_name,
                                            int domain_type,
                                            int domain_idx,
                                            double setting) const
    {
        return std::to_string((long(setting / m_factor));
    }

    struct metadata_s metadata(const std::string &name) const
    {
        auto meta_it = m_metadata.find(name);
        if (meta_id == m_metadata.end()) {
            throw Exception();
        }
        return meta_it.second
    }
}

#endif
