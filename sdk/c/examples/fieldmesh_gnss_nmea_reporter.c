/*
 * FieldMesh local GNSS NMEA reporter.
 *
 * Reads real NMEA GGA/RMC fixes from a configured device or file and reports
 * the local board EUI to the daemon through FIELDMESH_RTLS_REPORT. This is an
 * ingestion bridge, not a synthetic position source.
 */

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define EUI_TEXT_LEN 13
#define LINE_MAX_BYTES 192
#define REQUEST_MAX_BYTES 384
#define RESPONSE_MAX_BYTES 512
#define REPORT_ACK_RETRIES 5u
#define REPORT_ACK_TIMEOUT_US 200000u

struct gnss_fix {
    int lat_e7;
    int lon_e7;
    int pps_lock;
};

static int valid_eui(const char *eui)
{
    size_t i;

    if (!eui || strlen(eui) != 12u) {
        return 0;
    }
    for (i = 0; i < 12u; ++i) {
        if (!isxdigit((unsigned char)eui[i])) {
            return 0;
        }
    }
    return 1;
}

static speed_t baud_to_speed(unsigned baud)
{
    switch (baud) {
    case 4800u:
        return B4800;
    case 9600u:
        return B9600;
    case 19200u:
        return B19200;
    case 38400u:
        return B38400;
    case 57600u:
        return B57600;
    case 115200u:
        return B115200;
    default:
        return 0;
    }
}

static int configure_serial_if_tty(int fd, unsigned baud)
{
    struct termios tio;
    speed_t speed = baud_to_speed(baud);

    if (!isatty(fd)) {
        return 0;
    }
    if (!speed || tcgetattr(fd, &tio) != 0) {
        return -1;
    }
    tio.c_iflag &= (tcflag_t)~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR |
                               IGNCR | ICRNL | IXON);
    tio.c_oflag &= (tcflag_t)~OPOST;
    tio.c_lflag &= (tcflag_t)~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    tio.c_cflag |= CLOCAL | CREAD;
    tio.c_cflag &= (tcflag_t)~(PARENB | CSTOPB);
#ifdef CRTSCTS
    tio.c_cflag &= (tcflag_t)~CRTSCTS;
#endif
    tio.c_cflag = (tio.c_cflag & ~CSIZE) | CS8;
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 10;
    if (cfsetispeed(&tio, speed) != 0 || cfsetospeed(&tio, speed) != 0) {
        return -1;
    }
    return tcsetattr(fd, TCSANOW, &tio);
}

static int nmea_coord_to_e7(const char *coord, char hemi, int *out)
{
    double raw;
    int deg;
    double minutes;
    double value;

    if (!coord || !*coord || !out) {
        return 0;
    }
    raw = strtod(coord, NULL);
    if (raw <= 0.0) {
        return 0;
    }
    deg = (int)(raw / 100.0);
    minutes = raw - (double)(deg * 100);
    if (deg < 0 || minutes < 0.0 || minutes >= 60.0) {
        return 0;
    }
    value = ((double)deg + minutes / 60.0) * 10000000.0;
    if (hemi == 'S' || hemi == 'W') {
        value = -value;
    } else if (hemi != 'N' && hemi != 'E') {
        return 0;
    }
    *out = (int)(value >= 0.0 ? value + 0.5 : value - 0.5);
    return 1;
}

static int split_nmea(char *line, char **fields, size_t cap)
{
    size_t count = 0u;
    char *star = strchr(line, '*');
    char *cursor = line;

    if (star) {
        *star = '\0';
    }
    while (count < cap) {
        fields[count++] = cursor;
        cursor = strchr(cursor, ',');
        if (!cursor) {
            break;
        }
        *cursor++ = '\0';
    }
    return (int)count;
}

static int parse_gga(char **fields, int count, struct gnss_fix *fix)
{
    int quality;

    if (count < 7 || !fields || !fix) {
        return 0;
    }
    quality = atoi(fields[6]);
    if (quality <= 0) {
        return 0;
    }
    return nmea_coord_to_e7(fields[2], fields[3][0], &fix->lat_e7) &&
           nmea_coord_to_e7(fields[4], fields[5][0], &fix->lon_e7);
}

static int parse_rmc(char **fields, int count, struct gnss_fix *fix)
{
    if (count < 7 || !fields || !fix || fields[2][0] != 'A') {
        return 0;
    }
    return nmea_coord_to_e7(fields[3], fields[4][0], &fix->lat_e7) &&
           nmea_coord_to_e7(fields[5], fields[6][0], &fix->lon_e7);
}

static int parse_nmea_fix(const char *line_in, struct gnss_fix *fix)
{
    char line[LINE_MAX_BYTES];
    char *fields[24];
    int count;
    const char *type;
    size_t len;

    if (!line_in || !fix) {
        return 0;
    }
    while (*line_in == '\r' || *line_in == '\n' || *line_in == ' ') {
        ++line_in;
    }
    if (*line_in != '$') {
        return 0;
    }
    len = strcspn(line_in, "\r\n");
    if (len >= sizeof(line)) {
        return 0;
    }
    memcpy(line, line_in, len);
    line[len] = '\0';
    count = split_nmea(line, fields, sizeof(fields) / sizeof(fields[0]));
    if (count <= 0 || strlen(fields[0]) < 6u) {
        return 0;
    }
    type = fields[0] + strlen(fields[0]) - 3u;
    if (strcmp(type, "GGA") == 0) {
        return parse_gga(fields, count, fix);
    }
    if (strcmp(type, "RMC") == 0) {
        return parse_rmc(fields, count, fix);
    }
    return 0;
}

