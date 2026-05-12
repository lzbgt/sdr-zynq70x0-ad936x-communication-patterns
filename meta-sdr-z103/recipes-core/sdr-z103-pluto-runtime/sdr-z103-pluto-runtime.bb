SUMMARY = "Pluto-compatible runtime assets for SDR-Z103"
DESCRIPTION = "Imports the essential Pluto runtime scripts and MSD assets from the extracted vendor firmware tree."
LICENSE = "CLOSED"

SRC_URI = " \
    file://sdr-z103-pluto-preboot.sh \
    file://sdr-z103-usb-getty.sh \
    file://portable-frm-helpers.sh \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = " \
    dosfstools \
    libiio-iiod \
    libiio-tests \
    libubootenv-bin \
    mtd-utils \
    mtd-utils-jffs2 \
    unzip \
"

do_install() {
    board_dir="${SDR_Z103_VENDOR_FW}/buildroot/board/pluto"
    target_dir="${SDR_Z103_VENDOR_FW}/buildroot/output/target"

    if [ ! -d "$board_dir" ]; then
        bbfatal "Vendor Pluto board directory not found: $board_dir"
    fi
    if [ ! -d "$target_dir" ]; then
        bbfatal "Vendor Buildroot output target not found: $target_dir"
    fi
    if [ ! -f "$target_dir/opt/vfat.img" ]; then
        bbfatal "Vendor MSD image not found: $target_dir/opt/vfat.img"
    fi

    install -d ${D}${sysconfdir}/init.d ${D}${sysconfdir}/rcS.d
    install -m 0755 ${WORKDIR}/sdr-z103-pluto-preboot.sh ${D}${sysconfdir}/init.d/S20pluto-preboot
    install -m 0755 ${WORKDIR}/sdr-z103-usb-getty.sh ${D}${sysconfdir}/init.d/S24usb-getty

    for script in S21misc S23udc S40network S45msd S98autostart; do
        install -m 0755 "$board_dir/$script" ${D}${sysconfdir}/init.d/
    done

    sed -i \
        -e 's#echo ${MAX_BS} > /sys/module/industrialio_buffer_dma/parameters/max_block_size#[ -w /sys/module/industrialio_buffer_dma/parameters/max_block_size ] \&\& echo ${MAX_BS} > /sys/module/industrialio_buffer_dma/parameters/max_block_size || true#' \
        ${D}${sysconfdir}/init.d/S21misc
    sed -i \
        -e '/\/sbin\/ifup -a 2>&1 | logger/a\\t/usr/sbin/udhcpd /etc/udhcpd.conf 2> /dev/null || true' \
        -e '/\/sbin\/ifdown -a/i\\tkillall udhcpd 2> /dev/null || true' \
        ${D}${sysconfdir}/init.d/S40network

    ln -sf ../init.d/S20pluto-preboot ${D}${sysconfdir}/rcS.d/S20pluto-preboot
    ln -sf ../init.d/S21misc ${D}${sysconfdir}/rcS.d/S21misc
    ln -sf ../init.d/S23udc ${D}${sysconfdir}/rcS.d/S23udc
    ln -sf ../init.d/S24usb-getty ${D}${sysconfdir}/rcS.d/S24usb-getty
    ln -sf ../init.d/S40network ${D}${sysconfdir}/rcS.d/S40network
    ln -sf ../init.d/S45msd ${D}${sysconfdir}/rcS.d/S45msd
    ln -sf ../init.d/S98autostart ${D}${sysconfdir}/rcS.d/S98autostart

    install -d ${D}${base_sbindir}
    for script in update.sh update_frm.sh update_from_github.sh udc_handle_suspend.sh; do
        install -m 0755 "$board_dir/$script" ${D}${base_sbindir}/
    done
    sed -i '2a PATH=/usr/bin:/usr/sbin:/bin:/sbin' \
        ${D}${base_sbindir}/update.sh \
        ${D}${base_sbindir}/update_frm.sh
    sed -i "3r ${WORKDIR}/portable-frm-helpers.sh" \
        ${D}${base_sbindir}/update.sh \
        ${D}${base_sbindir}/update_frm.sh
    sed -i \
        -e 's#head -c -33 .* > /opt/boot_and_env_and_mtdinfo.bin#copy_without_trailing_bytes "$FILE" /opt/boot_and_env_and_mtdinfo.bin 33#' \
        -e 's#head -c -1024 /opt/boot_and_env_and_mtdinfo.bin > /opt/boot_and_env.bin#copy_without_trailing_bytes /opt/boot_and_env_and_mtdinfo.bin /opt/boot_and_env.bin 1024#' \
        -e 's#head -c -131072 /opt/boot_and_env.bin > /opt/boot.bin#copy_without_trailing_bytes /opt/boot_and_env.bin /opt/boot.bin 131072#' \
        -e 's#head -c -33 .* > /opt/firmware.frm#copy_without_trailing_bytes "$FILE" /opt/firmware.frm 33#' \
        ${D}${base_sbindir}/update.sh \
        ${D}${base_sbindir}/update_frm.sh

    install -d ${D}${sbindir}
    for tool in device_reboot device_passwd device_persistent_keys device_format_jffs2 test_ensm_pinctrl.sh; do
        install -m 0755 "$board_dir/$tool" ${D}${sbindir}/
    done
    ln -sf device_reboot ${D}${sbindir}/pluto_reboot

    install -d ${D}/opt
    install -m 0644 "$target_dir/opt/vfat.img" ${D}/opt/vfat.img
    if [ -f "$target_dir/opt/VERSIONS" ]; then
        install -m 0644 "$target_dir/opt/VERSIONS" ${D}/opt/VERSIONS
    else
        echo "device-fw yocto-local" > ${D}/opt/VERSIONS
    fi

    install -d ${D}/www
    cp -R --no-preserve=ownership "$target_dir/www/." ${D}/www/

    install -d ${D}${sysconfdir}/wpa_supplicant
    cp -R --no-preserve=ownership "$board_dir/wpa_supplicant/." ${D}${sysconfdir}/wpa_supplicant/

    install -d ${D}/mnt/jffs2 ${D}/mnt/msd ${D}/dev/iio_ffs
}

