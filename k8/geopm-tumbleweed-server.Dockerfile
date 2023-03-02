FROM opensuse/tumbleweed

RUN mkdir -m 700 -p /etc/geopm-service; mkdir -m 700 -p /etc/geopm-service/0.DEFAULT_ACCESS; echo "TIME" > /etc/geopm-service/0.DEFAULT_ACCESS/allowed_signals; chmod 600 /etc/geopm-service/0.DEFAULT_ACCESS/allowed_signals
RUN zypper install -y curl
RUN curl -fsSL https://download.opensuse.org/repositories/home:/cmcantal:/cloud/openSUSE_Tumbleweed/repodata/repomd.xml.key > /tmp/suse-key
RUN rpm --import /tmp/suse-key
RUN zypper addrepo https://download.opensuse.org/repositories/home:/cmcantal:/cloud/openSUSE_Tumbleweed/home:cmcantal:cloud.repo
RUN zypper install -y geopm-service
