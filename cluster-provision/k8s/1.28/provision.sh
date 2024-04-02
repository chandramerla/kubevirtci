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

# openvswitch2 need to be built following instructions below.
# dnf install -y @'Development Tools' rpm-build dnf-plugins-core
# git clone https://github.com/openvswitch/ovs.git
# cd ovs
# git checkout v2.16.0
# dnf install -y clang
# dnf install -y git
# dnf install -y autoconf
# dnf install -y automake
# dnf install -y libtool
# sleep 7200
# sudo dnf install -y unbound-1.16.2-3.el9.s390x
# sudo dnf install -y https://kojihub.stream.centos.org/kojifiles/packages/unbound/1.16.2/3.el9/s390x/unbound-devel-1.16.2-3.el9.s390x.rpm
# sudo dnf install -y python3-pip
# sudo dnf install -y desktop-file-utils
# sudo dnf install -y groff
# sudo dnf install -y libcap-ng-devel
# sudo dnf install -y selinux-policy-devel
# python -m pip install git+https://github.com/sphinx-doc/sphinx
# cd ovs
# sed -i -e 's/@VERSION@/2.16.0/' -e '/BuildRequires: \/usr\/bin\/sphinx-build-3/s/^/#/' rhel/openvswitch-fedora.spec
# sed -e 's/@VERSION@/2.16.0/' -e '/BuildRequires: \/usr\/bin\/sphinx-build-3/s/^/#/' rhel/openvswitch-fedora.spec.in \
#  > /tmp/ovs.spec
# sudo dnf -y builddep /tmp/ovs.spec
# rm -f /tmp/ovs.spec
# sudo ./boot.sh
# sudo ./configure
# sudo make rpm-fedora
# sudo dnf install -y rpm/rpmbuild/RPMS/*/*.rpm
# sudo systemctl status openvswitch

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

dnf install -y https://kojipkgs.fedoraproject.org//packages/openvswitch/2.16.0/2.fc36/s390x/openvswitch-2.16.0-2.fc36.s390x.rpm

systemctl enable openvswitch

dnf install -y NetworkManager NetworkManager-ovs NetworkManager-config-server
