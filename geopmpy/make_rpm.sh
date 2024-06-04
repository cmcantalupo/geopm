#!/bin/bash
#  Copyright (c) 2015 - 2024 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

set -xe

./make_sdist.sh

PACKAGE_NAME=geopmpy
VERSION=$(cat ${PACKAGE_NAME}/VERSION)
RPM_TOPDIR=${RPM_TOPDIR:-${HOME}/rpmbuild}
mkdir -p ${RPM_TOPDIR}/SOURCES
mkdir -p ${RPM_TOPDIR}/SPECS
sed -e "s|@VERSION@|$VERSION|g" ${PACKAGE_NAME}.spec.in > ${RPM_TOPDIR}/SPECS/${PACKAGE_NAME}.spec
cd ..
git archive --format=tar.gz -o ${RPM_TOPDIR}/SOURCES/geopm-${VERSION}.tar.gz --prefix=geopm-${VERSION}/ HEAD
rpmbuild -ba ${RPM_TOPDIR}/SPECS/${PACKAGE_NAME}.spec
