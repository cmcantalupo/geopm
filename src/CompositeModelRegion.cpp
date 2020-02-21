/*
 * Copyright (c) 2015, 2016, 2017, 2018, 2019, 2020, Intel Corporation
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY LOG OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "CompositeModelRegion.hpp"

#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include <algorithm>

#include "geopm.h"
#include "geopm_time.h"
#include "Exception.hpp"
#include "Helper.hpp"

namespace geopm
{
    const std::string CompositeModelRegion::M_REGION_DELIM = ",";
    const std::string CompositeModelRegion::M_BIG_O_DELIM = ":";
    CompositeModelRegion::CompositeModelRegion(const std::string &name,
                                           double big_o_in,
                                           int verbosity,
                                           bool do_imbalance,
                                           bool do_progress,
                                           bool do_unmarked)
        : ModelRegion(name, GEOPM_REGION_HINT_UNKNOWN, verbosity)
    {
        m_do_imbalance = do_imbalance;
        m_do_progress = do_progress;
        m_do_unmarked = do_unmarked;
        auto sub_region_names = geopm::string_split(name, M_REGION_DELIM);
        // TODO need composite_end and loop_end to support nested composites and loops
        for (const auto &sub_region_name_big_o : sub_region_names) {
            if (sub_region_name_big_o == "composite" ||
                sub_region_name_big_o == "loop") {
                continue;
            }
            else {
                auto split = geopm::string_split(sub_region_name_big_o, M_BIG_O_DELIM);
                if (split.size() == 2) {
                    auto region_name = split[0].c_str();
                    auto region_big_o = std::atoi(split[1].c_str());
                    m_regions.push_back(ModelRegion::model_region(region_name, region_big_o, verbosity));
                }
                else {
                    // throw
                }
            }
        }
    }

    void CompositeModelRegion::big_o(double big_o_in)
    {
    }

    void CompositeModelRegion::run(void)
    {
        ModelRegion::region_enter();
        for(const auto &region : m_regions) {
            region->run();
        }
        ModelRegion::region_exit();
    }

    LoopModelRegion::LoopModelRegion(const std::string &name,
                                     double big_o_in,
                                     int verbosity,
                                     bool do_imbalance,
                                     bool do_progress,
                                     bool do_unmarked)
        : CompositeModelRegion(name, big_o_in, verbosity, do_imbalance, do_progress, do_unmarked)
    {
        big_o(big_o_in);
    }

    void LoopModelRegion::big_o(double big_o_in)
    {
        m_big_o = big_o_in;
    }

    void LoopModelRegion::run(void)
    {
        // important that region enter exit not called for this loop region type
        for (int x = 0; x < (int) m_big_o; ++x) {
            for(const auto &region : m_regions) {
                region->run();
            }
        }
    }
}
