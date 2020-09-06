#!/bin/sh
cd "$(dirname "$(readlink -f "$0")")"
curl -Lo busybox 'https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64'
chmod +x busybox
./busybox --install .
