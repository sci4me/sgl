package sgl

import "core:runtime"

Bitmap :: struct {
    data: []Pixel,
    width, height: int,
}

make_bitmap :: proc(_width, _height: int) -> ^Bitmap {
    using b := new(Bitmap);
    data = make([]Pixel, _width * _height);
    width = _width;
    height = _height;
    return b;
}

delete_bitmap :: proc(using b: ^Bitmap) {
    delete(data);
    free(b);
}

draw_pixel :: inline proc(using b: ^Bitmap, x, y: int, color: Color) {
    data[x + y * width] = color_to_pixel(color);
}

clear_bitmap :: inline proc(using b: ^Bitmap, color: Color) {
    for i in 0..<len(data) do data[i] = color_to_pixel(color);
}