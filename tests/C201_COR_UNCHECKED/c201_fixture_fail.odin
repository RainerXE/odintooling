package c201_test

import "core:os"
import "core:net"

// C201 violations: error returns ignored

bad_open :: proc() {
    os.open("foo.txt")                      // C201: open returns (Handle, Error)
}

bad_write :: proc() {
    h, _ := os.open("out.txt", os.O_WRONLY)
    os.write(h, []u8{1, 2, 3})              // C201: write returns (int, Error)
    os.close(h)                             // C201: close returns Error
}

bad_net :: proc() {
    net.dial_tcp("127.0.0.1:8080")          // C201: returns (net.TCP_Socket, net.Network_Error)
}
