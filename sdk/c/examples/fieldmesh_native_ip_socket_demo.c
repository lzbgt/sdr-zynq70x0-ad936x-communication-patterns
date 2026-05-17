#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#define SOCKET_DEMO_MAX_PAYLOAD 512u
#define SOCKET_DEMO_BACKLOG 1
#define SOCKET_DEMO_RETRY_SLICE_MS 250u

static void sleep_ms(unsigned delay_ms)
{
    struct timeval tv;

    tv.tv_sec = (time_t)(delay_ms / 1000u);
    tv.tv_usec = (suseconds_t)((delay_ms % 1000u) * 1000u);
    (void)select(0, NULL, NULL, NULL, &tv);
}

static int retryable_connect_error(int err)
{
    return err == ECONNREFUSED || err == ETIMEDOUT || err == EHOSTUNREACH ||
           err == ENETUNREACH || err == EAGAIN || err == EINTR;
}

static int parse_port(const char *text)
{
    char *end = NULL;
    long value;

    if (!text) {
        return -1;
    }
    errno = 0;
    value = strtol(text, &end, 10);
    if (errno != 0 || !end || *end != '\0' || value < 1 || value > 65535) {
        return -1;
    }
    return (int)value;
}

static int wait_fd(int fd, int want_write, unsigned timeout_ms)
{
    fd_set fds;
    struct timeval tv;
    int rc;

    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    tv.tv_sec = (time_t)(timeout_ms / 1000u);
    tv.tv_usec = (suseconds_t)((timeout_ms % 1000u) * 1000u);
    rc = select(fd + 1, want_write ? NULL : &fds, want_write ? &fds : NULL,
                NULL, &tv);
    if (rc == 0) {
        return ETIMEDOUT;
    }
    if (rc < 0) {
        return errno;
    }
    return 0;
}

static int make_addr(const char *ip, int port, struct sockaddr_in *addr)
{
    if (!ip || !addr || port < 1 || port > 65535) {
        return EINVAL;
    }
    memset(addr, 0, sizeof(*addr));
    addr->sin_family = AF_INET;
    addr->sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, ip, &addr->sin_addr) != 1) {
        return EINVAL;
    }
    return 0;
}

static void print_report(const char *mode,
                         int ok,
                         const char *bind_ip,
                         const char *peer_ip,
                         int port,
                         ssize_t bytes_sent,
                         ssize_t bytes_received,
                         int err)
{
    printf("{\"event\":\"fieldmesh_native_ip_socket_demo\","
           "\"ok\":%s,"
           "\"mode\":\"%s\","
           "\"bind_ip\":\"%s\","
           "\"peer_ip\":\"%s\","
           "\"port\":%d,"
           "\"bytes_sent\":%ld,"
           "\"bytes_received\":%ld,"
           "\"errno_value\":%d,"
           "\"uses_fieldmesh_sdk\":0,"
           "\"uses_normal_tcp_udp_sockets\":1}\n",
           ok ? "true" : "false", mode ? mode : "",
           bind_ip ? bind_ip : "", peer_ip ? peer_ip : "", port,
           (long)bytes_sent, (long)bytes_received, err);
}

