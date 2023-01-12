package main

import "core:fmt"
import sdl2_net "vendor:sdl2/net"

main :: proc () {
    fmt.println("server started")
    sdl2_net.Init()
    socket := sdl2_net.UDP_Open(50000)

    packet : sdl2_net.UDPpacket
    for {
        if sdl2_net.UDP_Recv(socket, &packet) > 0 {
            fmt.println("packet received")
        }
    }
    // sdl2_net.FreePacket(packet)
    fmt.println("server xiting...")
}

