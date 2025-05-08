# Stage 1: Build container
FROM fedora:42 AS build

RUN dnf -y update && \
    dnf -y install gcc g++ grpc-devel protobuf-devel && \
    mkdir -p /mnt/geopm-fedora && \
    chmod a+rwx /mnt/geopm-fedora && \
    useradd -m build

USER build
WORKDIR /home/build
RUN curl -sL https://github.com/geopm/geopm/archive/v3.2.0/geopm-3.2.0.tar.gz > geopm-3.2.0.tar.gz && \
    tar xf geopm-3.2.0.tar.gz && \
    cd geopm-3.2.0/geopmdrs && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    export PATH="$HOME/.cargo/bin:${PATH}" && \
    sed -e "s|@VERSION@|3.2.0|" Cargo.toml.in > Cargo.toml && \
    cargo vendor && \
    cargo build --release && \
    cp -p target/release/geopmd-proxy /mnt/geopm-fedora/geopmd-proxy

FROM fedora:42
# Copy .rpm packages from the build stage and install them
COPY --from=build /mnt/geopm-fedora /mnt/geopm-fedora
RUN curl -sL https://copr.fedorainfracloud.org/coprs/cmcantalupo/GEOPM/repo/fedora-42/cmcantalupo-GEOPM-fedora-42.repo > /etc/yum.repos.d/cmcantalupo-GEOPM-fedora-42.repo && \
    dnf update -y && \
    dnf install --setopt=install_weak_deps=False -y util-linux python3-geopmdpy && \
    dnf clean all && \
    install /mnt/geopm-fedora/geopmd-proxy /usr/bin/geopmd-proxy && \
    rm -rf /mnt/geopm-fedora

# Configure GEOPM
RUN printf \
"CPU_CORE_TEMPERATURE\nCPU_ENERGY\nCPU_FREQUENCY_STATUS\n"\
"CPU_PACKAGE_TEMPERATURE\nCPU_POWER\nCPU_UNCORE_FREQUENCY_STATUS\n"\
"DRAM_ENERGY\nDRAM_POWER\nGPU_CORE_FREQUENCY_STATUS\nGPU_ENERGY\n"\
"GPU_POWER\nGPU_TEMPERATURE\n" | \
    geopmaccess --direct --force --write --default && \
    printf "" | geopmaccess --direct --force --write --default --controls
