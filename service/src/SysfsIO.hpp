/*
 * Copyright (c) 2015 - 2022, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SYSFSIO_HPP_INCLUDE
#define SYSFSIO_HPP_INCLUDE

#include <string>
#include <memory>

namespace geopm
{
    /// @brief Class used to implement the SysfsIOGroup base class
    ///
    /// This virtual interface can be adapted for each Linux device
    /// driver.  A concrete implementation can be used to construct a
    /// SysfsIOGroup object.
    class SysfsIO
    {
        public:
            /// @brief The metadata about a signal or control
            struct metadata_s {
                int id, // Unique identifier
                int domain, // native domain geopm_domain_e
                int units, // IOGroup::m_units_e
                int behavior, // IOGroup::m_signal_behavior_e
                int aggregation, // Agg::m_type_e
                double factor, // SI unit conversion factor
                std::string name, // The full low level signal name
                std::string descrption, // Long description
                std::string alias, // Either empty string or name of high level alias
            };
            SysfsIO() = default;
            virtual ~SysfsIO() = default;
            /// @brief Get supported signal names.
            ///
            /// @return Vector of all supported signals
            virtual std::vector<std::string> signal_names(void) const = 0;
            /// @brief Get supported control names.
            ///
            /// @return Vector of all supported controls
            virtual std::vector<std::string> control_names(void) const = 0;
            /// @brief Get the path to the sysfs entry for signal.
            ///
            /// @param [in] signal_name The name of the signal
            ///
            /// @param [in] domain_type One of the values from the
            ///        geopm_domain_e enum described in geopm_topo.h
            ///
            /// @param [in] domain_idx The index of the domain within
            ///        the set of domains of the same type on the
            ///        platform.
            ///
            /// @return File path to the sysfs entry to be read.
            virtual std::string signal_path(const std::string &signal_name,
                                            int domain_type,
                                            int domain_idx) = 0;
            /// @brief Get the path to the sysfs entry for control.
            ///
            /// @param [in] control_name The name of the control.
            ///
            /// @param [in] domain_type One of the values from the
            ///        geopm_domain_e enum described in geopm_topo.h
            ///
            /// @param [in] domain_idx The index of the domain within
            ///        the set of domains of the same type on the
            ///        platform.
            ///
            /// @return File path to the sysfs entry to be written.
            virtual std::string control_path(const std::string &control_name,
                                             int domain_type,
                                             int domain_idx) const = 0;
            /// @brief Convert contents of sysfs file into signal
            ///
            /// This parsing includes the conversion of the numerical
            /// data into SI units.
            ///
            /// @param [in] signal_name The name of the signal.
            ///
            /// @param [in] content The string content read from the
            ///        sysfs file.
            ///
            /// @return The parsed signal value in SI units.
            virtual double signal_parse(const std::string &signal_name,
                                        const std::string &content) const = 0;
            /// @brief Convert a control into a sysfs string
            ///
            /// Converts from the SI unit control into the text
            /// representation required by the device driver.
            ///
            /// @param [in] control_name The name of the control.
            ///
            /// @param [in] setting The control setting in SI units.
            ///
            /// @return String content to be written to sysfs file.
            virtual std::string control_gen(const std::string &control_name,
                                            double setting) const = 0;
            /// @brief Convert contents of sysfs file into signal
            ///
            /// This parsing includes the conversion of the numerical
            /// data into SI units.
            ///
            /// @param [in] metadata_id The unique identifier of the signal.
            ///
            /// @param [in] content The string content read from the
            ///        sysfs file.
            ///
            /// @return The parsed signal value in SI units.
            virtual double signal_parse(int metadata_id,
                                        const std::string &content) const = 0;
            /// @brief Convert a control into a sysfs string
            ///
            /// Converts from the SI unit control into the text
            /// representation required by the device driver.
            ///
            /// @param [in] metadata_id The unique identifier of the control.
            ///
            /// @param [in] setting The control setting in SI units.
            ///
            /// @return String content to be written to sysfs file.
            virtual std::string control_gen(int metadata_id,
                                            double setting) const = 0;
            /// Name of the Linux kernel device driver
            ///
            /// @return Name of device driver
            virtual std::string driver(void) const = 0;
            /// Query the meta data about a signal or control
            virtual struct metadata_s metadata(const std::string &name) const = 0;
            /// Get all of the meta data in JSON format.
            virtual std::string metadata_json(void) const = 0;
    };
}

#endif
