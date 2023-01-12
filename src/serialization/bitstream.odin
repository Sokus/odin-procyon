package serialization

BitStream_Base :: struct {
    data : []u32,
    num_bits : int,
    num_words : int,
    scratch : u64,
    scratch_bits : int,
    word_index : int,

}

WriteStream :: struct {
    using bit_stream : BitStream_Base,
    bits_written : int,
}

ReadStream :: struct {
    using bit_stream : BitStream_Base,
    bits_read : int,
}

MeasureStream :: struct {
    using bit_stream : BitStream_Base,
    bits_written : int,
}

BitStream :: union #no_nil { WriteStream, ReadStream, MeasureStream }

create_write_stream :: proc(buffer : []u8) -> WriteStream {
    assert(len(buffer) % 4 == 0)
    write_stream : WriteStream
    num_words := len(buffer) / 4
    write_stream.num_words = num_words
    write_stream.num_bits = num_words * 32
    write_stream.data = transmute([]u32)buffer
    return write_stream
}