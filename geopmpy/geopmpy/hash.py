#
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#


from geopmdpy._libgeopmd import ffi, lib

# TODO: Should be part of geopm_hash.h in libgeopmd
ffi.cdef("""
uint64_t geopm_crc32_str(const char *key);
""")


def hash_str(key):
    """Return the geopm hash of a string

    Args:
        key (int): String to hash

    Returns:
        int: Hash of string

    """
    key_name_cstr = ffi.new("char[]", key.encode())
    return lib.geopm_crc32_str(key_name_cstr)
