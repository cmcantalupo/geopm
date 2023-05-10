#  Copyright (c) 2015 - 2023, Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

from dasbus.loop import EventLoop
from dasbus.connection import SystemMessageBus
from signal import signal
from signal import SIGTERM
from line_profiler import LineProfiler
from . import service

_bus = None
_loop = None

def term_handler(signum, frame):
    if signum == SIGTERM:
        stop()

def stop():
    global _bus
    if _bus is not None:
        _bus.disconnect()
        _bus = None
    if _loop is not None:
        _loop.quit()

def main():
    signal(SIGTERM, term_handler)
    global _bus, _loop
    _loop = EventLoop()
    _bus = SystemMessageBus()
    try:
        bus_object = service.GEOPMService()
        method_names = [nn for nn in dir(bus_object) if not nn.startswith('_')]
        prof = LineProfiler()
        prof.add_function(bus_object._platform.get_group_access)
        prof.add_function(bus_object._platform.set_group_access)
        prof.add_function(bus_object._platform.set_group_access_signals)
        prof.add_function(bus_object._platform.set_group_access_controls)
        prof.add_function(bus_object._platform.get_user_access)
        prof.add_function(bus_object._platform.get_all_access)
        prof.add_function(bus_object._platform.get_signal_info)
        prof.add_function(bus_object._platform.get_control_info)
        prof.add_function(bus_object._platform.lock_control)
        prof.add_function(bus_object._platform.unlock_control)
        prof.add_function(bus_object._platform.open_session)
        prof.add_function(bus_object._platform.close_session)
        prof.add_function(bus_object._platform.close_session_admin)
        prof.add_function(bus_object._platform._close_session_completely)
        prof.add_function(bus_object._platform._close_session_write)
        prof.add_function(bus_object._platform.start_batch)
        prof.add_function(bus_object._platform.stop_batch)
        prof.add_function(bus_object._platform.read_signal)
        prof.add_function(bus_object._platform.write_control)
        prof.add_function(bus_object._platform.start_profile)
        prof.add_function(bus_object._platform.stop_profile)
        prof.add_function(bus_object._platform.get_profile_pids)
        prof.add_function(bus_object._platform.get_profile_region_names)
        prof.add_function(bus_object._topo.get_cache)
        _bus.publish_object("/io/github/geopm", service.GEOPMService())
        _bus.register_service("io.github.geopm")
        prof.run("_loop.run()")
    finally:
        stop()

if __name__ == '__main__':
    main()
