package serialization

bits_required :: proc(#any_int value : uint) -> int {
    if value > (uint(1) << 63) {
        return 64
    }
    pow : uint = 0
    for ;value > (1 << pow); pow += 1 {}
    return int(pow)
}

bits_required_for_range :: proc(min_value, max_value : $T) -> int {
    assert(min_value <= max_value)
    return 0 if min_value == max_value else bits_required(uint(max_value - min_value))
}

ptr_to_bytes :: proc "contextless" (ptr: ^$T, len := 1) -> []byte {
    return transmute([]byte)Raw_Slice{ptr, len*size_of(T)}
}