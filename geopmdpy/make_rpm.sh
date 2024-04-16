#!/bin/bash

set -xe

./make_sdist.sh

PACKAGE_NAME=geopmdpy
ARCHIVE=${PACKAGE_NAME}-$(cat ${PACKAGE_NAME}/VERSION).tar.gz
RPM_TOPDIR=${RPM_TOPDIR:-${HOME}/rpmbuild}
mkdir -p ${RPM_TOPDIR}/SOURCES
mkdir -p ${RPM_TOPDIR}/SPECS
cp dist/${ARCHIVE} ${RPM_TOPDIR}/SOURCES
cp ${PACKAGE_NAME}.spec ${RPM_TOPDIR}/SPECS
rpmbuild -ba ${RPM_TOPDIR}/SPECS/${PACKAGE_NAME}.spec

echo "0.0.0" > ${PACKAGE_NAME}/VERSION
