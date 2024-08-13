/*
 * Copyright (c) 2015 - 2024 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */


#include "StatsCollector.hpp"

#include <memory>

#include "geopm/Helper.hpp"
#include "geopm_test.hpp"
#include "MockPlatformIO.hpp"


using geopm::StatsCollector;
using testing::Return;

class StatsCollectorTest : public ::testing::Test
{
    protected:
        void SetUp();
        std::shared_ptr<MockPlatformIO> m_pio_mock;
};

void StatsCollectorTest::SetUp()
{
    m_pio_mock = std::make_shared<MockPlatformIO>();
}

/// @brief test report generation with no updates
TEST_F(StatsCollectorTest, empty_report)
{
    std::vector<geopm_request_s> req;
    EXPECT_CALL(*m_pio_mock, push_signal("TIME", 0, 0))
        .WillOnce(Return(0));
    auto coll = StatsCollector(req, *m_pio_mock);
    std::string report = coll.report_yaml();
    std::vector<std::string> expected_begin = {
        "host",
        "sample-time-first",
        "sample-time-total",
        "sample-period-mean",
        "sample-period-std",
        "metrics",
    };
    auto eb_it = expected_begin.begin();
    for (const auto &line : geopm::string_split(report, "\n")) {
        if (eb_it == expected_begin.end()) {
            break;
        }
        auto line_split = geopm::string_split(line, ":");
        EXPECT_EQ(*eb_it, line_split[0]);
        ++eb_it;
    }
}

/// @brief Create two reports with a restart between
TEST_F(StatsCollectorTest, time_report)
{
    int pio_idx = 3;
    EXPECT_CALL(*m_pio_mock, push_signal("TIME", 0, 0))
        .WillOnce(Return(pio_idx))
        .WillOnce(Return(pio_idx));
    EXPECT_CALL(*m_pio_mock, read_signal("TIME", 0, 0))
        .WillOnce(Return(0.0))
        .WillOnce(Return(1.0));
    EXPECT_CALL(*m_pio_mock, sample(pio_idx))
        .WillOnce(Return(0.0))
        .WillOnce(Return(0.0))
        .WillOnce(Return(1.0))
        .WillOnce(Return(1.0))
        .WillOnce(Return(0.0))
        .WillOnce(Return(0.0))
        .WillOnce(Return(1.0))
        .WillOnce(Return(1.0));
    std::vector<geopm_request_s> req {{0, 0, "TIME"}};
    auto coll = StatsCollector(req, *m_pio_mock);
    for (int reset_idx = 0; reset_idx < 2; ++reset_idx) {
        coll.update();
        coll.update();
        std::string report = coll.report_yaml();
        std::vector<std::string> expected_begin = {
            "host",
            "sample-time-first",
            "sample-time-total",
            "sample-period-mean",
            "sample-period-std",
            "metrics",
            "  TIME",
            "    count",
            "    first",
            "    last",
            "    min",
            "    max",
            "    mean-arithmetic",
            "    std",
        };
        auto eb_it = expected_begin.begin();
        for (const auto &line : geopm::string_split(report, "\n")) {
            if (eb_it == expected_begin.end()) {
                break;
            }
            auto line_split = geopm::string_split(line, ":");
            EXPECT_EQ(*eb_it, line_split[0]);
            ++eb_it;
        }
        EXPECT_NE(std::string::npos, report.find("count: 2\n"));
        EXPECT_NE(std::string::npos, report.find("first: 0\n"));
        EXPECT_NE(std::string::npos, report.find("last: 1\n"));
        EXPECT_NE(std::string::npos, report.find("min: 0\n"));
        EXPECT_NE(std::string::npos, report.find("max: 1\n"));
        EXPECT_NE(std::string::npos, report.find("mean-arithmetic: 0.5\n"));
        EXPECT_NE(std::string::npos, report.find("std: 0.707107\n"));
        coll.reset();
    }
}
