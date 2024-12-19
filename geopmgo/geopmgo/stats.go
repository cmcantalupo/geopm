// Copyright (c) 2015 - 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//

package geopmgo

/*
#cgo LDFLAGS: -lgeopmd
#include <geopm_stats_collector.h>
#include <stdlib.h>
*/
import "C"

import (
    "errors"
    "fmt"
    "unsafe"
)

// Sample and Metric constants
const (
    SampleTimeTotal       = C.GEOPM_SAMPLE_TIME_TOTAL
    SampleCount           = C.GEOPM_SAMPLE_COUNT
    SamplePeriodMean      = C.GEOPM_SAMPLE_PERIOD_MEAN
    SamplePeriodStd       = C.GEOPM_SAMPLE_PERIOD_STD
    NumSampleStats        = C.GEOPM_NUM_SAMPLE_STATS
    MetricCount           = C.GEOPM_METRIC_COUNT
    MetricFirst           = C.GEOPM_METRIC_FIRST
    MetricLast            = C.GEOPM_METRIC_LAST
    MetricMin             = C.GEOPM_METRIC_MIN
    MetricMax             = C.GEOPM_METRIC_MAX
    MetricMean            = C.GEOPM_METRIC_MEAN
    MetricStd             = C.GEOPM_METRIC_STD
    NumMetricStats        = C.GEOPM_NUM_METRIC_STATS
)



// Collector is an object for aggregating statistics gathered from the PlatformIO interface of GEOPM.
type Collector struct {
    collectorPtr *C.struct_geopm_stats_collector_s
    numSignal    int
}

// NewCollector creates a new stats collector.
func NewCollector(signalConfig []GeopmRequest) (*Collector, error) {
    numSignal := len(signalConfig)
    if numSignal == 0 {
        return nil, errors.New("Collector creation failed: length of input is zero")
    }

    signalConfigCArray := C.malloc(C.size_t(numSignal) * C.size_t(unsafe.Sizeof(C.struct_geopm_request_s{})))
    configArr := (*[1 << 30]C.struct_geopm_request_s)(signalConfigCArray)[:numSignal:numSignal]
    for i, req := range signalConfig {
        configArr[i].domain_type = C.int(req.DomainType)
        configArr[i].domain_idx = C.int(req.DomainIdx)
        configArr[i].name = C.CString(req.Name)
        defer C.free(unsafe.Pointer(configArr[i].name))
    }

    collectorPtr := C.malloc(C.size_t(unsafe.Sizeof(uintptr(0))))
    defer C.free(collectorPtr)

    err := C.geopm_stats_collector_create(C.uint(numSignal), (*C.struct_geopm_request_s)(signalConfigCArray), (**C.struct_geopm_stats_collector_s)(collectorPtr))
    if err < 0 {
        return nil, errors.New("geopm_stats_collector_create() failed")
    }

    return &Collector{
        collectorPtr: *(**C.struct_geopm_stats_collector_s)(collectorPtr),
        numSignal:    numSignal,
    }, nil
}

// Close frees all resources by deleting the StatsCollector.
func (c *Collector) Close() {
    if c.collectorPtr != nil {
        C.geopm_stats_collector_free(c.collectorPtr)
        c.collectorPtr = nil
    }
}

// Update updates the collector with new values.
func (c *Collector) Update() error {
    if c.collectorPtr == nil {
        return errors.New("called Collector.Update() after calling Collector.Close()")
    }
    err := C.geopm_stats_collector_update(c.collectorPtr)
    if err < 0 {
        return errors.New("geopm_stats_collector_update() failed")
    }
    return nil
}

// UpdateCount gets the number of updates since last reset.
func (c *Collector) UpdateCount() (uint, error) {
    if c.collectorPtr == nil {
        return 0, errors.New("called Collector.UpdateCount() after calling Collector.Close()")
    }
    result := C.malloc(C.size_t(unsafe.Sizeof(uintptr(0))))
    defer C.free(result)

    err := C.geopm_stats_collector_update_count(c.collectorPtr, (*C.size_t)(result))
    if err < 0 {
        return 0, errors.New("geopm_stats_collector_update_count() failed")
    }
    return uint(*(*C.size_t)(result)), nil
}

// ReportYaml creates a YAML report of the collected statistics.
func (c *Collector) ReportYaml() (string, error) {
    if c.collectorPtr == nil {
        return "", errors.New("called Collector.ReportYaml() after calling Collector.Close()")
    }
    reportMax := C.malloc(C.size_t(unsafe.Sizeof(uintptr(0))))
    defer C.free(reportMax)

    C.geopm_stats_collector_report_yaml(c.collectorPtr, (*C.size_t)(reportMax), nil)
    reportCStr := C.malloc(C.size_t(*(*C.size_t)(reportMax)))
    defer C.free(reportCStr)

    err := C.geopm_stats_collector_report_yaml(c.collectorPtr, (*C.size_t)(reportMax), (*C.char)(reportCStr))
    if err < 0 {
        return "", errors.New("geopm_stats_collector_report_yaml() failed")
    }
    return C.GoString((*C.char)(reportCStr)), nil
}

