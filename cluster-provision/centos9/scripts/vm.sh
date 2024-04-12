#!/bin/bash

# This script is executed in the container during startup to start the qemu VM
set -ex

PROVISION=false
MEMORY=3096M
CPU=2
QEMU_ARGS=""
KERNEL_ARGS=""
NEXT_DISK=""
BLOCK_DEV=""
BLOCK_DEV_SIZE=""

while true; do
  case "$1" in
    -m | --memory ) MEMORY="$2"; shift 2 ;;
    -c | --cpu ) CPU="$2"; shift 2 ;;
    -q | --qemu-args ) QEMU_ARGS="${2}"; shift 2 ;;
    -k | --additional-kernel-args ) KERNEL_ARGS="${2}"; shift 2 ;;
    -n | --next-disk ) NEXT_DISK="$2"; shift 2 ;;
    -b | --block-device ) BLOCK_DEV="$2"; shift 2 ;;
    -s | --block-device-size ) BLOCK_DEV_SIZE="$2"; shift 2 ;;
    -n | --nvme-device-size ) NVME_DISK_SIZES+="$2 "; shift 2 ;;
    -t | --scsi-device-size ) SCSI_DISK_SIZES+="$2 "; shift 2 ;;
    -u | --usb-device-size ) USB_SIZES+="$2 "; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

#Calculates disk name that can be used when a new disk with particular size is created baseed from existing disk
function calc_next_disk {
  last="$(ls -t disk* | head -1 | sed -e 's/disk//' -e 's/.qcow2//')"
  last="${last:-00}"
  next=$((last+1))
  next=$(printf "/disk%02d.qcow2" $next)
  if [ -n "$NEXT_DISK" ]; then next=${NEXT_DISK}; fi
  if [ "$last" = "00" ]; then
    last="box.qcow2"
  else
    last=$(printf "/disk%02d.qcow2" $last)
  fi
}

NODE_NUM=${NODE_NUM-1}
n="$(printf "%02d" $(( 10#${NODE_NUM} )))"

cat >/usr/local/bin/ssh.sh <<EOL
#!/bin/bash
set -ex
dockerize -wait tcp://192.168.66.1${n}:22 -timeout 300s &>/dev/null
ssh -vvv -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no cloud-user@192.168.66.1${n} -i s390x_cloud-user.key -p 22 -q \$@
EOL
chmod u+x /usr/local/bin/ssh.sh
echo "done" > /ssh_ready


sleep 0.1
until ip link show tap${n}; do
  echo "Waiting for tap${n} to become ready"
  sleep 0.1
done

ROOTLESS=0
if [ -f /run/.containerenv ]; then
  ROOTLESS=$(sed -n 's/^rootless=//p' /run/.containerenv)
fi

############## test ###########
ip ad

iptables -t nat -A POSTROUTING ! -s 192.168.66.0/16 --out-interface br0 -j MASQUERADE
if [ "$ROOTLESS" != "1" ]; then
  iptables -A FORWARD --in-interface eth0 -j ACCEPT
  iptables -t nat -A PREROUTING -p tcp -i eth0 -m tcp --dport 22${n} -j DNAT --to-destination 192.168.66.1${n}:22
else
  # Add DNAT rule for rootless podman (traffic originating from loopback adapter)
  iptables -t nat -A OUTPUT -p tcp --dport 22${n} -j DNAT --to-destination 192.168.66.1${n}:22
fi

function create_ip_rules {
  protocol=$1
  shift
  if [ "$ROOTLESS" != "1" ]; then
    for port in "$@"; do
      iptables -t nat -A PREROUTING -p ${protocol} -i eth0 -m ${protocol} --dport ${port} -j DNAT --to-destination 192.168.66.101:${port}
    done
  else
    for port in "$@"; do
      # Add DNAT rule for rootless podman (traffic originating from loopback adapter)
      iptables -t nat -A OUTPUT -p ${protocol} --dport ${port} -j DNAT --to-destination 192.168.66.101:${port}
    done
  fi
}

# Route ports from container to VM for first node
if [ "$n" = "01" ] ; then
  tcp_ports=( 6443 8443 80 443 30007 30008 31001 )
  create_ip_rules "tcp" "${tcp_ports[@]}"

  udp_ports=( 31111 )
  create_ip_rules "udp" "${udp_ports[@]}"
fi

# For backward compatibility, so that we can just copy over the newer files
if [ -f provisioned.qcow2 ]; then
  ln -sf provisioned.qcow2 disk01.qcow2
