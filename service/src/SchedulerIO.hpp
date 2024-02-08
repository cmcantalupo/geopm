/*
 * Copyright (c) 2015 - 2024, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SCHEDULERIO_HPP_INCLUDE
#define SCHEDULERIO_HPP_INCLUDE

#include <memory>

namespace geopm
{
    class SchedulerIO
    {
        public:
            static std::unique_ptr<SchedulerIO> make_unique();
            SchedulerIO() = default;
            virtual ~SchedulerIO() = default;
            virtual void watch_pid(int pid) = 0;
            virtual void update(void) = 0;
            virtual int get_cpu(int pid) const = 0;
            virtual int get_pid(int cpu) const = 0;
    };
}

#endif
