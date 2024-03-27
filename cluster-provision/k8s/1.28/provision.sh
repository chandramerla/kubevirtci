#!/bin/bash

set -ex

KUBEVIRTCI_SHARED_DIR=/var/lib/kubevirtci
mkdir -p $KUBEVIRTCI_SHARED_DIR
export ISTIO_VERSION=1.15.0
cat << EOF > $KUBEVIRTCI_SHARED_DIR/shared_vars.sh
#!/bin/bash
set -ex
export KUBELET_CGROUP_ARGS="--cgroup-driver=systemd --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"
export ISTIO_VERSION=${ISTIO_VERSION}
export ISTIO_BIN_DIR="/opt/istio-${ISTIO_VERSION}/bin"
EOF
source $KUBEVIRTCI_SHARED_DIR/shared_vars.sh

# Install modules of the initrd kernel
dnf install -y "kernel-modules-$(uname -r)"

# Resize root partition
dnf install -y cloud-utils-growpart
if growpart /dev/vda 1; then
    resize2fs /dev/vda1
fi

dnf install -y patch

systemctl stop firewalld || :
systemctl disable firewalld || :
# Make sure the firewall is never enabled again
# Enabling the firewall destroys the iptable rules
dnf -y remove firewalld

# Required for iscsi demo to work.
dnf -y install iscsi-initiator-utils

# required for some sig-network tests
dnf -y install nftables

# for rook ceph
dnf -y install lvm2
# Convince ceph our storage is fast (not a rotational disk)
echo 'ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="vd[a-z]", ATTR{queue/rotational}="0"' \
	> /etc/udev/rules.d/60-force-ssd-rotational.rules

# To prevent preflight issue related to tc not found
dnf install -y iproute-tc
# Install istioctl
export PATH="$ISTIO_BIN_DIR:$PATH"
(
  set -E
  mkdir -p "$ISTIO_BIN_DIR"
  curl "https://storage.googleapis.com/kubevirtci-istioctl-mirror/istio-${ISTIO_VERSION}/bin/istioctl" -o "$ISTIO_BIN_DIR/istioctl"
  chmod +x "$ISTIO_BIN_DIR/istioctl"
)

dnf install -y container-selinux

dnf install -y libseccomp-devel

# openvswitch2 need to be built following instructions that worked for Vamsi (given below). 
dnf install -y @'Development Tools' rpm-build dnf-plugins-core
git clone https://github.com/openvswitch/ovs.git
cd ovs
git checkout v2.16.0
dnf install -y clang
dnf install -y git
dnf install -y autoconf
dnf install -y automake
dnf install -y libtool
sleep 7200
dnf install -y https://kojihub.stream.centos.org/kojifiles/vol/koji02/packages/unbound/1.19.0/8.el10/s390x/unbound-libs-1.19.0-8.el10.s390x.rpm
dnf install -y https://kojihub.stream.centos.org/kojifiles/vol/koji02/packages/unbound/1.19.0/8.el10/s390x/unbound-devel-1.19.0-8.el10.s390x.rpm
python -m pip install git+https://github.com/sphinx-doc/sphinx
# git clone https://github.com/NLnetLabs/unbound.git
# # Update the package repositories
# sudo yum update -y
# # Install the C toolchain
# sudo yum install -y gcc
# # Install OpenSSL and OpenSSL Development Files
# sudo yum install -y openssl openssl-devel
# # Install Flex and Bison (for building from repository source)
# sudo yum install -y flex bison
# # Install Libexpat and Expact Development Files
# sudo yum install -y expat expat-devel
# # Install Libevent and Libevent Development Files
# sudo yum install -y libevent libevent-devel
# # Install LDNS and LDNS Development Files
# sudo yum install -y ldns ldns-devel
# ./configure && make && make install

sed -e 's/@VERSION@/2.16/' rhel/openvswitch-fedora.spec.in \
 > /tmp/ovs.spec
dnf -y builddep /tmp/ovs.spec
rm -f /tmp/ovs.spec
./boot.sh
./configure
make rpm-fedora
dnf install -y rpm/rpmbuild/RPMS/*/*.rpm
systemctl status openvswitch

# dnf install -y clang
# dnf install -y git
# dnf install -y autoconf
# dnf install -y automake
# dnf install -y libtool
# git clone https://github.com/openvswitch/ovs.git
# cd ovs
# git checkout v2.16.0
# ./boot.sh
# ./configure
# make
# make install
# export PATH=$PATH:/usr/local/share/openvswitch/scripts
# ovs-ctl start
# ovs-ctl status
# dnf install -y centos-release-nfv-openvswitch
# dnf install -y openvswitch2.16

dnf install -y NetworkManager NetworkManager-ovs NetworkManager-config-server
