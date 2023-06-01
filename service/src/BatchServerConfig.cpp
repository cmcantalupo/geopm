/*
 * Copyright (c) 2015 - 2023, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "config.h"

#include "BatchServerConfig.hpp"

#include <cstring>

#include "geopm/json11.hpp"
#include "geopm/Helper.hpp"
#include "geopm/Exception.hpp"
#include "geopm/PlatformTopo.hpp"
#include "geopm/PlatformIO.hpp"

using json11::Json;

namespace geopm
{
    std::unique_ptr<BatchServerConfig>
    BatchServerConfig::make_unique(const std::vector<geopm_request_s> &read_requests,
                                   const std::vector<geopm_request_s> &write_requests)
    {
        return geopm::make_unique<BatchServerConfigImp>(read_requests, write_requests);
    }

    std::unique_ptr<BatchServerConfig>
    BatchServerConfig::make_unique(const std::string &json_string)
    {
        return geopm::make_unique<BatchServerConfigImp>(json_string);
    }

    BatchServerConfigImp::BatchServerConfigImp(const std::vector<geopm_request_s> &read_requests,
                                               const std::vector<geopm_request_s> &write_requests)
        : m_read_requests(read_requests)
        , m_write_requests(write_requests)
    {

    }

    BatchServerConfigImp::BatchServerConfigImp(const std::string &json_string)
        : m_json(json_string)
    {

    }

    std::string BatchServerConfigImp::json(void) const
    {
        std::string result = m_json;
        if (result.empty()) {
            result = json(m_read_requests, m_write_requests);
        }
        return result;
    }

    std::pair<std::vector<geopm_request_s>, std::vector<geopm_request_s> >
        BatchServerConfigImp::requests(void) const
    {
        std::pair<std::vector<geopm_request_s>, std::vector<geopm_request_s> > result =
            {m_read_requests, m_write_requests};
        if (result.first.empty() && result.second.empty()) {
            result = requests(m_json);
        }
        return result;
    }


    std::string BatchServerConfigImp::json(const std::vector<geopm_request_s> &read_requests,
                                           const std::vector<geopm_request_s> &write_requests)
    {
        std::vector<std::map<std::string, Json> > json_requests;
        for (const auto &ss : read_requests) {
            json_requests.push_back({{"name", ss.name},
                                     {"domain_type", ss.domain_type},
                                     {"domain_idx", ss.domain_idx},
                                     {"is_write", false}});
        }
        for (const auto &ss : write_requests) {
            json_requests.push_back({{"name", ss.name},
                                     {"domain_type", ss.domain_type},
                                     {"domain_idx", ss.domain_idx},
                                     {"is_write", true}});
        }
        Json json_obj(json_requests);
        return json_obj.dump();
    }

    std::pair<std::vector<geopm_request_s>, std::vector<geopm_request_s> >
    BatchServerConfigImp::requests(const std::string &json_string)
    {
        std::pair<std::vector<geopm_request_s>, std::vector<geopm_request_s> > result;
        std::string err;
        Json root = Json::parse(json_string, err);
        if (!err.empty() || !root.is_array()) {
            throw Exception("BatchServerConfigImp::requests(): Expected a JSON array, unable to parse: " + err,
                            GEOPM_ERROR_INVALID, __FILE__, __LINE__);
        }
        for (const auto &jss : root.array_items()) {
            if (!jss.is_object()) {
                throw Exception("BatchServerConfigImp::requests(): Expected a JSON object, unable to parse",
                                GEOPM_ERROR_INVALID, __FILE__, __LINE__);
            }
            auto jss_map = jss.object_items();
            std::vector<std::string> required_keys = {"name",
                                                      "domain_type",
                                                      "domain_idx",
                                                      "is_write"};
            if (jss_map.size() != required_keys.size()) {
                throw Exception("BatchServerConfigImp::requests(): JSON object representing request must have four fields",
                                GEOPM_ERROR_INVALID, __FILE__, __LINE__);
            }
            for (const auto &rk : required_keys) {
                if (jss_map.count(rk) == 0) {
                    throw Exception("BatchServerConfigImp::requests(): Invalid requests object JSON, missing a required field: \"" + rk + "\"",
                                    GEOPM_ERROR_INVALID, __FILE__, __LINE__);
                }
            }
            geopm_request_s request = {jss["domain_type"].int_value(),
                                       jss["domain_idx"].int_value(),
                                       ""};
            size_t max_copy = sizeof(request.name);
            strncpy(request.name, jss["name"].string_value().c_str(), max_copy);
            if (request.name[max_copy - 1] != '\0') {
                throw Exception("BatchServerConfigImp::requests(): Request name too long: " + jss["name"].string_value(),
                                GEOPM_ERROR_INVALID, __FILE__, __LINE__);
            }
            if (jss["is_write"].bool_value()) {
                result.second.push_back(request);
            }
            else {
                result.first.push_back(request);
            }
        }
        return result;
    }

    void BatchServerConfigImp::write_json(const std::string &save_path) const
    {
        write_file(save_path, json());
    }
}
