FROM --platform=linux/amd64 rockylinux:9

RUN dnf install -y https://yum.voxpupuli.org/openvox8-release-el-9.noarch.rpm && \
    dnf install -y puppet-agent jq procps-ng cronie && \
    dnf clean all

COPY target/setup.sh /setup.sh
COPY target/entrypoint.sh /entrypoint.sh
RUN chmod +x /setup.sh /entrypoint.sh

CMD ["sleep", "infinity"]
