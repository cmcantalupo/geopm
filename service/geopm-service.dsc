#  Copyright (c) 2015 - 2022, Intel Corporation
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in
#        the documentation and/or other materials provided with the
#        distribution.
#
#      * Neither the name of Intel Corporation nor the names of its
#        contributors may be used to endorse or promote products derived
#        from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY LOG OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
Format: 3.0 (quilt)
Source: geopm-service
Binary: geopm-service, geopm-service-devel, python3-geopmdpy, libgeopmd0
Architecture: linux-any
# release-v2.0-candidate version
Version: 1.1.0+dev1915g1708279ba
Maintainer: Christopher M. Cantalupo <christopher.m.cantalupo@intel.com
Uploaders: Christopher M. Cantalupo <christopher.m.cantalupo@intel.com
Homepage: https://geopm.github.io
Vcs-Browser: https://github.com/geopm/geopm
Vcs-Git: git://github.com/geopm/geopm.git
# Removed  from Build-Depends line
Build-Depends: python3-all-dev, python3-setuptools, python3-dasbus (>= 1.6), python3-jsonschema, python3-psutil, python3-cffi, python3-gi python3-gi-cairo, libsystemd-dev
Package-List:
 geopm-service deb admin optional
 geopm-service-dev deb libdevel extra
 python3-geopmdpy deb python optional
 libgeopmd0 deb libs optional
Checksums-Sha1:
 577311b239e08becf0046b2d529749f2422c6d47 1895390 geopm-service-1.1.0+dev1915g1708279ba.tar.gz
Checksums-Sha256:
 cbcc537eaddcbb981fd1d7f1f28a5bd491f84a737e576f37bccbd76c1857c6b7 1895390 geopm-service-1.1.0+dev1915g1708279ba.tar.gz
Files:
 8c460bd828c7b49c1f50e0148e61dae4 1895390 geopm-service-1.1.0+dev1915g1708279ba.tar.gz
Original-Maintainer: Christopher M. Cantalupo <christopher.m.cantalupo@intel.com