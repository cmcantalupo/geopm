#!/bin/bash
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

set -xe

./autogen.sh

PACKAGE_NAME=geopm-service
VERSION=$(cat VERSION)
RPM_TOPDIR=${RPM_TOPDIR:-${HOME}/rpmbuild}
mkdir -p ${RPM_TOPDIR}/SOURCES
mkdir -p ${RPM_TOPDIR}/SPECS
sed -e "s|@VERSION@|$VERSION|g" ${PACKAGE_NAME}.spec.in > ${RPM_TOPDIR}/SPECS/${PACKAGE_NAME}.spec
cd ..
git archive --format=tar.gz -o ${RPM_TOPDIR}/SOURCES/geopm-${VERSION}.tar.gz --prefix=geopm-${VERSION}/ HEAD

if grep -q 'VERSION="15-SP2"' /etc/os-release; then
    rpmbuild ${rpmbuild_flags} --define "disable_io_uring 1" -ba ${RPM_TOPDIR}/SPECS/${PACKAGE_NAME}.spec
else
    rpmbuild ${rpmbuild_flags} -ba ${RPM_TOPDIR}/SPECS/${PACKAGE_NAME}.spec
fi
