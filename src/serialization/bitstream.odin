package serialization

import "core:fmt"

SerializationError :: enum {
    None,
    InvalidBitStreamMode,
    Overflow,
}

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

create_write_stream :: proc(buffer : []u8) -> BitStream {
    assert(len(buffer) % 4 == 0)
    write_stream : BitStream
    write_stream.mode = BitStreamMode.Write
    num_words := len(buffer) / 4
    write_stream.num_words = num_words
    write_stream.num_bits = num_words * 32
    write_stream.data = transmute([]u32)buffer
    return write_stream
}

create_read_stream :: proc(buffer : []u8, #any_int bytes : int) -> BitStream {
    assert(len(buffer) % 4 == 0)
    read_stream : BitStream
    read_stream.mode = BitStreamMode.Read
    read_stream.num_words = (bytes + 3) / 4
    read_stream.num_bits = bytes * 8
    read_stream.data = transmute([]u32)buffer
    return read_stream
}

create_measure_stream :: proc(#any_int bytes : int) -> BitStream {
    assert(bytes % 4 == 0)
    measure_stream : BitStream
    measure_stream.mode = BitStreamMode.Measure
    measure_stream.num_words = bytes / 4
    measure_stream.num_bits = bytes * 8
    return measure_stream
}

serialize_bits_write_stream :: proc(stream : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    using stream
    assert(stream.mode == BitStreamMode.Write)
    assert(value != nil)
    assert(bits > 0)
    assert(bits <= 32)
    assert(!would_overflow(stream, bits))

    if would_overflow(stream, bits) {
        return SerializationError.Overflow
    }

    write_value := value^ & cast(u32)((u64(1) << uint(bits)) - 1)
    scratch |= u64(write_value) << uint(scratch_bits)
    scratch_bits += bits

    if scratch_bits >= 32 {
        assert(word_index < num_words)
        data[word_index] = u32(scratch & 0xFFFFFFFF)
        scratch >>= 32
        scratch_bits -= 32
        word_index += 1
    }

    bits_processed += bits

    return SerializationError.None
}

serialize_bits_read_stream :: proc(stream : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    using stream
    assert(bits > 0)
    assert(bits <= 32)
    assert(scratch_bits >= 0)
    assert(scratch_bits <= 64)
    assert(stream.mode == BitStreamMode.Read)

    if would_overflow(stream, bits) {
        return SerializationError.Overflow
    }

    if (scratch_bits < bits)
    {
        assert(word_index < num_words)
        scratch |= u64(data[word_index]) << uint(scratch_bits)
        scratch_bits += 32
        word_index += 1
    }

    assert(scratch_bits >= bits)
    value^ = u32(scratch & ((u64(1) << uint(bits)) - 1))
    bits_processed += bits
    scratch >>= uint(bits)
    scratch_bits -= bits

    return SerializationError.None
}

serialize_bits_measure_stream :: proc(stream : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    assert(bits > 0)
    assert(bits <= 32)
    assert(stream.mode == BitStreamMode.Measure)
    stream.bits_processed += bits

    return SerializationError.None
}

serialize_bits :: proc(stream : ^BitStream, value : ^u32, #any_int bits : int) -> SerializationError {
    switch stream.mode {
        case .Write: return serialize_bits_write_stream(stream, value, bits)
        case .Read: return serialize_bits_read_stream(stream, value, bits)
        case .Measure: return serialize_bits_measure_stream(stream, value, bits)
    }
    return SerializationError.InvalidBitStreamMode
}

// serialize_bytes_write_stream :: proc(stream : ^WriteStream,

flush_bits :: proc(stream : ^BitStream) {
    assert(stream.mode == BitStreamMode.Write)
    using stream
    if scratch_bits != 0 {
        assert(word_index < num_words)
        data[word_index] = u32(scratch & 0xFFFFFFFF)
        word_index += 1
        scratch >>= 32
        scratch_bits -= 32
    }
}

would_overflow :: proc(stream : ^BitStream, #any_int bits : int) -> bool {
    return stream.bits_processed + bits > stream.num_bits
}

get_align_bits :: proc(stream : ^BitStream) -> int {
    return (8 - stream.bits_processed % 8) % 8
}

serialize_align_align :: proc(stream : ^BitStream) -> SerializationError {
    align_bits := get_align_bits(stream)
    if align_bits > 0 {
        value : u32
        serialize_bits(stream, &value, align_bits) or_return
        if stream.mode == .Write {
            assert(stream.bits_processed % 8 == 0)
        }
    }

    return SerializationError.None
}

get_bits_processed :: proc(stream : ^BitStream) -> int {
    return stream.bits_processed
}

get_bytes_processed :: proc(stream : ^BitStream) -> int {
    return (stream.bits_processed + 7) / 8
}

get_bits_remaining :: proc(stream : ^BitStream) -> int {
    return stream.num_bits - stream.bits_processed
}


