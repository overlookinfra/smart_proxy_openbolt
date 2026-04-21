FROM --platform=linux/amd64 rockylinux:9

RUN dnf install -y https://yum.theforeman.org/releases/latest/el9/x86_64/foreman-release.rpm
RUN dnf install -y foreman-proxy openssl git cronie && \
    dnf clean all
RUN dnf install -y https://yum.voxpupuli.org/openvox8-release-el-9.noarch.rpm && \
    dnf install -y openbolt openvox-server puppet-agent && \
    dnf clean all

RUN /opt/puppetlabs/puppet/bin/gem install r10k --no-document
RUN echo '*' > /etc/puppetlabs/puppet/autosign.conf

RUN mkdir -p /opt/foreman-proxy && \
    chown -R foreman-proxy:foreman-proxy /opt/foreman-proxy

COPY proxy/setup.sh /setup.sh
COPY proxy/entrypoint.sh /entrypoint.sh
RUN chmod +x /setup.sh /entrypoint.sh

EXPOSE 8443 8140 4222

CMD ["sleep", "infinity"]