fi

calc_next_disk

default_disk_size=53687091200 # 50G
disk_size=$(qemu-img info --output json ${last} | jq '.["virtual-size"]')
if [ $disk_size -lt $default_disk_size ]; then
    disk_size=$default_disk_size
fi

echo "Creating new disk \"${next} backed by ${last} with size ${disk_size}\"."
qemu-img create -f qcow2 -o backing_file=${last} -F qcow2 ${next} ${disk_size}

echo ""
echo "SSH will be available on container port 22${n}."
echo "VNC will be available on container port 59${n}."
echo "VM MAC in the guest network will be 52:55:00:d1:55:${n}"
echo "VM IP in the guest network will be 192.168.66.1${n}"
echo "VM hostname will be node${n}"

# Try to create /dev/kvm if it does not exist
if [ ! -e /dev/kvm ]; then
   mknod /dev/kvm c 10 $(grep '\<kvm\>' /proc/misc | cut -f 1 -d' ')
fi

# Prevent the emulated soundcard from messing with host sound
export QEMU_AUDIO_DRV=none

block_dev_arg=""

if [ -n "${BLOCK_DEV}" ]; then
  # 10Gi default
  block_device_size="${BLOCK_DEV_SIZE:-10737418240}"
  qemu-img create -f qcow2 ${BLOCK_DEV} ${block_device_size}
  block_dev_arg="-drive format=qcow2,file=${BLOCK_DEV},if=virtio,cache=unsafe"
fi

disk_num=0
for size in ${NVME_DISK_SIZES[@]}; do
  echo "Creating disk "$size" for NVMe disk emulation"
  disk="/nvme-"${disk_num}".img"
  qemu-img create -f raw $disk $size
  let "disk_num+=1"
done

disk_num=0
for size in ${SCSI_DISK_SIZES[@]}; do
  echo "Creating disk "$size" for SCSI disk emulation"
  disk="/scsi-"${disk_num}".img"
  qemu-img create -f raw $disk $size
  let "disk_num+=1"
done


disk_num=0
for size in ${USB_SIZES[@]}; do
  echo "Creating disk "$size" for USB disk emulation"
  disk="/usb-"${disk_num}".img"
  qemu-img create -f raw $disk $size
  let "disk_num+=1"
done

sleep 100000

#Docs: https://www.qemu.org/docs/master/system/invocation.html
#     https://www.qemu.org/docs/master/system/target-s390x.html
qemu_log="qemu_log.txt"
# qemu-system-s390x -enable-kvm -drive format=qcow2,file=${next},if=virtio,cache=unsafe -machine s390-ccw-virtio -device virtio-net-ccw,netdev=network0,mac=52:55:00:d1:55:${n} -netdev tap,id=network0,ifname=tap01,script=no,downscript=no -device virtio-rng -vnc :01 -cpu host -m 32767M -smp 16 -serial pty -uuid $(cat /proc/sys/kernel/random/uuid) ${QEMU_ARGS} >"$qemu_log" 2>&1
# qemu-system-s390x -enable-kvm -drive format=qcow2,file=${next},if=virtio,cache=unsafe -machine s390-ccw-virtio -device virtio-net-ccw,netdev=network0,mac=52:55:00:d1:55:${n} -netdev tap,id=network0,ifname=tap01,script=no,downscript=no -device virtio-rng -vnc :01 -cpu host -m 3096M -smp 2 -serial pty -uuid $(cat /proc/sys/kernel/random/uuid)
   #To use the CPU topology, you currently need to choose the KVM accelerator.
   #As per https://www.qemu.org/docs/master/system/s390x/bootdevices.html#booting-without-bootindex-parameter -drive if=virtio can't be specified with bootindex
qemu-system-s390x \
    -enable-kvm \
    -drive format=qcow2,file=${next},if=none,cache=unsafe,id=drive1 ${block_dev_arg} \
    -device virtio-blk,drive=drive1,bootindex=1 \
    -machine s390-ccw-virtio,accel=kvm \
    -device virtio-net-ccw,netdev=network0,mac=52:55:00:d1:55:${n} \
    -netdev tap,id=network0,ifname=tap${n},script=no,downscript=no \
    -device virtio-rng \
    -vnc :${n} \
    -cpu host \
    -m 32767M \
    -smp 16 \
    -serial pty \
    -uuid $(cat /proc/sys/kernel/random/uuid) \
    ${QEMU_ARGS} \
    >"$qemu_log" 2>&1
cat "qemu_log.txt"