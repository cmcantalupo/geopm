#!/usr/bin/env python3
#
#  Copyright (c) 2015 - 2023, Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

import unittest
import host_config
import os
import sys
class TestCombine(unittest.TestCase):

    def setUp(self):
        test_name = 'test_host_config'
        self.test_dir = test_name
        self.global_config_path = f'{test_name}_global.json'
        self.readme_path = f'{test_name}/README'
        mcfly1_config_path = f'{test_name}/mcfly1.json'
        mcfly2_config_path = f'{test_name}/mcfly2.json'
        mcfly3_config_path = f'{test_name}/mcfly3.json'
        self.all_paths = [self.global_config_path,
                          mcfly1_config_path,
                          mcfly2_config_path,
                          mcfly3_config_path]
        single_config = """
{
    "GPU_CORE_FREQUENCY_MAX": {
        "domain": "gpu",
        "description": "Defines the max core frequency to use for available GPUs",
        "units": "hertz",
        "aggregation": "average",
        "values": [1200, 1300, 1500]
    }
}
"""
        self.expected = """\
{
    "GPU_CORE_FREQUENCY_MAX": {
        "aggregation": "average",
        "description": "Defines the max core frequency to use for available GPUs",
        "domain": "gpu",
        "units": "hertz",
        "values": [
            1200,
            1300,
            1500
        ]
    },
    "GPU_CORE_FREQUENCY_MAX@mcfly1": {
        "aggregation": "average",
        "description": "Defines the max core frequency to use for available GPUs",
        "domain": "gpu",
        "units": "hertz",
        "values": [
            1200,
            1300,
            1500
        ]
    },
    "GPU_CORE_FREQUENCY_MAX@mcfly2": {
        "aggregation": "average",
        "description": "Defines the max core frequency to use for available GPUs",
        "domain": "gpu",
        "units": "hertz",
        "values": [
            1200,
            1300,
            1500
        ]
    },
    "GPU_CORE_FREQUENCY_MAX@mcfly3": {
        "aggregation": "average",
        "description": "Defines the max core frequency to use for available GPUs",
        "domain": "gpu",
        "units": "hertz",
        "values": [
            1200,
            1300,
            1500
        ]
    }
}\
"""
        readme = """
These files are populated for testing the host_config.py
"""
        os.mkdir(self.test_dir)
        for path in self.all_paths:
            with open(path, 'w') as fid:
                fid.write(single_config)
        with open(self.readme_path, 'w') as fid:
            fid.write(readme)

    def tearDown(self):
        os.unlink(self.readme_path)
        for path in self.all_paths:
            os.unlink(path)
        os.rmdir(self.test_dir)

    def test_combine(self):
        result = host_config.combine(self.test_dir, self.global_config_path)
        self.assertEqual(self.expected, result)


if __name__ == '__main__':
    unittest.main()
