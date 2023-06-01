/*
 * Copyright (c) 2015 - 2023, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef BATCHSERVERCONFIG_HPP_INCLUDE
#define BATCHSERVERCONFIG_HPP_INCLUDE

#include <memory>
#include <vector>
#include <string>

struct geopm_request_s;

namespace geopm
{
    class PlatformTopo;

    /// @brief Class that enables the creation of a batch server
    ///
    /// This is a helper class that is used to configure geopmbatch
    /// command line tool.  Configurations can be serialized for input
    /// to the geopmbatch command line tool.
    ///
    /// The JSON format for the data structure is a list of maps.
    /// Each map represents a geopm_request_s structure by mapping a
    /// string naming the structure field to the value.  An additional
    /// field determines if the request is a read or write request.
    /// An example JSON string follows
    ///
    ///     [{"name": "MSR::PERF_CTL:FREQ",
    ///       "domain_type": 2,
    ///       "domain_idx": 0,
    ///       "do_write": true},
    ///      {"name": "MSR::PERF_CTL:FREQ",
    ///       "domain_type": 2,
    ///       "domain_idx": 1,
    ///       "do_write": false}]
    ///
    class BatchServerConfig
    {
        public:
            BatchServerConfig() = default;
            virtual ~BatchServerConfig() = default;
            /// @brief Create a unique pointer to BatchServerConfig object
            ///        from read and write requests
            ///
            /// This method enables the construction when the user
            /// wants explicit control of the request parameters.
            ///
            /// @param read_requests Vector of all read requests
            ///
            /// @param write_requests Vector of all write requests
            ///
            /// @return A unique pointer to an object that implements
            ///         the BatchServerConfig interface.
            static std::unique_ptr<BatchServerConfig> make_unique(const std::vector<geopm_request_s> &read_requests,
                                                                  const std::vector<geopm_request_s> &write_requests);
            /// @brief Create a unique pointer to BatchServerConfig object
            ///        from a JSON formatted string
            ///
            /// @param json_string [in] A JSON representation of a vector
            ///                    of m_setting_s structures.
            ///
            /// @return A unique pointer to an object that implements
            ///         the BatchServerConfig interface.
            static std::unique_ptr<BatchServerConfig> make_unique(const std::string &json_string);
            /// @brief Get saved control settings JSON
            ///
            /// @return A JSON representation of a vector of
            ///         m_setting_s structures
            virtual std::string json(void) const = 0;
            /// @brief Get read and write requests
            ///
            /// @return Pair of vectors, first is read requests,
            ///         second is write requests.
            virtual std::pair<std::vector<geopm_request_s>, std::vector<geopm_request_s> > requests(void) const = 0;
            /// @brief Write the JSON formatted configuration to a file
            ///
            /// Writes the string to the specified output file.  The
            /// file is overwritten if it already exists.  An
            /// exception is raised if the directory containing the
            /// output does not exist, or if the file cannot be
            /// created for any other reason.
            ///
            /// @param save_path [in] The file path where the JSON
            ///                  string is written.
            virtual void write_json(const std::string &save_path) const = 0;
    };

    class BatchServerConfigImp : public BatchServerConfig
    {
        public:
            BatchServerConfigImp(const std::vector<geopm_request_s> &read_requests,
                                 const std::vector<geopm_request_s> &write_requests);
            BatchServerConfigImp(const std::string &json_string);
            BatchServerConfigImp(const PlatformTopo &topo);
            virtual ~BatchServerConfigImp() = default;
            std::string json(void) const override;
            std::pair<std::vector<geopm_request_s>, std::vector<geopm_request_s> > requests(void) const override;
            void write_json(const std::string &save_path) const override;

            static std::string json(const std::vector<geopm_request_s> &read_requests,
                                 const std::vector<geopm_request_s> &write_requests);
            static std::pair<std::vector<geopm_request_s>, std::vector<geopm_request_s> > requests(const std::string &json_string);
        private:
            const std::vector<geopm_request_s> m_read_requests;
            const std::vector<geopm_request_s> m_write_requests;
            const std::string m_json;
    };
}

#endif
