/*
 * Copyright (c) 2015 - 2024, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef GEOPM_IMBALANCER_H_INCLUDE
#define GEOPM_IMBALANCER_H_INCLUDE

#include "geopm_public.h"
#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Used to set a delay frac that will sleep for the given fraction
    ///        of the region runtime.
    int GEOPM_PUBLIC
        geopm_imbalancer_frac(double frac);
    /// @brief Sets the entry time for the imbalanced region.
    int GEOPM_PUBLIC
        geopm_imbalancer_enter(void);
    /// @brief Spins until the region has been extended by the previously specified delay.
    int GEOPM_PUBLIC
        geopm_imbalancer_exit(void);

#ifdef __cplusplus
}
#endif
#endif
