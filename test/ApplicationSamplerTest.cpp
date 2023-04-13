/*
 * Copyright (c) 2015 - 2023, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <memory>

#include "gtest/gtest.h"
#include "gmock/gmock.h"

#include "ApplicationSamplerImp.hpp"
#include "MockApplicationRecordLog.hpp"
#include "MockRecordFilter.hpp"
#include "MockApplicationStatus.hpp"
#include "MockPlatformTopo.hpp"
#include "MockScheduler.hpp"
#include "record.hpp"
#include "geopm_prof.h"
#include "geopm_hint.h"
#include "geopm_hash.h"
#include "geopm_test.hpp"
#include "config.h"

using testing::_;
using testing::Return;
using testing::SetArgReferee;
using testing::DoAll;
using geopm::ApplicationSampler;
using geopm::ApplicationSamplerImp;
using geopm::record_s;
using geopm::short_region_s;
using geopm::RecordFilter;
using geopm::ApplicationRecordLog;


class ApplicationSamplerTest : public ::testing::Test
{
    protected:
        void SetUp();
        std::shared_ptr<ApplicationSamplerImp> m_app_sampler;
        std::map<int, ApplicationSamplerImp::m_process_s> m_process_map;
        std::shared_ptr<MockRecordFilter> m_filter_0;
        std::shared_ptr<MockRecordFilter> m_filter_1;
        std::shared_ptr<MockApplicationRecordLog> m_record_log_0;
        std::shared_ptr<MockApplicationRecordLog> m_record_log_1;
        std::shared_ptr<MockApplicationStatus> m_mock_status;
        int m_num_cpu;
        std::unique_ptr<MockPlatformTopo> m_mock_topo;
        std::shared_ptr<MockScheduler> m_scheduler;
        std::map<int, std::set<int> > m_client_cpu_map;
};

void ApplicationSamplerTest::SetUp()
{
    m_filter_0 = std::make_shared<MockRecordFilter>();
    m_filter_1 = std::make_shared<MockRecordFilter>();
    m_record_log_0 = std::make_shared<MockApplicationRecordLog>();
    m_record_log_1 = std::make_shared<MockApplicationRecordLog>();
    m_mock_status = std::make_shared<MockApplicationStatus>();
    m_num_cpu = 4;
    m_scheduler = std::make_shared<MockScheduler>();
    m_client_cpu_map[0] = {0};
    m_client_cpu_map[234] = {1};
    EXPECT_CALL(*m_scheduler, num_cpu())
       .WillRepeatedly(Return(m_num_cpu));
    EXPECT_CALL(*m_scheduler, proc_cpuset(0))
       .WillRepeatedly([](){return geopm::make_cpu_set(4, {0});});
    EXPECT_CALL(*m_scheduler, proc_cpuset(234))
       .WillRepeatedly([](){return geopm::make_cpu_set(4, {1});});

    m_process_map[0].filter = m_filter_0;
    m_process_map[0].record_log = m_record_log_0;
    m_process_map[234].filter = m_filter_1;
    m_process_map[234].record_log = m_record_log_1;
    std::vector<bool> is_active {true, true, false, false};
    m_mock_topo = geopm::make_unique<MockPlatformTopo>();
    EXPECT_CALL(*m_mock_topo, num_domain(GEOPM_DOMAIN_CPU))
        .WillOnce(Return(m_num_cpu));

    m_app_sampler = std::make_shared<ApplicationSamplerImp>(m_mock_status,
                                                            *m_mock_topo,
                                                            m_process_map,
                                                            false,
                                                            "",
                                                            is_active,
                                                            true,
                                                            "profile_name",
                                                            m_client_cpu_map,
                                                            m_scheduler);
}

TEST_F(ApplicationSamplerTest, one_enter_exit)
{
    uint64_t region_hash = 0xabcdULL;
    std::vector<record_s> message_buffer {
    //  time            process    event                      signal
        {{{10, 0}},     0,         geopm::EVENT_REGION_ENTRY, region_hash},
        {{{11, 0}},     0,         geopm::EVENT_REGION_EXIT,  region_hash},
    };
    std::vector<record_s> empty_message_buffer;
    std::vector<short_region_s> empty_short_region_buffer;
    EXPECT_CALL(*m_record_log_0, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(message_buffer),
                        SetArgReferee<1>(empty_short_region_buffer)));
    EXPECT_CALL(*m_record_log_1, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                        SetArgReferee<1>(empty_short_region_buffer)));
    EXPECT_CALL(*m_mock_status, get_hint(_))
        .WillRepeatedly(Return(GEOPM_REGION_HINT_UNKNOWN));
    EXPECT_CALL(*m_mock_status, update_cache());
    m_app_sampler->update({{1, 0}});
    std::vector<struct record_s> result {
         m_app_sampler->get_records()
    };

    ASSERT_EQ(2U, result.size());

    EXPECT_EQ(10, result[0].time.t.tv_sec);
    EXPECT_EQ(0, result[0].time.t.tv_nsec);
    EXPECT_EQ(0, result[0].process);
    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, result[0].event);
    EXPECT_EQ(region_hash, result[0].signal);

    EXPECT_EQ(11.0, result[1].time.t.tv_sec);
    EXPECT_EQ(0, result[1].time.t.tv_nsec);
    EXPECT_EQ(0, result[1].process);
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, result[1].event);
    EXPECT_EQ(region_hash, result[1].signal);
}

TEST_F(ApplicationSamplerTest, one_enter_exit_two_ranks)
{
    uint64_t region_hash = 0xabcdULL;
    std::vector<record_s> message_buffer_0 {
    //  time            process    event                      signal
        {{{10, 0}},     0,         geopm::EVENT_REGION_ENTRY, region_hash},
        {{{11, 0}},     0,         geopm::EVENT_REGION_EXIT,  region_hash},
    };
    std::vector<record_s> message_buffer_1 {
    //   time                   process      event                      signal
        {{{10, 500000000}},     234,         geopm::EVENT_REGION_ENTRY, region_hash},
        {{{11, 500000000}},     234,         geopm::EVENT_REGION_EXIT,  region_hash},
    };

    std::vector<short_region_s> empty_short_region_buffer;
    EXPECT_CALL(*m_record_log_0, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(message_buffer_0),
                        SetArgReferee<1>(empty_short_region_buffer)));
    EXPECT_CALL(*m_record_log_1, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(message_buffer_1),
                        SetArgReferee<1>(empty_short_region_buffer)));
    EXPECT_CALL(*m_mock_status, update_cache());
    EXPECT_CALL(*m_mock_status, get_hint(_))
        .WillRepeatedly(Return(GEOPM_REGION_HINT_UNKNOWN));
    m_app_sampler->update({{1, 0}});
    std::vector<struct record_s> result {
         m_app_sampler->get_records()
    };

    ASSERT_EQ(4U, result.size());

    EXPECT_EQ(10, result[0].time.t.tv_sec);
    EXPECT_EQ(0, result[0].time.t.tv_nsec);
    EXPECT_EQ(0, result[0].process);
    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, result[0].event);
    EXPECT_EQ(region_hash, result[0].signal);

    EXPECT_EQ(11, result[1].time.t.tv_sec);
    EXPECT_EQ(0, result[1].time.t.tv_nsec);
    EXPECT_EQ(0, result[1].process);
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, result[1].event);
    EXPECT_EQ(region_hash, result[1].signal);

    EXPECT_EQ(10, result[2].time.t.tv_sec);
    EXPECT_EQ(500000000, result[2].time.t.tv_nsec);
    EXPECT_EQ(234, result[2].process);
    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, result[2].event);
    EXPECT_EQ(region_hash, result[2].signal);

    EXPECT_EQ(11, result[3].time.t.tv_sec);
    EXPECT_EQ(500000000, result[2].time.t.tv_nsec);
    EXPECT_EQ(234, result[3].process);
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, result[3].event);
    EXPECT_EQ(region_hash, result[3].signal);
}

TEST_F(ApplicationSamplerTest, with_epoch)
{
    uint64_t region_hash_0 = 0xabcdULL;
    uint64_t region_hash_1 = 0x1234ULL;

    std::vector<record_s> message_buffer_0 {
    //   time           process      event                      signal
        {{{10, 0}},     0,           geopm::EVENT_REGION_ENTRY, region_hash_0},
        {{{11, 0}},     0,           geopm::EVENT_EPOCH_COUNT,  1},
        {{{12, 0}},     0,           geopm::EVENT_REGION_EXIT, region_hash_0},
        {{{13, 0}},     0,           geopm::EVENT_REGION_ENTRY, region_hash_1},
        {{{14, 0}},     0,           geopm::EVENT_EPOCH_COUNT, 2},
        {{{15, 0}},     0,           geopm::EVENT_REGION_EXIT, region_hash_1},
    };

    std::vector<record_s> message_buffer_1 {
    //   time                   process      event                      signal
        {{{10, 500000000}},     234,         geopm::EVENT_REGION_ENTRY, region_hash_0},
        {{{11, 500000000}},     234,         geopm::EVENT_EPOCH_COUNT,  1},
        {{{12, 500000000}},     234,         geopm::EVENT_REGION_EXIT, region_hash_0},
        {{{13, 500000000}},     234,         geopm::EVENT_REGION_ENTRY, region_hash_1},
        {{{14, 500000000}},     234,         geopm::EVENT_EPOCH_COUNT, 2},
        {{{15, 500000000}},     234,         geopm::EVENT_REGION_EXIT, region_hash_1},
    };

    std::vector<short_region_s> empty_short_region_buffer;
    EXPECT_CALL(*m_record_log_0, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(message_buffer_0),
                        SetArgReferee<1>(empty_short_region_buffer)));
    EXPECT_CALL(*m_record_log_1, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(message_buffer_1),
                        SetArgReferee<1>(empty_short_region_buffer)));
    EXPECT_CALL(*m_mock_status, update_cache());
    EXPECT_CALL(*m_mock_status, get_hint(_))
        .WillRepeatedly(Return(GEOPM_REGION_HINT_UNKNOWN));
    m_app_sampler->update({{1, 0}});
    std::vector<struct record_s> result {
         m_app_sampler->get_records()
    };

    ASSERT_EQ(12U, result.size());

    EXPECT_EQ(10, result[0].time.t.tv_sec);
    EXPECT_EQ(0, result[0].time.t.tv_nsec);
    EXPECT_EQ(0, result[0].process);
    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, result[0].event);
    EXPECT_EQ(region_hash_0, result[0].signal);

    EXPECT_EQ(11, result[1].time.t.tv_sec);
    EXPECT_EQ(0, result[1].time.t.tv_nsec);
    EXPECT_EQ(0, result[1].process);
    EXPECT_EQ(geopm::EVENT_EPOCH_COUNT, result[1].event);
    EXPECT_EQ(1U, result[1].signal);

    EXPECT_EQ(12, result[2].time.t.tv_sec);
    EXPECT_EQ(0, result[2].time.t.tv_nsec);
    EXPECT_EQ(0, result[2].process);
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, result[2].event);
    EXPECT_EQ(region_hash_0, result[2].signal);

    EXPECT_EQ(13, result[3].time.t.tv_sec);
    EXPECT_EQ(0, result[3].time.t.tv_nsec);
    EXPECT_EQ(0, result[3].process);
    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, result[3].event);
    EXPECT_EQ(region_hash_1, result[3].signal);

    EXPECT_EQ(14, result[4].time.t.tv_sec);
    EXPECT_EQ(0, result[4].time.t.tv_nsec);
    EXPECT_EQ(0, result[4].process);
    EXPECT_EQ(geopm::EVENT_EPOCH_COUNT, result[4].event);
    EXPECT_EQ(2U, result[4].signal);

    EXPECT_EQ(15, result[5].time.t.tv_sec);
    EXPECT_EQ(0, result[5].time.t.tv_nsec);
    EXPECT_EQ(0, result[5].process);
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, result[5].event);
    EXPECT_EQ(region_hash_1, result[5].signal);

    EXPECT_EQ(10, result[6].time.t.tv_sec);
    EXPECT_EQ(500000000, result[6].time.t.tv_nsec);
    EXPECT_EQ(234, result[6].process);
    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, result[6].event);
    EXPECT_EQ(region_hash_0, result[6].signal);

    EXPECT_EQ(11, result[7].time.t.tv_sec);
    EXPECT_EQ(500000000, result[7].time.t.tv_nsec);
    EXPECT_EQ(234, result[7].process);
    EXPECT_EQ(geopm::EVENT_EPOCH_COUNT, result[7].event);
    EXPECT_EQ(1U, result[7].signal);

    EXPECT_EQ(12, result[8].time.t.tv_sec);
    EXPECT_EQ(500000000, result[8].time.t.tv_nsec);
    EXPECT_EQ(234, result[8].process);
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, result[8].event);
    EXPECT_EQ(region_hash_0, result[8].signal);

    EXPECT_EQ(13, result[9].time.t.tv_sec);
    EXPECT_EQ(500000000, result[9].time.t.tv_nsec);
    EXPECT_EQ(234, result[9].process);
    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, result[9].event);
    EXPECT_EQ(region_hash_1, result[9].signal);

    EXPECT_EQ(14, result[10].time.t.tv_sec);
    EXPECT_EQ(500000000, result[10].time.t.tv_nsec);
    EXPECT_EQ(234, result[10].process);
    EXPECT_EQ(geopm::EVENT_EPOCH_COUNT, result[10].event);
    EXPECT_EQ(2U, result[10].signal);

    EXPECT_EQ(15, result[11].time.t.tv_sec);
    EXPECT_EQ(500000000, result[11].time.t.tv_nsec);
    EXPECT_EQ(234, result[11].process);
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, result[11].event);
    EXPECT_EQ(region_hash_1, result[11].signal);
}

TEST_F(ApplicationSamplerTest, string_conversion)
{
    EXPECT_EQ("REGION_ENTRY", geopm::event_name(geopm::EVENT_REGION_ENTRY));
    EXPECT_EQ("REGION_EXIT", geopm::event_name(geopm::EVENT_REGION_EXIT));
    EXPECT_EQ("EPOCH_COUNT", geopm::event_name(geopm::EVENT_EPOCH_COUNT));

    EXPECT_EQ(geopm::EVENT_REGION_ENTRY, geopm::event_type("REGION_ENTRY"));
    EXPECT_EQ(geopm::EVENT_REGION_EXIT, geopm::event_type("REGION_EXIT"));
    EXPECT_EQ(geopm::EVENT_EPOCH_COUNT, geopm::event_type("EPOCH_COUNT"));

    EXPECT_THROW(geopm::event_name(99), geopm::Exception);
    EXPECT_THROW(geopm::event_type("INVALID"), geopm::Exception);
}

TEST_F(ApplicationSamplerTest, short_regions)
{
    uint64_t region_hash_0 = 0xabcdULL;
    uint64_t region_hash_1 = 0x1234ULL;
    std::vector<record_s> message_buffer_0 {
    //   time    process    event                      signal
        {{{10, 0}},     0,         geopm::EVENT_SHORT_REGION, 0},
    };
    std::vector<record_s> message_buffer_1 {
        {{{11, 0}},     234,       geopm::EVENT_SHORT_REGION, 0},
    };
    std::vector<short_region_s> short_region_buffer_0 {
    //   hash           num_complete, total_time
        {region_hash_0, 3,             1.0}
    };
    std::vector<short_region_s> short_region_buffer_1 {
    //   hash           num_complete, total_time
        {region_hash_1, 4,            1.1}
    };
    EXPECT_CALL(*m_record_log_0, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(message_buffer_0),
                        SetArgReferee<1>(short_region_buffer_0)));
    EXPECT_CALL(*m_record_log_1, dump(_, _))
        .WillOnce(DoAll(SetArgReferee<0>(message_buffer_1),
                        SetArgReferee<1>(short_region_buffer_1)));
    EXPECT_CALL(*m_mock_status, update_cache());
    EXPECT_CALL(*m_mock_status, get_hint(_))
        .WillRepeatedly(Return(GEOPM_REGION_HINT_UNKNOWN));
    m_app_sampler->update({{1, 0}});
    std::vector<struct record_s> records {
        m_app_sampler->get_records()
    };

    ASSERT_EQ(2U, records.size());

    EXPECT_EQ(10, records[0].time.t.tv_sec);
    EXPECT_EQ(0, records[0].time.t.tv_nsec);
    EXPECT_EQ(0, records[0].process);
    EXPECT_EQ(geopm::EVENT_SHORT_REGION, records[0].event);
    EXPECT_EQ(0ULL, records[0].signal);

    EXPECT_EQ(11, records[1].time.t.tv_sec);
    EXPECT_EQ(0, records[1].time.t.tv_nsec);
    EXPECT_EQ(234, records[1].process);
    EXPECT_EQ(geopm::EVENT_SHORT_REGION, records[1].event);
    EXPECT_EQ(1ULL, records[1].signal);

    std::vector<struct short_region_s> short_regions {
        m_app_sampler->get_short_region(0),
        m_app_sampler->get_short_region(1),
    };

    EXPECT_EQ(region_hash_0, short_regions[0].hash);
    EXPECT_EQ(region_hash_1, short_regions[1].hash);
    EXPECT_EQ(3, short_regions[0].num_complete);
    EXPECT_EQ(4, short_regions[1].num_complete);
    EXPECT_EQ(1.0, short_regions[0].total_time);
    EXPECT_EQ(1.1, short_regions[1].total_time);

    GEOPM_EXPECT_THROW_MESSAGE(m_app_sampler->get_short_region(3),
                               GEOPM_ERROR_INVALID,
                               "event_signal does not match any short region handle");
}

TEST_F(ApplicationSamplerTest, hash)
{
    uint64_t region_a = 0xAAAA;
    uint64_t region_b = 0xBBBB;
    EXPECT_CALL(*m_mock_status, get_hash(0))
        .WillOnce(Return(region_a));
    EXPECT_CALL(*m_mock_status, get_hash(1))
        .WillOnce(Return(region_b));
    uint64_t hash = m_app_sampler->cpu_region_hash(0);
    EXPECT_EQ(region_a, hash);
    hash = m_app_sampler->cpu_region_hash(1);
    EXPECT_EQ(region_b, hash);
}

TEST_F(ApplicationSamplerTest, hint)
{
    EXPECT_CALL(*m_mock_status, get_hint(0))
        .WillOnce(Return(GEOPM_REGION_HINT_COMPUTE));
    uint64_t hint = m_app_sampler->cpu_hint(0);
    EXPECT_EQ(GEOPM_REGION_HINT_COMPUTE, hint);
    EXPECT_CALL(*m_mock_status, get_hint(1))
        .WillOnce(Return(GEOPM_REGION_HINT_MEMORY));
    hint = m_app_sampler->cpu_hint(1);
    EXPECT_EQ(GEOPM_REGION_HINT_MEMORY, hint);
}

TEST_F(ApplicationSamplerTest, hint_time)
{
    double compute_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(0.0, compute_time);
    double network_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(0.0, network_time);
    double memory_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    compute_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(0.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(0.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    std::vector<record_s> empty_message_buffer;
    std::vector<short_region_s> empty_short_region_buffer;
    {
        EXPECT_CALL(*m_record_log_0, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_record_log_1, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_mock_status, update_cache());
        EXPECT_CALL(*m_mock_status, get_hint(_))
            .WillOnce(Return(GEOPM_REGION_HINT_NETWORK))
            .WillOnce(Return(GEOPM_REGION_HINT_COMPUTE));
        m_app_sampler->update({{1, 0}});
    }
    compute_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(0.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(0.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    compute_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(0.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(0.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    {
        EXPECT_CALL(*m_record_log_0, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_record_log_1, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_mock_status, update_cache());
        EXPECT_CALL(*m_mock_status, get_hint(_))
            .WillOnce(Return(GEOPM_REGION_HINT_NETWORK))
            .WillOnce(Return(GEOPM_REGION_HINT_MEMORY));
        m_app_sampler->update({{2, 0}});
    }
    compute_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(0.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(1.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    compute_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(1.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(0.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    {
        EXPECT_CALL(*m_record_log_0, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_record_log_1, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_mock_status, update_cache());
        EXPECT_CALL(*m_mock_status, get_hint(_))
            .WillOnce(Return(GEOPM_REGION_HINT_COMPUTE))
            .WillOnce(Return(GEOPM_REGION_HINT_NETWORK));
        m_app_sampler->update({{4, 0}});
    }
    compute_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(0.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(3.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    compute_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(1.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(0.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(2.0, memory_time);
    {
        EXPECT_CALL(*m_record_log_0, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_record_log_1, dump(_, _))
            .WillOnce(DoAll(SetArgReferee<0>(empty_message_buffer),
                            SetArgReferee<1>(empty_short_region_buffer)));
        EXPECT_CALL(*m_mock_status, update_cache());
        EXPECT_CALL(*m_mock_status, get_hint(_))
            .WillOnce(Return(GEOPM_REGION_HINT_UNSET))
            .WillOnce(Return(GEOPM_REGION_HINT_UNSET));
        m_app_sampler->update({{7, 0}});
    }
    compute_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(3.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(3.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(0, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(0.0, memory_time);
    compute_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_COMPUTE);
    EXPECT_EQ(1.0, compute_time);
    network_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_NETWORK);
    EXPECT_EQ(3.0, network_time);
    memory_time = m_app_sampler->cpu_hint_time(1, GEOPM_REGION_HINT_MEMORY);
    EXPECT_EQ(2.0, memory_time);
}

TEST_F(ApplicationSamplerTest, cpu_progress)
{
    double expected = 0.75;
    EXPECT_CALL(*m_mock_status, get_progress_cpu(1))
        .WillOnce(Return(expected));
    EXPECT_EQ(expected, m_app_sampler->cpu_progress(1));
}

TEST_F(ApplicationSamplerTest, sampler_cpu)
{
    // The model for this test is a system with two cores and four
    // CPUs.  The first core has CPUs 0 and 1 and the second core has
    // CPUs 2 and 3.  CPU's 0 and 1 are active and CPU's 2 and 3 are
    // inactive.

    // The topo is queried to discover the total number of cores
    EXPECT_CALL(*m_mock_topo, num_domain(GEOPM_DOMAIN_CORE))
        .WillOnce(Return(2));
    // The topo is queried to discover the core of every active CPU
    EXPECT_CALL(*m_mock_topo, domain_idx(GEOPM_DOMAIN_CORE, 0))
        .WillOnce(Return(0));
    EXPECT_CALL(*m_mock_topo, domain_idx(GEOPM_DOMAIN_CORE, 1))
        .WillOnce(Return(0));
#ifdef GEOPM_DEBUG
    // In the case of debug builds, an additional call is performed
    // to see if we're sharing a core with the OS
    EXPECT_CALL(*m_mock_topo, domain_idx(GEOPM_DOMAIN_CORE, 3))
        .WillOnce(Return(0));
#endif
    // Since core 1 has no active CPU's the topo is queried for the
    // CPUs associated with core 1 (which are CPU 2 and 3)
    std::set<int> core_cpu = {2, 3};
    EXPECT_CALL(*m_mock_topo, domain_nested(GEOPM_DOMAIN_CPU,
                                            GEOPM_DOMAIN_CORE, 1))
        .WillOnce(Return(core_cpu));
    // The sampler should pick the last CPU on the last unused core
    // which is CPU 3
    EXPECT_EQ(3, m_app_sampler->sampler_cpu());

    // Check that make_cpu_set() as it would be called in connect() in
    // this example creates a cpu_set_t that has all but the third bit
    // set to zero
    std::set<int> enabled_cpu = {2};
    auto cpu_set = geopm::make_cpu_set(4, enabled_cpu);
    EXPECT_EQ(0, CPU_ISSET(0, cpu_set.get()));
    EXPECT_EQ(0, CPU_ISSET(1, cpu_set.get()));
    EXPECT_EQ(1, CPU_ISSET(2, cpu_set.get()));
    EXPECT_EQ(0, CPU_ISSET(3, cpu_set.get()));
}
