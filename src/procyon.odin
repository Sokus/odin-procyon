package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"

import "shared:serialization"

Foo :: struct{
    x, y : u8,
}

any_to_bytes :: #force_inline proc "contextless" (val: any) -> []byte {
    ti := type_info_of(val.id)
    size := ti != nil ? ti.size : 0
    return transmute([]byte)mem.Raw_Slice{val.data, size}
}

main :: proc() {
    test_structure := Foo{5, 8}
    bytes := any_to_bytes(test_structure)
    fmt.println(bytes) // [5, 8]

    stream : serialization.BitStream = serialization.create_measure_stream()
}