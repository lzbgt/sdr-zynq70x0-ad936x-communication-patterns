SUMMARY = "ARM-side developer image for SDR-Z203"
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "ssh-server-dropbear"

IMAGE_INSTALL:append = " \
    ethtool \
    i2c-tools \
    iproute2 \
    libiio \
    libiio-iiod \
    libubootenv-bin \
    sdr-z203-board-files \
"

IMAGE_FSTYPES = "cpio.gz tar.gz"

