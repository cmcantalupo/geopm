/*
 * Copyright (c) 2015 - 2023, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <sys/types.h>
#include <unistd.h>

pid_t setsid(void)
{
   return getsid(0);
}
