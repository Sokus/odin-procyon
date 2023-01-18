package serialization

import "core:fmt"
import "core:mem"

BitStreamMode :: enum {
    Write,
    Read,
    Measure,
}

BitStream :: struct {
    mode : BitStreamMode,
    data : []u32,
    num_bits : int,
    num_words : int,
    scratch : u64,
    scratch_bits : int,
    word_index : int,
    bits_processed : int,
}

create_write_stream :: proc(buffer : []byte) -> BitStream {
    assert(len(buffer) % 4 == 0, "BitStream buffer length not a multiple of 4 bytes")
    write_stream : BitStream
    write_stream.mode = .Write
    num_words := len(buffer) / 4
    write_stream.num_words = num_words
    write_stream.num_bits = num_words * 32
    write_stream.data = transmute([]u32)buffer
    return write_stream
}

create_read_stream :: proc(buffer : []byte, #any_int bytes : int) -> BitStream {
    assert(len(buffer) % 4 == 0)
    read_stream : BitStream
    read_stream.mode = .Read
    read_stream.num_words = (bytes + 3) / 4
    read_stream.num_bits = bytes * 8
    read_stream.data = transmute([]u32)buffer
    return read_stream
}

create_measure_stream :: proc(#any_int bytes : int) -> BitStream {
    assert(bytes % 4 == 0)
    measure_stream : BitStream
    measure_stream.mode = .Measure
    measure_stream.num_words = bytes / 4
    measure_stream.num_bits = bytes * 8
    return measure_stream
}

_serialize_bits_write_stream :: proc(s : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    assert(s.mode == .Write)
    assert(value != nil)
    assert(bits > 0)
    assert(bits <= 32)
    assert(!would_overflow(s, bits))

    if would_overflow(s, bits) {
        return SerializationError.Overflow
    }

    write_value := value^ & cast(u32)((u64(1) << uint(bits)) - 1)
    s.scratch |= u64(write_value) << uint(s.scratch_bits)
    s.scratch_bits += bits

    if s.scratch_bits >= 32 {
        assert(s.word_index < s.num_words)
        s.data[s.word_index] = u32(s.scratch & 0xFFFFFFFF)
        s.scratch >>= 32
        s.scratch_bits -= 32
        s.word_index += 1
    }

    s.bits_processed += bits

    return SerializationError.None
}

_serialize_bits_read_stream :: proc(s : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    assert(bits > 0)
    assert(bits <= 32)
    assert(s.scratch_bits >= 0)
    assert(s.scratch_bits <= 64)
    assert(s.mode == .Read)

    if would_overflow(s, bits) {
        return SerializationError.Overflow
    }

    if (s.scratch_bits < bits)
    {
        assert(s.word_index < s.num_words)
        s.scratch |= u64(s.data[s.word_index]) << uint(s.scratch_bits)
        s.scratch_bits += 32
        s.word_index += 1
    }

    assert(s.scratch_bits >= bits)
    value^ = u32(s.scratch & ((u64(1) << uint(bits)) - 1))
    s.bits_processed += bits
    s.scratch >>= uint(bits)
    s.scratch_bits -= bits

    return SerializationError.None
}

_serialize_bits_measure_stream :: proc(s : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    assert(bits > 0)
    assert(bits <= 32)
    assert(s.mode == .Measure)
    s.bits_processed += bits

    return SerializationError.None
}

would_overflow :: proc(s : ^BitStream, #any_int bits : int) -> bool {
    return s.bits_processed + bits > s.num_bits
}

get_bits_total :: proc(s : ^BitStream) -> int {
    return s.num_bits
}

get_bytes_total :: proc(s : ^BitStream) -> int {
    return s.num_bits / 8
}

get_bits_processed :: proc(s : ^BitStream) -> int {
    return s.bits_processed
}

get_bytes_processed :: proc(s : ^BitStream) -> int {
    return (s.bits_processed + 7) / 8
}

get_bits_remaining :: proc(s : ^BitStream) -> int {
    return s.num_bits - s.bits_processed
}

get_bytes_remaining :: proc(s : ^BitStream) -> int {
    return get_bytes_total(s) - get_bytes_processed(s)
}

get_align_bits :: proc(s : ^BitStream) -> int {
    return (8 - s.bits_processed % 8) % 8
}

flush_bits :: proc(s : ^BitStream) {
    assert(s.mode == .Write)
    if s.scratch_bits != 0 {
        assert(s.word_index < s.num_words)
        s.data[s.word_index] = u32(s.scratch & 0xFFFFFFFF)
        s.word_index += 1
        s.scratch >>= 32
        s.scratch_bits -= 32
    }
}