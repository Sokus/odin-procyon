package serialization

import "core:hash"
import "core:slice"

SerializationError :: enum {
    None,
    InvalidBitStreamMode,
    Overflow,
    InvalidCheckValue,
}

serialize_bits :: proc(s : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    switch s.mode {
        case .Write: return _serialize_bits_write_stream(s, value, bits)
        case .Read: return _serialize_bits_read_stream(s, value, bits)
        case .Measure: return _serialize_bits_measure_stream(s, value, bits)
        case: return SerializationError.InvalidBitStreamMode
    }
}

serialize_bytes :: proc(s : ^BitStream, bytes : []byte) -> SerializationError {
    num_bytes := len(bytes)
    assert(num_bytes > 0)
    serialize_align(s) or_return

    if s.mode == .Measure {
        s.bits_processed += num_bytes * 8
        return SerializationError.None
    }
    assert(s.mode == .Write || s.mode == .Read)
    assert(get_align_bits(s) == 0)
    assert(get_bits_remaining(s) >= len(bytes) * 8)

    num_head_bytes := (4 - (s.bits_processed % 32) / 8) % 4
    num_head_bytes = min(num_head_bytes, num_bytes)
    for i in 0..<num_head_bytes {
        byte_value : u32
        if s.mode == .Write { byte_value = u32(bytes[i]) }
        serialize_bits(s, &byte_value, 8) or_return
        if s.mode == .Read { bytes[i] = byte(byte_value) }
    }
    if num_head_bytes == num_bytes { return SerializationError.None }

    if s.mode == .Write { flush_bits(s) }

    num_middle_bytes := ((num_bytes - num_head_bytes) / 4) * 4
    if num_middle_bytes > 0 {
        assert(s.bits_processed % 32 == 0)
        middle_bytes_start := num_head_bytes
        middle_bytes_end := num_head_bytes + num_middle_bytes
        #partial switch s.mode {
            case .Write: copy_slice(slice.to_bytes(s.data[s.word_index:]), bytes[middle_bytes_start:middle_bytes_end])
            case .Read: copy_slice(bytes[middle_bytes_start:middle_bytes_end], slice.to_bytes(s.data[s.word_index:])) // fix
        }
        s.bits_processed += num_middle_bytes * 8
        s.word_index += num_middle_bytes / 4
        s.scratch = 0
    }

    num_tail_bytes := num_bytes - num_head_bytes - num_middle_bytes
    assert(num_tail_bytes >= 0 && num_tail_bytes < 4)
    tail_bytes_start := num_head_bytes + num_middle_bytes
    for i in 0..<num_tail_bytes {
        byte_value : u32
        if s.mode == .Write { byte_value = u32(bytes[tail_bytes_start + i]) }
        serialize_bits(s, &byte_value, 8) or_return
        if s.mode == .Read { bytes[tail_bytes_start + i] = byte(byte_value) }
    }
    assert(num_head_bytes + num_middle_bytes + num_tail_bytes == num_bytes)

    return SerializationError.None
}

serialize_align :: proc(s : ^BitStream) -> SerializationError {
    align_bits := get_align_bits(s)
    if align_bits > 0 {
        value : u32
        serialize_bits(s, &value, align_bits) or_return
        if s.mode == .Write {
            assert(s.bits_processed % 8 == 0)
        }
    }

    return SerializationError.None
}

serialize_check :: proc(s : ^BitStream, check : string) -> SerializationError {
    serialize_align(s) or_return
    switch s.mode {
        case .Write:
            magic := hash.fnv32a(transmute([]byte)check)
            return serialize_bits(s, &magic, 32)
        case .Read:
            magic := hash.fnv32a(transmute([]byte)check)
            value : u32
            serialize_bits(s, &value, 32) or_return
            if value != magic { return .InvalidCheckValue }
        case .Measure:
            value : u32
            serialize_bits(s, &value, 32) or_return
    }
    return .InvalidBitStreamMode
}