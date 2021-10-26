/*
 * Copyright (c) 2015 - 2021, Intel Corporation
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

#ifndef BATCHCLIENT_HPP_INCLUDE
#define BATCHCLIENT_HPP_INCLUDE

#include <memory>
#include <vector>
#include <signal.h>

struct geopm_request_s;

namespace geopm
{
    class SharedMemory;
    class BatchStatus;

    class BatchClient
    {
        public:
            BatchClient() = default;
            virtual ~BatchClient() = default;
            static std::unique_ptr<BatchClient> make_unique(const std::string &server_key,
                                                            int num_signal,
                                                            int num_control);
            virtual std::vector<double> read_batch(void) = 0;
            virtual void write_batch(std::vector<double> settings) = 0;
    };

    class BatchClientImp : public BatchClient
    {
        public:
            BatchClientImp(const std::string &server_key,
                           int num_signal, int num_control);
            BatchClientImp(int num_signal, int num_control,
                           std::shared_ptr<BatchStatus> batch_status,
                           std::shared_ptr<SharedMemory> signal_shmem,
                           std::shared_ptr<SharedMemory> control_shmem);
            virtual ~BatchClientImp() = default;
            std::vector<double> read_batch(void) override;
            void write_batch(std::vector<double> settings) override;
        private:
            int m_num_signal;
            int m_num_control;
            std::shared_ptr<BatchStatus> m_batch_status;
            std::shared_ptr<SharedMemory> m_signal_shmem;
            std::shared_ptr<SharedMemory> m_control_shmem;
    };
}

#endif
