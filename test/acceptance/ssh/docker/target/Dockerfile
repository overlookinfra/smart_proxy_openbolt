FROM ubuntu:24.04

RUN apt-get update && \
    apt-get -y install openssh-server sudo jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir /run/sshd

RUN useradd -m openbolt && \
    echo 'openbolt:openbolt' | chpasswd && \
    adduser openbolt sudo

RUN mkdir -p /home/openbolt/.ssh && \
    chmod 700 /home/openbolt/.ssh && \
    chown -R openbolt:openbolt /home/openbolt

COPY target/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
