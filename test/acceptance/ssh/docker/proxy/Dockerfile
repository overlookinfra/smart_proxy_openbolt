FROM --platform=linux/amd64 rockylinux:9

# Add Foreman repo
RUN dnf install -y https://yum.theforeman.org/releases/latest/el9/x86_64/foreman-release.rpm

# Install foreman-proxy and its dependencies
RUN dnf install -y foreman-proxy openssh-clients openssl && \
    dnf clean all

# Install OpenBolt from the OpenVox RPM repo
RUN dnf install -y https://yum.voxpupuli.org/openvox8-release-el-9.noarch.rpm && \
    dnf install -y openbolt

# Create SSH key directory
RUN mkdir -p /opt/foreman-proxy/.ssh && \
    chown -R foreman-proxy:foreman-proxy /opt/foreman-proxy

COPY proxy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8443

ENTRYPOINT ["/entrypoint.sh"]
