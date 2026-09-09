/* Join a Speed Dreams dedicated server as a player, far enough to prove the
 * roster logic: connect, send PLAYERINFO, report what comes back.
 *
 * The packet layout is PackedBuffer's, from NetClient::SendDriverInfoPacket:
 * a ubyte tag, then ints in network byte order, fixed-size raw char arrays for
 * the strings, and floats as htonl'd IEEE-754.
 */
#include <enet/enet.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define PLAYERINFO_PACKET   2
#define PLAYERREJECTED      17
#define PLAYERACCEPTED      18
#define RELIABLECHANNEL     1

static unsigned char buf[2048];
static size_t len;

static void p_ubyte(unsigned char v) { buf[len++] = v; }

static void p_int(int v)
{
    enet_uint32 x = htonl((enet_uint32)v);
    memcpy(buf + len, &x, 4);
    len += 4;
}

static void p_float(float v)
{
    union { float f; enet_uint32 i; } u;
    u.f = v;
    enet_uint32 x = htonl(u.i);
    memcpy(buf + len, &x, 4);
    len += 4;
}

/* Fixed-width field, zero padded - pack_string copies the whole array. */
static void p_str(const char* s, int width)
{
    memset(buf + len, 0, width);
    if (s) strncpy((char*)(buf + len), s, width - 1);
    len += width;
}

int main(int argc, char** argv)
{
    const char* host = argc > 1 ? argv[1] : "127.0.0.1";
    int         port = argc > 2 ? atoi(argv[2]) : 28500;
    const char* name = argc > 3 ? argv[3] : "TestPlayer";
    int         idx  = argc > 4 ? atoi(argv[4]) : 1;
    int         hold = argc > 5 ? atoi(argv[5]) : 6;

    if (enet_initialize() != 0) { puts("enet init failed"); return 2; }

    ENetHost* h = enet_host_create(NULL, 1, 2, 0, 0);
    ENetAddress addr;
    enet_address_set_host(&addr, host);
    addr.port = (enet_uint16)port;

    ENetPeer* peer = enet_host_connect(h, &addr, 2, 0);
    ENetEvent ev;
    if (!(enet_host_service(h, &ev, 5000) > 0 && ev.type == ENET_EVENT_TYPE_CONNECT))
    {
        printf("no connection to %s:%d\n", host, port);
        return 1;
    }
    printf("connected to %s:%d\n", host, port);

    len = 0;
    p_ubyte(PLAYERINFO_PACKET);
    p_int(idx);
    p_str(name, 64);            /* name       */
    p_str(name, 64);            /* sname      */
    p_str("TST", 4);            /* cname      */
    p_str("sc-cavallo-360", 64);/* car        */
    p_str("Probe", 64);         /* team       */
    p_str("probe", 64);         /* author     */
    p_int(7);                   /* racenumber */
    p_str("rookie", 64);        /* skilllevel */
    p_float(1.0f); p_float(0.0f); p_float(0.0f);
    p_str("networkhuman", 64);  /* module     */
    p_str("human", 64);         /* type       */
    p_int(1);                   /* client     */

    printf("sending PLAYERINFO (%zu bytes) as '%s' idx %d\n", len, name, idx);
    enet_peer_send(peer, RELIABLECHANNEL,
                   enet_packet_create(buf, len, ENET_PACKET_FLAG_RELIABLE));
    enet_host_flush(h);

    /* Stay connected so the server keeps us on the roster while it is watched. */
    int waited = 0;
    while (waited < hold * 1000)
    {
        if (enet_host_service(h, &ev, 200) > 0 && ev.type == ENET_EVENT_TYPE_RECEIVE)
        {
            unsigned char tag = ev.packet->data[0];
            if (tag == PLAYERACCEPTED)      puts("server: ACCEPTED");
            else if (tag == PLAYERREJECTED) puts("server: REJECTED");
            else printf("server: packet type %u (%zu bytes)\n", tag, ev.packet->dataLength);
            enet_packet_destroy(ev.packet);
        }
        waited += 200;
    }

    enet_peer_disconnect(peer, 0);
    while (enet_host_service(h, &ev, 1000) > 0)
        if (ev.type == ENET_EVENT_TYPE_DISCONNECT) break;

    enet_host_destroy(h);
    enet_deinitialize();
    return 0;
}