static int tcp_server(const char *bind_ip, int port, unsigned timeout_ms)
{
    int fd = -1;
    int client = -1;
    int one = 1;
    struct sockaddr_in addr;
    unsigned char payload[SOCKET_DEMO_MAX_PAYLOAD];
    ssize_t got;
    ssize_t sent;
    int err;

    err = make_addr(bind_ip, port, &addr);
    if (err != 0) {
        print_report("tcp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        err = errno;
        print_report("tcp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (bind(fd, (const struct sockaddr *)&addr, sizeof(addr)) != 0 ||
        listen(fd, SOCKET_DEMO_BACKLOG) != 0) {
        err = errno;
        close(fd);
        print_report("tcp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    err = wait_fd(fd, 0, timeout_ms);
    if (err != 0) {
        close(fd);
        print_report("tcp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    client = accept(fd, NULL, NULL);
    if (client < 0) {
        err = errno;
        close(fd);
        print_report("tcp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    err = wait_fd(client, 0, timeout_ms);
    if (err != 0) {
        close(client);
        close(fd);
        print_report("tcp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    got = recv(client, payload, sizeof(payload), 0);
    if (got <= 0) {
        err = got == 0 ? ECONNRESET : errno;
        close(client);
        close(fd);
        print_report("tcp-server", 0, bind_ip, NULL, port, 0, got, err);
        return 1;
    }
    sent = send(client, payload, (size_t)got, 0);
    err = sent == got ? 0 : errno;
    close(client);
    close(fd);
    print_report("tcp-server", sent == got, bind_ip, NULL, port, sent, got, err);
    return sent == got ? 0 : 1;
}

static int tcp_client(const char *peer_ip, int port, const char *message,
                      unsigned timeout_ms)
{
    int fd = -1;
    struct sockaddr_in addr;
    unsigned char echo[SOCKET_DEMO_MAX_PAYLOAD];
    size_t message_len;
    ssize_t sent;
    ssize_t got;
    int err;
    unsigned attempt;
    unsigned attempts;

    message_len = strlen(message);
    if (message_len == 0u || message_len > sizeof(echo)) {
        print_report("tcp-client", 0, NULL, peer_ip, port, 0, 0, EMSGSIZE);
        return 1;
    }
    err = make_addr(peer_ip, port, &addr);
    if (err != 0) {
        print_report("tcp-client", 0, NULL, peer_ip, port, 0, 0, err);
        return 1;
    }
    attempts = timeout_ms / SOCKET_DEMO_RETRY_SLICE_MS;
    if (attempts == 0u) {
        attempts = 1u;
    }
    err = 0;
    for (attempt = 0; attempt < attempts; ++attempt) {
        fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) {
            err = errno;
            print_report("tcp-client", 0, NULL, peer_ip, port, 0, 0, err);
            return 1;
        }
        if (connect(fd, (const struct sockaddr *)&addr, sizeof(addr)) == 0) {
            break;
        }
        err = errno;
        close(fd);
        fd = -1;
        if (!retryable_connect_error(err) || attempt + 1u == attempts) {
            print_report("tcp-client", 0, NULL, peer_ip, port, 0, 0, err);
            return 1;
        }
        sleep_ms(SOCKET_DEMO_RETRY_SLICE_MS);
    }
    if (fd < 0) {
        print_report("tcp-client", 0, NULL, peer_ip, port, 0, 0, err);
        return 1;
    }
    sent = send(fd, message, message_len, 0);
    if (sent != (ssize_t)message_len) {
        err = errno;
        close(fd);
        print_report("tcp-client", 0, NULL, peer_ip, port, sent, 0, err);
        return 1;
    }
    err = wait_fd(fd, 0, timeout_ms);
    if (err != 0) {
        close(fd);
        print_report("tcp-client", 0, NULL, peer_ip, port, sent, 0, err);
        return 1;
    }
    got = recv(fd, echo, sizeof(echo), 0);
    err = got == (ssize_t)message_len &&
                  memcmp(echo, message, message_len) == 0 ?
              0 : EPROTO;
    close(fd);
    print_report("tcp-client", err == 0, NULL, peer_ip, port, sent, got, err);
    return err == 0 ? 0 : 1;
}

static int udp_server(const char *bind_ip, int port, unsigned timeout_ms)
{
    int fd;
    int one = 1;
    struct sockaddr_in addr;
    struct sockaddr_in peer;
    socklen_t peer_len = sizeof(peer);
    unsigned char payload[SOCKET_DEMO_MAX_PAYLOAD];
    ssize_t got;
    ssize_t sent;
    char peer_text[INET_ADDRSTRLEN];
    int err;

    err = make_addr(bind_ip, port, &addr);
    if (err != 0) {
        print_report("udp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        err = errno;
        print_report("udp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (bind(fd, (const struct sockaddr *)&addr, sizeof(addr)) != 0) {
        err = errno;
        close(fd);
        print_report("udp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    err = wait_fd(fd, 0, timeout_ms);
    if (err != 0) {
        close(fd);
        print_report("udp-server", 0, bind_ip, NULL, port, 0, 0, err);
        return 1;
    }
    got = recvfrom(fd, payload, sizeof(payload), 0,
                   (struct sockaddr *)&peer, &peer_len);
    if (got <= 0) {
        err = got == 0 ? EPROTO : errno;
        close(fd);
        print_report("udp-server", 0, bind_ip, NULL, port, 0, got, err);
        return 1;
    }
    sent = sendto(fd, payload, (size_t)got, 0,
                  (const struct sockaddr *)&peer, peer_len);
    err = sent == got ? 0 : errno;
    inet_ntop(AF_INET, &peer.sin_addr, peer_text, sizeof(peer_text));
    close(fd);
    print_report("udp-server", sent == got, bind_ip, peer_text, port, sent, got,
                 err);
    return sent == got ? 0 : 1;
}

static int udp_client(const char *peer_ip, int port, const char *message,
                      unsigned timeout_ms)
{
    int fd;
    struct sockaddr_in addr;
    unsigned char echo[SOCKET_DEMO_MAX_PAYLOAD];
    size_t message_len;
    ssize_t sent;
    ssize_t got;
    int err;
    unsigned attempt;
    unsigned attempts;
    unsigned wait_ms;
    ssize_t total_sent = 0;

    message_len = strlen(message);
    if (message_len == 0u || message_len > sizeof(echo)) {
        print_report("udp-client", 0, NULL, peer_ip, port, 0, 0, EMSGSIZE);
        return 1;
    }
    err = make_addr(peer_ip, port, &addr);
    if (err != 0) {
        print_report("udp-client", 0, NULL, peer_ip, port, 0, 0, err);
        return 1;
    }
    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        err = errno;
        print_report("udp-client", 0, NULL, peer_ip, port, 0, 0, err);
        return 1;
    }
    attempts = timeout_ms / SOCKET_DEMO_RETRY_SLICE_MS;
    if (attempts == 0u) {
        attempts = 1u;
    }
    wait_ms = timeout_ms < 1000u ? timeout_ms : 1000u;
    err = ETIMEDOUT;
    got = 0;
    for (attempt = 0; attempt < attempts; ++attempt) {
        sent = sendto(fd, message, message_len, 0,
                      (const struct sockaddr *)&addr, sizeof(addr));
        if (sent != (ssize_t)message_len) {
            err = errno;
            close(fd);
            print_report("udp-client", 0, NULL, peer_ip, port, total_sent, 0,
                         err);
            return 1;
        }
        total_sent += sent;
        err = wait_fd(fd, 0, wait_ms);
        if (err != 0) {
            continue;
        }
        got = recv(fd, echo, sizeof(echo), 0);
        err = got == (ssize_t)message_len &&
                      memcmp(echo, message, message_len) == 0 ?
                  0 : EPROTO;
        break;
    }
    close(fd);
    print_report("udp-client", err == 0, NULL, peer_ip, port, total_sent, got,
                 err);
    return err == 0 ? 0 : 1;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "Usage:\n"
            "  %s tcp-server <bind-ip> <port> [timeout-ms]\n"
            "  %s tcp-client <peer-ip> <port> <message> [timeout-ms]\n"
            "  %s udp-server <bind-ip> <port> [timeout-ms]\n"
            "  %s udp-client <peer-ip> <port> <message> [timeout-ms]\n",
            argv0, argv0, argv0, argv0);
}

int main(int argc, char **argv)
{
    const char *mode;
    int port;
    unsigned timeout_ms = 8000u;

    if (argc == 1) {
        printf("{\"event\":\"fieldmesh_native_ip_socket_demo\","
               "\"ok\":true,"
               "\"mode\":\"self-test\","
               "\"supports_tcp_client\":1,"
               "\"supports_tcp_server\":1,"
               "\"supports_udp_client\":1,"
               "\"supports_udp_server\":1,"
               "\"uses_fieldmesh_sdk\":0,"
               "\"uses_normal_tcp_udp_sockets\":1}\n");
        return 0;
    }
    if (argc < 4) {
        usage(argv[0]);
        return 2;
    }
    mode = argv[1];
    port = parse_port(argv[3]);
    if (port < 0) {
        usage(argv[0]);
        return 2;
    }
    if ((strcmp(mode, "tcp-client") == 0 || strcmp(mode, "udp-client") == 0)) {
        if (argc < 5) {
            usage(argv[0]);
            return 2;
        }
        if (argc > 5) {
            timeout_ms = (unsigned)strtoul(argv[5], NULL, 10);
        }
    } else if (argc > 4) {
        timeout_ms = (unsigned)strtoul(argv[4], NULL, 10);
    }
    if (timeout_ms == 0u) {
        timeout_ms = 8000u;
    }

    if (strcmp(mode, "tcp-server") == 0) {
        return tcp_server(argv[2], port, timeout_ms);
    }
    if (strcmp(mode, "tcp-client") == 0) {
        return tcp_client(argv[2], port, argv[4], timeout_ms);
    }
    if (strcmp(mode, "udp-server") == 0) {
        return udp_server(argv[2], port, timeout_ms);
    }
    if (strcmp(mode, "udp-client") == 0) {
        return udp_client(argv[2], port, argv[4], timeout_ms);
    }
    usage(argv[0]);
    return 2;
}
