#!/bin/bash

set -e
set -o pipefail

curl -L $1 -o box.qcow2

#qemu-img convert -O qcow2 box.img box.qcow2
#rm box.img
