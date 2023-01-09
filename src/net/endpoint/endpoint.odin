package endpoint

when ODIN_OS == .Windows {
    import "core:sys/windows"
}


import "shared:net"

IPv4 :: distinct u32
IPv6 :: distinct [8]u16
Address :: union { IPv4, IPv6 }

Endpoint :: struct {
    address : Address,
    port : u16,
}

ipv4 :: proc (a, b, c, d : u8, port : u16) -> Endpoint {
    // TODO: Look if bit_sets could be of use here
    endpoint_address := transmute(IPv4)(u32(a) | u32(b) << 8 | u32(c) << 16 | u32(d) << 24)
    return Endpoint { endpoint_address, port }
}

ipv4_u32 :: proc (address : u32, port : u16) -> Endpoint {
    endpoint_address := transmute(IPv4)net.HOST_TO_NET_32(address)
    return Endpoint { endpoint_address, port }
}

ipv6 :: proc (a, b, c, d, e, f, g, h, port : u16) -> Endpoint {
    endpoint_address : IPv6
    endpoint_address[0] = net.HOST_TO_NET_16(a)
    endpoint_address[1] = net.HOST_TO_NET_16(b)
    endpoint_address[2] = net.HOST_TO_NET_16(c)
    endpoint_address[3] = net.HOST_TO_NET_16(d)
    endpoint_address[4] = net.HOST_TO_NET_16(e)
    endpoint_address[5] = net.HOST_TO_NET_16(f)
    endpoint_address[6] = net.HOST_TO_NET_16(g)
    return Endpoint { endpoint_address, port }
}



create :: proc{ipv4, ipv4_u32, ipv6}