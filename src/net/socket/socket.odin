package odin

import "core:intrinsics"

import "core:sys/unix"

_unix_recvfrom :: proc(sd: int, buf: rawptr, len: uint, flags: int, addr: rawptr, alen: uintptr) -> i64 {
    return i64(intrinsics.syscall(unix.SYS_recvfrom, uintptr(sd), uintptr(buf), uintptr(len), uintptr(flags), uintptr(addr), uintptr(alen)))
}

/*
recvfrom :: proc(sd: Socket, data: []byte, flags: int, addr: ^SOCKADDR, addrlen: ^socklen_t) -> (u32, Errno) {
    result := _unix_recvfrom(int(sd), raw_data(data), len(data), flags, addr, uintptr(addrlen))
    if result < 0 {
        return 0, _get_errno(int(result))
    }
    return u32(result), ERROR_NONE
}

_unix_recvfrom :: proc(sd: int, buf: rawptr, len: uint, flags: int, addr: rawptr, alen: uintptr) -> i64 {
    return i64(intrinsics.syscall(unix.SYS_recvfrom, uintptr(sd), uintptr(buf), uintptr(len), uintptr(flags), uintptr(addr), uintptr(alen)))
}
*/