#!/bin/bash

set -ex

docker build . -f geopm-prometheus-pkg.Dockerfile | tee geopm-prometheus-pkg.log
id=$(grep "writing image sha256:" geopm-prometheus-pkg.log | awk -F: '{print $2}')
docker tag ${id} geopm-prometheus-pkg
id=$(docker create geopm-prometheus-pkg)
docker cp ${id}:/mnt/geopm-prometheus geopm-prometheus-pkg
docker rm -v ${id}
docker build . -f geopm-prometheus.Dockerfile | tee geopm-prometheus.log
id=$(grep "writing image sha256:" geopm-prometheus.log | awk -F: '{print $2}')
docker tag ${id} geopm-prometheus

