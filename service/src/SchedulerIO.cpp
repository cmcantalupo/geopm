/*
 * Copyright (c) 2015 - 2024, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "config.h"

#include "SchedulerIO.hpp"

#include <map>
#include <sstream>
#include <cstring>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "geopm/Exception.hpp"
#include "geopm/PlatformTopo.hpp"
#include "UniqueFd.hpp"
#include "IOUring.hpp"


namespace geopm
{
    class SchedulerIOImp : public SchedulerIO
    {
        public:
            SchedulerIOImp();
            SchedulerIOImp(int num_cpu,
                           std::shared_ptr<IOUring> batch_reader);
            virtual ~SchedulerIOImp() = default;
            void watch_pid(int pid) override;
            void update(void) override;
            int get_cpu(int pid) const override;
            int get_pid(int cpu) const override;
        private:
            static constexpr size_t M_BUFFER_SIZE = 1024;
            struct pid_info_s {
                int cpu;
                UniqueFd fd;
                std::shared_ptr<int> return_val;
                std::vector<char> buffer;
                pid_info_s(int cc, UniqueFd ff, std::shared_ptr<int> rv, std::vector<char> buf)
                    : cpu(cc)
                    , fd(std::move(ff))
                    , return_val(std::move(rv))
                    , buffer(std::move(buf)) {}
                ~pid_info_s() = default;
            };
            std::shared_ptr<IOUring> m_batch_reader;
            const int m_num_cpu;
            bool m_is_updated;
            std::vector<int> m_per_cpu_pid;
            std::map<int, pid_info_s> m_pid_info_map;
    };

    std::unique_ptr<SchedulerIO> SchedulerIO::make_unique()
    {
        return std::make_unique<SchedulerIOImp>();
    }


    SchedulerIOImp::SchedulerIOImp()
        : SchedulerIOImp(platform_topo().num_domain(GEOPM_DOMAIN_CPU), nullptr)
    {

    }

    SchedulerIOImp::SchedulerIOImp(int num_cpu,
                                   std::shared_ptr<IOUring> batch_reader)
        : m_batch_reader(std::move(batch_reader))
        , m_num_cpu(num_cpu)
        , m_is_updated(false)
        , m_per_cpu_pid(m_num_cpu, -1)
    {

    }

    void SchedulerIOImp::watch_pid(int pid)
    {
        if (m_is_updated) {
            throw geopm::Exception("SchedulerIOImp::watch_pid(): Cannot call watch_pid after update()",
                                   GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        std::ostringstream path;
        path << "/proc/" << pid << "/stat"; // 39th entry is last CPU executed
        const auto &element = m_pid_info_map.try_emplace(pid, -1, std::move(UniqueFd(open(path.str().c_str(), O_RDONLY))),
                                                         std::make_shared<int>(-1), std::vector<char>(M_BUFFER_SIZE,'\0'));
        if (element.first->second.fd.get() == -1) {
            throw geopm::Exception("SchedulerIOImp::watch_pid(): PID not active: " + std::to_string(pid),
                                   GEOPM_ERROR_RUNTIME, __FILE__, __LINE__);
        }
    }

    void SchedulerIOImp::update(void)
    {
        if (m_pid_info_map.empty()) {
            return;
        }
        if (m_batch_reader == nullptr) {
            m_batch_reader = IOUring::make_unique(m_pid_info_map.size());
        }
        for (auto &it : m_pid_info_map) {
            m_batch_reader->prep_read(
                it.second.return_val, it.second.fd.get(), &(it.second.buffer.front()), it.second.buffer.size(), 0);
        }
        m_batch_reader->submit();
        for (auto &it : m_pid_info_map) {
            int pid = it.first;
            int ret = *(it.second.return_val);
            if (ret == -1 || ret >= static_cast<int>(M_BUFFER_SIZE)) {
                throw geopm::Exception("SchedulerIOImp::update(): Unable to read /proc/" + std::to_string(pid) + "/stat",
                                       GEOPM_ERROR_RUNTIME, __FILE__, __LINE__);
            }
            it.second.buffer[ret] = '\0';
            char *buff_ptr = &(it.second.buffer.front());
            // (39) processor  %d  CPU number last executed on.
            int cpu_col = 39;
            for (int col = 0; buff_ptr != nullptr && col < cpu_col; ++col) {
                buff_ptr = std::strtok(buff_ptr, " ");
            }
            geopm::Exception parse_ex("SchedulerIOImp::update(): Unable to parse /proc/" + std::to_string(pid) + "/stat",
                                      GEOPM_ERROR_RUNTIME, __FILE__, __LINE__);
            if (buff_ptr == nullptr) {
                throw parse_ex;
            }
            try {
                it.second.cpu = std::stoi(buff_ptr);
            }
            catch (std::invalid_argument const& ex) {
                throw parse_ex;
            }
            catch (std::out_of_range const& ex) {
                throw parse_ex;
            }
            if (it.second.cpu < 0 ||
                it.second.cpu >= m_num_cpu) {
                throw parse_ex;
            }
            m_per_cpu_pid.at(it.second.cpu) = pid;
        }
        m_is_updated = true;
    }

    int SchedulerIOImp::get_cpu(int pid) const
    {
        int result = -1;
        const auto it = m_pid_info_map.find(pid);
        if (it != m_pid_info_map.end()) {
            result = it->second.cpu;
        }
        return result;
    }

    int SchedulerIOImp::get_pid(int cpu) const
    {
        if (cpu < 0 || cpu >= static_cast<int>(m_per_cpu_pid.size())) {
            throw geopm::Exception("SchedulerIOImp::get_pid(): cpu is out of range: " + std::to_string(cpu),
                                   GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        return m_per_cpu_pid[cpu];
    }
}
