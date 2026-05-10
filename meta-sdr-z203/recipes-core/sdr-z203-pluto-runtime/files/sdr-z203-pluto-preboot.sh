#!/bin/sh

case "$1" in
	start|"")
		mkdir -p /mnt/jffs2 /mnt/msd /dev/iio_ffs /www /opt
		mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

		if grep -q 'qspi-nvmfs' /proc/mtd && ! grep -q ' /mnt/jffs2 ' /proc/mounts; then
			mount -t jffs2 -o rw,noatime /dev/mtdblock2 /mnt/jffs2 2>/dev/null || true
		fi
		;;
	stop)
		;;
	*)
		echo "Usage: $0 {start|stop}" >&2
		exit 1
		;;
esac

exit 0
