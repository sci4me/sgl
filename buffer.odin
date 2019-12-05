package sgl

Buffer :: struct {
    data: []u8
}

make_buffer :: proc(size: int) -> ^Buffer {
    using b := new(Buffer);
    data = make([]u8, size);
    return b;
}

delete_buffer :: proc(using b: ^Buffer) {
    delete(data);
    free(b);
}

read_buffer_element :: proc(using b: ^Buffer, element: int, $T: typeid) -> T {
    offset := size_of(T) * element;
    ptr := transmute(^T) rawptr(uintptr(&data[0]) + uintptr(offset));
    return ptr^;
}

write_buffer_element :: proc(using b: ^Buffer, element: int, value: $T) {
    offset := size_of(T) * element;
    ptr := transmute(^T) rawptr(uintptr(&data[0]) + uintptr(offset));
    ptr^ = value;
}