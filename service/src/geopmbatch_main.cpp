/*
 * Copyright (c) 2015 - 2023, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <iostream>
#include <cstring>

#include "geopm/PlatformIO.hpp"
#include "BatchServerConfig.hpp"

int main(int argc, char **argv)
{
    int client_pid = 0;
    if (argc != 2 || strcmp("--help", argv[1]) == 0) {
        std::cerr << "Usage: " << argv[0] << " CLIENT_PID\n\n";
        return 0;
    }
    try {
        client_pid = std::stoi(argv[1]);
    }
    catch (const std::invalid_argument &ex) {
        std::cerr << "Invalid pid: " << argv[1] << "\n";
        return -1;
    }
    catch (const std::out_of_range &ex) {
        std::cerr << "Pid is out of range: " << argv[1] << "\n";
        return -1;
    }

    std::string json_str;
    std::getline(std::cin, json_str);
    auto server_config = geopm::BatchServerConfig::make_unique(json_str);
    auto requests = server_config->requests();
    int server_pid;
    std::string server_key;
    geopm::platform_io().start_batch_server(client_pid, requests.first, requests.second,
                                            server_pid, server_key);
    std::cout << server_pid << " " << server_key << "\n";
    return 0;
}
