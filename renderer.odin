package sgl

import "core:math"
import "core:math/linalg"

Renderer :: struct {
    fb: ^Bitmap,
    scan_buffer: []int,
    screen_space_transform: M4
}

make_renderer :: proc(width, height: int) -> ^Renderer {
    using r := new(Renderer);
    fb = make_bitmap(width, height);
    scan_buffer = make([]int, height * 2);
    screen_space_transform = make_screen_space_transform(f64(width), f64(height));
    return r;
}

delete_renderer :: proc(using r: ^Renderer) {
    delete_bitmap(fb);
    delete(scan_buffer);
}

clear :: proc(using r: ^Renderer, color: Color) {
    clear_bitmap(r.fb, color);
}

@private
buffer_scan_line :: inline proc(scan_buffer: []int, y, x_min, x_max: int) {
    scan_buffer[y * 2 + 0] = x_min;
    scan_buffer[y * 2 + 1] = x_max;
}

@private
get_scan_line :: inline proc(scan_buffer: []int, y: int) -> (int, int) {
    return scan_buffer[y * 2 + 0], scan_buffer[y * 2 + 1];
}

@private
fill_shape :: inline proc(r: ^Renderer, scan_buffer: []int, y_min, y_max: int, color: Color) {
    for y in y_min..<y_max {
        x_min, x_max := get_scan_line(scan_buffer, y);
        
        for x in x_min..<x_max do r.fb.data[x + y * r.fb.width] = color;
    }
}

fill_triangle :: proc(r: ^Renderer, a, b, c: V4, color: Color) {
    scan_convert_line :: inline proc(r: ^Renderer, y_min_vert, y_max_vert: V4, side: int) {
        x_start := int(math.ceil(y_min_vert.x));
        y_start := int(math.ceil(y_min_vert.y));
        x_end :=   int(math.ceil(y_max_vert.x));
        y_end :=   int(math.ceil(y_max_vert.y));

        x_dist := y_max_vert.x - y_min_vert.x;
        y_dist := y_max_vert.y - y_min_vert.y;

        if y_dist <= 0 do return;

        x_step := x_dist / y_dist;
        y_prestep := f64(y_start) - y_min_vert.y;
        x := y_min_vert.x + y_prestep * x_step;

        for y in int(y_start)..<int(y_end) {
            r.scan_buffer[y * 2 + side] = int(math.ceil(x));
            x += x_step;
        }
    }

    scan_convert_triangle :: inline proc(r: ^Renderer, min, mid, max: V4, handedness: int) {
        scan_convert_line(r, min, max, handedness);
        scan_convert_line(r, min, mid, 1 - handedness);
        scan_convert_line(r, mid, max, 1 - handedness);
    }

    swap :: inline proc(a, b: ^$T) {
        temp := a^;
        a^ = b^;
        b^ = temp;
    }

    scan_buffer := r.scan_buffer;
    
    a_p, b_p, c_p := mul(a, r.screen_space_transform), mul(b, r.screen_space_transform), mul(c, r.screen_space_transform);
    min, mid, max := perspective_divide(a_p), perspective_divide(b_p), perspective_divide(c_p);

    if max.y < mid.y do swap(&max, &mid);
    if mid.y < min.y do swap(&mid, &min);
    if max.y < mid.y do swap(&max, &mid);

    f := linalg.cross2(V2{min.x - max.x, min.y - max.y}, V2{min.x - mid.x, min.y - max.y});

    scan_convert_triangle(r, min, mid, max, f > 0 ? 1 : 0);

    fill_shape(r, scan_buffer, int(math.ceil(min.y)), int(math.ceil(max.y)), color);
}