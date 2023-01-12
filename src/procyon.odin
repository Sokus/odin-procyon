package main

import "shared:serialization"

main :: proc() {
    assert(bits_required(7) == 3)
    assert(bits_required(15) == 4)
    assert(bits_required(24) == 5)
    assert(bits_required(1 << 31 + 5) == 32)
}