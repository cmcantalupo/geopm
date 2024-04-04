#!/bin/bash

set -x -e

VERSION=$(python3 -c "from setuptools_scm import get_version; print(get_version('..'))")
echo ${VERSION} > geopmdpy/VERSION
python3 -m build --sdist | tee make_sdist.log
archive=$(cat make_sdist.log | tail -n 1 | sed 's|^Successfully built ||')
tar -xvf dist/$archive
dir=$(echo $archive | sed 's|\.tar\.gz||')
cd $dir
dpkg-buildpackage -us -uc
