
FROM docker.io/s390x/fedora:latest

ARG centos_version

RUN dnf -y install jq iptables iproute dnsmasq qemu openssh-clients screen bind-utils tcpdump iputils && dnf clean all

WORKDIR /

COPY vagrant.key /vagrant.key

RUN chmod 700 vagrant.key

ENV DOCKERIZE_VERSION v0.6.1

RUN curl -LO https://github.com/ibm-jitendra/kubevirt_pkgs/raw/main/dockerize-linux-s390x.tar.gz \
  && tar -xvf dockerize-linux-s390x.tar.gz \
  && rm dockerize-linux-s390x.tar.gz \
  && chmod u+x dockerize \
  && mv dockerize /usr/local/bin/

COPY scripts/download_box.sh /

RUN echo "Centos9 version $centos_version"

ENV CENTOS_URL https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-Vagrant-9-$centos_version.x86_64.vagrant-libvirt.box

RUN /download_box.sh ${CENTOS_URL}

RUN curl -L -o /initrd.img http://mirror.stream.centos.org/9-stream/BaseOS/s390x/os/images/initrd.img
RUN curl -L -o /vmlinuz http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/images/pxeboot/vmlinuz

COPY scripts/* /
