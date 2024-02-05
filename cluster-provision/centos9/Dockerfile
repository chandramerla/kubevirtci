
FROM docker.io/s390x/fedora:latest

ARG centos_version

RUN dnf -y install jq iptables iproute dnsmasq qemu openssh-clients screen bind-utils tcpdump iputils && dnf clean all

WORKDIR /

COPY s390x_centos.key /s390x_centos.key

RUN chmod 700 s390x_centos.key

ENV DOCKERIZE_VERSION v0.6.1

RUN curl -LO https://github.com/ibm-jitendra/kubevirt_pkgs/raw/main/dockerize-linux-s390x.tar.gz \
  && tar -xvf dockerize-linux-s390x.tar.gz \
  && rm dockerize-linux-s390x.tar.gz \
  && chmod u+x dockerize \
  && mv dockerize /usr/local/bin/

#COPY scripts/download_box.sh /

RUN echo "Centos9 version $centos_version"

#ENV CENTOS_URL https://cloud.centos.org/centos/9-stream/s390x/images/CentOS-Stream-GenericCloud-9-latest.s390x.qcow2

#RUN /download_box.sh ${CENTOS_URL}

COPY  CentOS-Stream-GenericCloud-9-latest.s390x.qcow2 box.qcow2
#RUN curl -L -o /initrd.img http://mirror.stream.centos.org/9-stream/BaseOS/s390x/os/images/initrd.img
#RUN curl -L -o /vmlinuz http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/images/pxeboot/vmlinuz

COPY scripts/* /
