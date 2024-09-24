#!/usr/bin/env python3
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

import sys
from argparse import ArgumentParser
from geopmdpy import pio
from geopmdpy import stats
from geopmdpy.loop import TimedLoop
from prometheus_client import start_http_server, Gauge

class PrometheusUpdater:
    def __init__(self, stats_collector):
        self._stats_collector = stats_collector
        self._metric_names, self._metric_data = self._stats_collector.report_table()
        self._num_fresh = len(self._metric_names)
        self._is_fresh = self._num_fresh * [True]
        self._gauges = [Gauge(metric_name.replace('-', '_'), metric_name) for metric_name in self._metric_names]
        for metric_idx, gg in enumerate(self._gauges):
            gg.set_function(lambda updater=self, metric_idx=metric_idx: updater.get_metric(metric_idx))

    def refresh(self):
        _, self._metric_data = self._stats_collector.report_table()
        self._stats_collector.reset()
        self._num_fresh = len(self._metric_names)
        self._is_fresh = self._num_fresh * [True]

    def metric_names(self):
        return list(self._metric_names)

    def get_metric(self, metric_idx):
        if self._num_fresh == 0:
            self.refresh()
        if self._is_fresh[metric_idx]:
            self._num_fresh -= 1
            self._is_fresh[metric_idx] = False
        return self._metric_data[metric_idx]

def main(period, port):
    """Prometheus exporter for GEOPM power, energy, frequency and temperature metrics

    """
    include_strings = ["POWER", "ENERGY", "FREQ", "TEMP"]
    exclude_strings = ["::", "CONTROL", "MAX", "MIN", "STEP", "LIMIT", "STICKER"]
    all_signals = pio.signal_names()
    requests = []
    for sig in all_signals:
        if (not any(nn in sig for nn in exclude_strings)
            and any(nn in sig for nn in include_strings)):
            requests.append((sig, 0, 0))
    if len(requests) == 0:
        print("Failed to find any signals to report", file=sys.stderr)

    with stats.Collector(requests) as stats_collector:
        updater = PrometheusUpdater(stats_collector)
        start_http_server(port)
        for sample_idx in TimedLoop(period):
            pio.read_batch()
            stats_collector.update()

if __name__ == '__main__':
    parser = ArgumentParser(description=main.__doc__)
    parser.add_argument('-t', '--period', dest='period', type=float, default=0.1,
                        help='Sample period for fast loop in seconds. Default: %(default)s')
    parser.add_argument('-p', '--port', dest='port', type=int, default=8000,
                        help='Port to publish Prometheus metrics. Default: %(default)s')

    args = parser.parse_args()
    main(args.period, args.port)
