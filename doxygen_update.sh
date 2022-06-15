#!/bin/bash

set -e

SCRIPT_FILE=$0
SCRIPT_DIR=$(realpath $(dirname ${SCRIPT_FILE}))

cd ${SCRIPT_DIR}/service
sed -e "s|@DOX_VERSION@|$(cat VERSION)|g" \
    -e "s|@DOX_OUTPUT@|dox|g" \
    -e "s|@DOX_INPUT@|dox/blurb.md src|g" \
    dox/Doxyfile.in > dox/Doxyfile
doxygen dox/Doxyfile

cd ${SCRIPT_DIR}
mkdir -p dox
sed -e "s|@DOX_VERSION@|$(cat VERSION)|g" \
    -e "s|@DOX_OUTPUT@|dox|g" \
    -e "s|@DOX_INPUT@|README.md src|g" \
    dox/Doxyfile.in > dox/Doxyfile
doxygen dox/Doxyfile
