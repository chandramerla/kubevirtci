FROM docker.io/s390x/fedora:latest AS kernelfiles

RUN dnf -y install libguestfs libguestfs-tools-c && dnf clean all

WORKDIR /

COPY  CentOS-Stream-GenericCloud-9-latest.s390x.qcow2 box.qcow2

ENV LIBGUESTFS_BACKEND=direct

#This we can use virt-customize instead of virt-sysprep
#Remove -v & -x for verbose later
RUN virt-sysprep -v -x -a box.qcow2 --no-selinux-relabel --run-command "useradd -m cloud-user" || cat /var/log/virt-customize.log
RUN virt-sysprep -a box.qcow2 --no-selinux-relabel --root-password password:Zxc@123 --ssh-inject cloud-user:string:"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCR8M7jpRiuo1DdLyzDSndeGgsjDlrZBn6R8OLTb7P23wP9EjGhD+Tztf0hpgjsKtpGoDOGudQ+is5vob2m9jWmRibTJ4cv7/hp9lHboZGuCba40JAMUJfcO9hOzviVInBmxAcC7KUZ0AtYNs7ClYs0txd+Ibhtx1zh0GKrooyfXSfL5+CIZ78gJVED9D0ZGy9hF+HMyVM/bcmq2LPkpsk+B4zxfHuDvqzzG2wk93pnNgXuihxKqNo64gZ94/FwpnNkQq2sa9Alrudfs+l/DWPjhJle17o6Xg1Ai0N/32BGKtqpxbfGwcRcnLBGG+f1LGiau31Y9vpP+A+0FH810b4gY0BEtCd7JqqYjXqVdzTl2NzKnMDmO/NYEgi7Y75wZsKtF1T30GKYrnfevKpg2qLW2exEJXwkv6/enx5t7Mzvg8hZ+Am4uPajLAA6PVtFf2d8TE3TpIPhBakhbx3xrWiHxnmDYCEw/m1Q1k7H6cEGpk5jqdRaOBLAY74H4XU+pMIN6uoZSTN3bwYyTwbsOZmY+qWtZwhi5uQyFiNJfzbotIYZ4foajgHAf1I9LqLCzL7kmGOTv2dqab+NdCACJiNxECOz50gNjhkZ+03k1F5uLdgP4fagpOy+knJ1w/Vpn47RVUefknazZOXoOlI3dRlq844dpya1sYeO80ieEiNQHw== centos@localhost"

RUN guestfish --ro --add box.qcow2 --mount /dev/sda1:/ ls /boot/ | grep -E '^vmlinuz-|^initramfs-' | xargs -I {} guestfish --ro --add box.qcow2 -i copy-out /boot/{} /
RUN guestfish --rw --add box.qcow2 --mount /dev/sda1:/ selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts /

#append-line, edit are subcommands
#Even we can use https://libguestfs.org/virt-edit.1.html#non-interactive-editing or guestfish subcommand edit
#RUN virt-customize -a box.qcow2 --run-command "echo \"$RUN_CMD\" >> /etc/cloud/cloud.cfg"
# RUN virt-customize -a box.qcow2 --append-line '/etc/cloud/cloud.cfg:runcmd:'
# RUN virt-customize -a box.qcow2 --append-line '/etc/cloud/cloud.cfg:  - dhclient'
# RUN virt-customize -a box.qcow2 --append-line '/etc/cloud/cloud.cfg:  - systemctl start dbus'

FROM docker.io/s390x/fedora:latest
#TODO: Need to hardcode to shal hash than using latest tag to be 

ARG centos_version

RUN dnf -y install jq iptables iproute dnsmasq qemu socat openssh-clients screen bind-utils tcpdump iputils && dnf clean all

WORKDIR /

COPY s390x_cloud-user.key /s390x_cloud-user.key

RUN chmod 700 s390x_cloud-user.key

ENV DOCKERIZE_VERSION v0.6.1

RUN curl -LO https://github.com/ibm-jitendra/kubevirt_pkgs/raw/main/dockerize-linux-s390x.tar.gz \
  && tar -xvf dockerize-linux-s390x.tar.gz \
  && rm dockerize-linux-s390x.tar.gz \
  && chmod u+x dockerize \
  && mv dockerize /usr/local/bin/

#COPY scripts/download_box.sh /
RUN echo "Centos9 version $centos_version"

#Doc: https://docs.openstack.org/image-guide/introduction.html
#ENV CENTOS_URL https://cloud.centos.org/centos/9-stream/s390x/images/CentOS-Stream-GenericCloud-9-latest.s390x.qcow2
#TODO: We need to fix the version
#TODO: We need to checksum validation of the downloaded artifact by appending the URL with say SHA256SUM
#TODO: Check if there are any other alternatives as image size is ~900MB

#RUN /download_box.sh ${CENTOS_URL}

COPY  --from=kernelfiles /box.qcow2 box.qcow2
#RUN curl -L -o /initrd.img http://mirror.stream.centos.org/9-stream/BaseOS/s390x/os/images/initrd.img
#RUN curl -L -o /vmlinuz http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/images/pxeboot/vmlinuz
# RUN virt-copy-out -a CentOS-Stream-GenericCloud-9-latest.s390x.qcow2 --format=qcow2 /boot/vmlinuz-* /vmlinuz
# RUN virt-copy-out -a CentOS-Stream-GenericCloud-9-latest.s390x.qcow2 --format=qcow2 /boot/initramfs-* /initrd.img
COPY --from=kernelfiles /vmlinuz-* /vmlinuz
COPY --from=kernelfiles /initramfs-* /initrd.img

RUN echo "Debug: Current directory contents" && ls -l /

#TODO: Remainder for me to document: This needs to be done in L0 (LPAR/host) level machine.
#Enable nested virtualization. https://access.redhat.com/documentation/zh/red_hat_enterprise_linux/8/html/configuring_and_managing_virtualization/getting-started-with-virtualization-in-rhel-8-on-ibm-z_configuring-and-managing-virtualization
RUN echo "options kvm nested=1" >> /etc/modprobe.d/kvm.conf

COPY scripts/* /
