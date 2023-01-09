package net

when ODIN_OS == .Windows {
    import "core:sys/windows"
}

// taken from ENet binding code
HOST_TO_NET_16 :: #force_inline proc(value: u16) -> u16 { return transmute(u16)u16be(value) }
HOST_TO_NET_32 :: #force_inline proc(value: u32) -> u32 { return transmute(u32)u32be(value) }
NET_TO_HOST_16 :: #force_inline proc(value: u16) -> u16 { return u16(transmute(u16be)value) }
NET_TO_HOST_32 :: #force_inline proc(value: u32) -> u32 { return u32(transmute(u32be)value) }

@(private)
network_initialized : bool = false

initialized :: proc() -> bool { return network_initialized }

init :: proc() -> bool {
    assert(!network_initialized)
    result : bool = true
    when ODIN_OS == .Windows {
        wsa_data : windows.LPWSADATA
        result = windows.WSAStartup(windows.MAKE_WORD(2, 2), wsa_data) == windows.NO_ERROR
    }
    if result {
        network_initialized = result
    }
    return result
}

shutdown :: proc() -> bool {
    assert(network_initialized)
    result : bool = true
    when ODIN_OS == .Windows {
        result = windows.WSACleanup() == 0;
    }
    network_initialized = false
    return result
}

windows.recvfrom