// Report creates a report object of the collected statistics.
func (c *Collector) Report() (map[string]interface{}, error) {
    if c.collectorPtr == nil {
        return nil, errors.New("called Collector.Report() after calling Collector.Close()")
    }

    reportPtr := C.malloc(C.size_t(unsafe.Sizeof(C.struct_geopm_report_s{})))
    defer C.free(reportPtr)

    metricStats := C.malloc(C.size_t(c.numSignal) * C.size_t(unsafe.Sizeof(C.struct_geopm_metric_stats_s{})))
    defer C.free(metricStats)

    (*C.struct_geopm_report_s)(reportPtr).metric_stats = (*C.struct_geopm_metric_stats_s)(metricStats)

    err := C.geopm_stats_collector_report(c.collectorPtr, C.uint(c.numSignal), (*C.struct_geopm_report_s)(reportPtr))
    if err < 0 {
        return nil, errors.New("geopm_stats_collector_report() failed")
    }

    result := make(map[string]interface{})
    result["host"] = C.GoString(&(*C.struct_geopm_report_s)(reportPtr).host[0])
    result["sample-time-first"] = C.GoString(&(*C.struct_geopm_report_s)(reportPtr).sample_time_first[0])
    result["sample-time-total"] = float64((*C.struct_geopm_report_s)(reportPtr).sample_stats[SampleTimeTotal])
    result["sample-count"] = int((*C.struct_geopm_report_s)(reportPtr).sample_stats[SampleCount])
    result["sample-period-mean"] = float64((*C.struct_geopm_report_s)(reportPtr).sample_stats[SamplePeriodMean])
    result["sample-period-std"] = float64((*C.struct_geopm_report_s)(reportPtr).sample_stats[SamplePeriodStd])
    result["metrics"] = make(map[string]map[string]interface{})

    for i := 0; i < int((*C.struct_geopm_report_s)(reportPtr).num_metric); i++ {
        metricName := C.GoString(&(*C.struct_geopm_report_s)(reportPtr).metric_stats[i].name[0])
        result["metrics"].(map[string]map[string]interface{})[metricName] = map[string]interface{}{
            "count": int((*C.struct_geopm_report_s)(reportPtr).metric_stats[i].stats[MetricCount]),
            "first": float64((*C.struct_geopm_report_s)(reportPtr).metric_stats[i].stats[MetricFirst]),
            "last":  float64((*C.struct_geopm_report_s)(reportPtr).metric_stats[i].stats[MetricLast]),
            "min":   float64((*C.struct_geopm_report_s)(reportPtr).metric_stats[i].stats[MetricMin]),
            "max":   float64((*C.struct_geopm_report_s)(reportPtr).metric_stats[i].stats[MetricMax]),
            "mean":  float64((*C.struct_geopm_report_s)(reportPtr).metric_stats[i].stats[MetricMean]),
            "std":   float64((*C.struct_geopm_report_s)(reportPtr).metric_stats[i].stats[MetricStd]),
        }
    }

    return result, nil
}

// ReportCSV creates a CSV string of the collected statistics.
func (c *Collector) ReportCSV(delimiter string, printHeader bool) (string, error) {
    header, data, err := c.ReportTable()
    if err != nil {
        return "", err
    }

    headerStr := make([]string, len(header))
    for i, h := range header {
        headerStr[i] = fmt.Sprintf("\"%s\"", h)
    }
    dataStr := make([]string, len(data))
    for i, d := range data {
        switch v := d.(type) {
        case string:
            dataStr[i] = fmt.Sprintf("\"%s\"", v)
        default:
            dataStr[i] = fmt.Sprintf("%v", v)
        }
    }

    result := []string{}
    if printHeader {
        result = append(result, fmt.Sprintf("%s", delimiter, headerStr))
    }
    result = append(result, fmt.Sprintf("%s", delimiter, dataStr))
    return fmt.Sprintf("%s\n", result), nil
}

// ReportTable creates a report in tabular data format.
func (c *Collector) ReportTable() ([]string, []interface{}, error) {
    report, err := c.Report()
    if err != nil {
        return nil, nil, err
    }
    header := []string{"host", "sample-time-first", "sample-time-total", "sample-count", "sample-period-mean", "sample-period-std"}
    data := []interface{}{report["host"], report["sample-time-first"], report["sample-time-total"], report["sample-count"], report["sample-period-mean"], report["sample-period-std"]}

    metricStatNames := []string{"count", "first", "last", "min", "max", "mean", "std"}
    for metricName := range report["metrics"].(map[string]map[string]interface{}) {
        for _, statName := range metricStatNames {
            header = append(header, fmt.Sprintf("%s-%s", metricName, statName))
            data = append(data, report["metrics"].(map[string]map[string]interface{})[metricName][statName])
        }
    }
    return header, data, nil
}

// Reset zeroes all statistics gathered by the collector.
func (c *Collector) Reset() error {
    if c.collectorPtr == nil {
        return errors.New("called Collector.Reset() after calling Collector.Close()")
    }
    err := C.geopm_stats_collector_reset(c.collectorPtr)
    if err < 0 {
        return errors.New("geopm_stats_collector_reset() failed")
    }
    return nil
}
