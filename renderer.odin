package sgl

import "core:math"
import "core:math/linalg"

Renderer :: struct {
    fb: ^Bitmap,
    screen_space_transform: M4
}

make_renderer :: proc(width, height: int) -> ^Renderer {
    using r := new(Renderer);
    fb = make_bitmap(width, height);
    screen_space_transform = make_screen_space_transform(f64(width), f64(height));
    return r;
}

delete_renderer :: proc(using r: ^Renderer) {
    delete_bitmap(fb);
}

clear :: proc(using r: ^Renderer, color: Color) {
    clear_bitmap(r.fb, color);
}

fill_triangle :: proc(r: ^Renderer, a, b, c: V4, color: Color) {
    Edge :: struct {
        x: f64,
        x_step: f64,
        y_start: int,
        y_end: int
    };

    make_edge :: inline proc(start, end: V4) -> Edge {
        using edge: Edge;

        y_start = int(math.ceil(start.y));
        y_end =   int(math.ceil(end.y));

        x_dist := end.x - start.x;
        y_dist := end.y - start.y;
        y_prestep := f64(y_start) - start.y;

        x_step = x_dist / y_dist;
        x = start.x + y_prestep * x_step;

        return edge;
    }

    step :: inline proc(using e: ^Edge) {
        x += x_step;
    }

    draw_scan_line :: inline proc(r: ^Renderer, left, right: Edge, y: int, color: Color) {
        x_min := int(math.ceil(left.x));
        x_max := int(math.ceil(right.x));

        for x in x_min..<x_max {
            r.fb.data[x + y * r.fb.width] = color;
        }
    }

    scan_edges :: inline proc(r: ^Renderer, a, b: Edge, handedness: bool, color: Color) {
        left := a;
        right := b;

        if handedness do swap(&left, &right);

        y_start := b.y_start;
        y_end := b.y_end;
        for y in y_start..<y_end {
            draw_scan_line(r, left, right, y, color);
            step(&left);
            step(&right);
        }
    }

    a_p, b_p, c_p := mul(a, r.screen_space_transform), mul(b, r.screen_space_transform), mul(c, r.screen_space_transform);
    min, mid, max := perspective_divide(a_p), perspective_divide(b_p), perspective_divide(c_p);

    if max.y < mid.y do swap(&max, &mid);
    if mid.y < min.y do swap(&mid, &min);
    if max.y < mid.y do swap(&max, &mid);

    handedness := linalg.cross2(V2{min.x - max.x, min.y - max.y}, V2{min.x - mid.x, min.y - max.y}) > 0;
    
    min_to_max := make_edge(min, max);
    min_to_mid := make_edge(min, mid);
    mid_to_max := make_edge(mid, max);

    scan_edges(r, min_to_max, min_to_mid, handedness, color);
    scan_edges(r, min_to_max, mid_to_max, handedness, color);
}