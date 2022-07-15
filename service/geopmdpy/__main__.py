#  Copyright (c) 2015 - 2022, Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

from dasbus.loop import EventLoop
from dasbus.connection import SystemMessageBus
from signal import signal
from signal import SIGTERM
from . import service

def term_handler(signum, frame):
    if signum == SIGTERM:
        stop()

def stop():
    bus.disconnect()
    exit(0)

def main():
    signal.signal(SIGTERM, term_handler)
    loop = EventLoop()
    bus = SystemMessageBus()
    try:
        bus.publish_object("/io/github/geopm", service.GEOPMService())
        bus.register_service("io.github.geopm")
        loop.run()
    finally:
        stop()

if __name__ == '__main__':
    main()