FILES:${PN} = " \
    ${sysconfdir}/init.d/S20pluto-preboot \
    ${sysconfdir}/init.d/S21misc \
    ${sysconfdir}/init.d/S23udc \
    ${sysconfdir}/init.d/S24usb-getty \
    ${sysconfdir}/init.d/S40network \
    ${sysconfdir}/init.d/S45msd \
    ${sysconfdir}/init.d/S98autostart \
    ${sysconfdir}/rcS.d/S20pluto-preboot \
    ${sysconfdir}/rcS.d/S21misc \
    ${sysconfdir}/rcS.d/S23udc \
    ${sysconfdir}/rcS.d/S24usb-getty \
    ${sysconfdir}/rcS.d/S40network \
    ${sysconfdir}/rcS.d/S45msd \
    ${sysconfdir}/rcS.d/S98autostart \
    ${base_sbindir}/update.sh \
    ${base_sbindir}/update_frm.sh \
    ${base_sbindir}/update_from_github.sh \
    ${base_sbindir}/udc_handle_suspend.sh \
    ${sbindir}/device_reboot \
    ${sbindir}/device_passwd \
    ${sbindir}/device_persistent_keys \
    ${sbindir}/device_format_jffs2 \
    ${sbindir}/test_ensm_pinctrl.sh \
    ${sbindir}/pluto_reboot \
    ${sysconfdir}/wpa_supplicant \
    /opt \
    /www \
    /mnt/jffs2 \
    /mnt/msd \
    /dev/iio_ffs \
"
