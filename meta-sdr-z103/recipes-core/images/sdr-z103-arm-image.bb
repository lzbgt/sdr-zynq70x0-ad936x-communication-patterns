SUMMARY = "ARM-side developer image for SDR-Z103"
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "ssh-server-dropbear"

IMAGE_INSTALL:append = " \
    ethtool \
    i2c-tools \
    iproute2 \
    libiio \
    libiio-iiod \
    libiio-tests \
    libubootenv-bin \
    lighttpd \
    mtd-utils \
    fieldmesh-rf-tools \
    fieldmesh-sdk-demos \
    fieldmesh-udp-probe \
    sdr-z103-board-files \
    sdr-z103-pluto-runtime \
"

IMAGE_FSTYPES = "cpio.gz tar.gz"