static int send_rtls_report(const char *host,
                            unsigned port,
                            const char *eui,
                            const struct gnss_fix *fix)
{
    int sock;
    struct sockaddr_in dst;
    char request[REQUEST_MAX_BYTES];
    char response[RESPONSE_MAX_BYTES];
    int written;
    unsigned attempt;

    if (!host || !eui || !fix || port == 0u || port > 65535u) {
        return -1;
    }
    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        return -1;
    }
    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &dst.sin_addr) != 1) {
        close(sock);
        return -1;
    }
    written = snprintf(request, sizeof(request),
                       "FIELDMESH_RTLS_REPORT v1 node=%s gps_lock=1 "
                       "pps_lock=%u turnaround_calibrated=0 "
                       "gps_lat_e7=%d gps_lon_e7=%d "
                       "rssi_dbm=0 snr_db=0 measured_age_ms=0",
                       eui, fix->pps_lock ? 1u : 0u,
                       fix->lat_e7, fix->lon_e7);
    if (written <= 0 || (size_t)written >= sizeof(request)) {
        close(sock);
        return -1;
    }
    for (attempt = 0u; attempt < REPORT_ACK_RETRIES; ++attempt) {
        fd_set readfds;
        struct timeval timeout;
        ssize_t got;

        if (sendto(sock, request, (size_t)written, 0,
                   (const struct sockaddr *)&dst, sizeof(dst)) < 0) {
            close(sock);
            return -1;
        }
        FD_ZERO(&readfds);
        FD_SET(sock, &readfds);
        timeout.tv_sec = 0;
        timeout.tv_usec = REPORT_ACK_TIMEOUT_US;
        if (select(sock + 1, &readfds, NULL, NULL, &timeout) <= 0) {
            continue;
        }
        got = recv(sock, response, sizeof(response) - 1u, 0);
        if (got < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            close(sock);
            return -1;
        }
        response[got] = '\0';
        if (strstr(response, "\"ok\":true") || strstr(response, "\"ok\": true")) {
            close(sock);
            return 0;
        }
    }
    close(sock);
    return -1;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s DEVICE HOST PORT DEVICE_EUI [BAUD] [MAX_REPORTS] [PPS_LOCK]\n",
            argv0);
}

int main(int argc, char **argv)
{
    const char *device;
    const char *host;
    const char *eui;
    unsigned port;
    unsigned baud = 9600u;
    unsigned max_reports = 0u;
    unsigned reports = 0u;
    int pps_lock = 0;
    int fd;
    char read_buf[256];
    char line[LINE_MAX_BYTES];
    size_t line_len = 0u;

    if (argc < 5 || argc > 8) {
        usage(argv[0]);
        return 2;
    }
    device = argv[1];
    host = argv[2];
    port = (unsigned)strtoul(argv[3], NULL, 10);
    eui = argv[4];
    if (argc >= 6) {
        baud = (unsigned)strtoul(argv[5], NULL, 10);
    }
    if (argc >= 7) {
        max_reports = (unsigned)strtoul(argv[6], NULL, 10);
    }
    if (argc >= 8) {
        pps_lock = atoi(argv[7]) != 0;
    }
    if (!valid_eui(eui) || port == 0u || port > 65535u) {
        usage(argv[0]);
        return 2;
    }
    fd = open(device, O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        perror("open_gnss_device");
        return 1;
    }
    if (configure_serial_if_tty(fd, baud) != 0) {
        perror("configure_gnss_serial");
        close(fd);
        return 1;
    }

    while (max_reports == 0u || reports < max_reports) {
        fd_set readfds;
        struct timeval timeout;
        ssize_t got;

        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);
        timeout.tv_sec = 5;
        timeout.tv_usec = 0;
        if (select(fd + 1, &readfds, NULL, NULL, &timeout) <= 0) {
            continue;
        }
        got = read(fd, read_buf, sizeof(read_buf));
        if (got == 0) {
            break;
        }
        if (got < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                continue;
            }
            perror("read_gnss_device");
            close(fd);
            return 1;
        }
        for (ssize_t i = 0; i < got; ++i) {
            char ch = read_buf[i];
            if (ch == '\n' || ch == '\r') {
                struct gnss_fix fix;

                if (line_len == 0u) {
                    continue;
                }
                line[line_len] = '\0';
                memset(&fix, 0, sizeof(fix));
                fix.pps_lock = pps_lock;
                if (parse_nmea_fix(line, &fix) &&
                    send_rtls_report(host, port, eui, &fix) == 0) {
                    printf("{\"event\":\"fieldmesh_gnss_nmea_report\","
                           "\"ok\":true,\"device_eui\":\"%s\","
                           "\"gps_lock\":1,\"pps_lock\":%u,"
                           "\"gps_lat_e7\":%d,\"gps_lon_e7\":%d}\n",
                           eui, fix.pps_lock ? 1u : 0u,
                           fix.lat_e7, fix.lon_e7);
                    fflush(stdout);
                    ++reports;
                    if (max_reports != 0u && reports >= max_reports) {
                        close(fd);
                        return 0;
                    }
                }
                line_len = 0u;
                continue;
            }
            if (line_len + 1u < sizeof(line)) {
                line[line_len++] = ch;
            } else {
                line_len = 0u;
            }
        }
    }
    close(fd);
    return reports > 0u ? 0 : 1;
}
