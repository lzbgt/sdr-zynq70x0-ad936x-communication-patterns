#!/bin/sh

PID=/var/run/ttyGS0-getty.pid

case "$1" in
	start|"")
		if [ -e /dev/ttyGS0 ]; then
			start-stop-daemon -S -b -q -m -p "$PID" -x /sbin/getty -- -L ttyGS0 0 vt100
		fi
		;;
	stop)
		start-stop-daemon -K -q -p "$PID" 2>/dev/null || true
		;;
	restart|reload)
		"$0" stop
		"$0" start
		;;
	*)
		echo "Usage: $0 {start|stop|restart}" >&2
		exit 1
		;;
esac

exit 0
