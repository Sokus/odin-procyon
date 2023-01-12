package main

import "core:fmt"
import sdl2_net "vendor:sdl2/net"

main :: proc () {
    fmt.println("client started")
    sdl2_net.Init()
    socket := sdl2_net.UDP_Open(0)

    data := 4
    packet := sdl2_net.AllocPacket(size_of(data))
    sdl2_net.ResolveHost(&packet.address, "localhost", 50000)
    packet.data = cast(^u8)&data
    fmt.println("sending packet")
    sdl2_net.UDP_Send(socket, -1, packet)
    sdl2_net.FreePacket(packet)
    fmt.println("client exiting")
}

