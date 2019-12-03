package sgl

import "core:fmt"
import "core:math"
import "core:math/linalg"

Renderer :: struct {
    fb: ^Bitmap,
    depth_buffer: []f64,
    screen_space_transform: M4
}

make_renderer :: proc(width, height: int) -> ^Renderer {
    using r := new(Renderer);
    fb = make_bitmap(width, height);
    depth_buffer = make([]f64, width * height);
    screen_space_transform = make_screen_space_transform(f64(width), f64(height));
    return r;
}

delete_renderer :: proc(using r: ^Renderer) {
    delete_bitmap(fb);
    delete(depth_buffer);
}

clear :: proc(using r: ^Renderer, color: Color) {
    clear_bitmap(r.fb, color);
    for i in 0..<len(depth_buffer) do depth_buffer[i] = math.F64_MAX;
}

fill_triangle :: proc(r: ^Renderer, a, b, c: Vertex) {
    Edge :: struct {
        x: f64,
        x_step: f64,
        y_start: int,
        y_end: int,
        color: Color,
        color_step: Color,
        one_over_w: f64,
        one_over_w_step: f64,
        z: f64,
        z_step: f64
    };

    Gradients :: struct {
        color: [3]Color,
        one_over_w: [3]f64,
        z: [3]f64,
        color_x_step: Color,
        color_y_step: Color,
        one_over_w_x_step: f64,
        one_over_w_y_step: f64,
        z_x_step: f64,
        z_y_step: f64
    };

    calc_x_step :: inline proc(values: [3]f64, min, mid, max: V4, one_over_dx: f64) -> f64 {
        return (((values[1] - values[2]) * (min.y - max.y)) - ((values[0] - values[2]) * (mid.y - max.y))) * one_over_dx;
    }

    calc_y_step :: inline proc(values: [3]f64, min, mid, max: V4, one_over_dy: f64) -> f64 {
        return (((values[1] - values[2]) * (min.x - max.x)) - ((values[0] - values[2]) * (mid.x - max.x))) * one_over_dy;
    } 

    calc_color_step :: inline proc(values: [3]Color, min, mid, max: V4, s: f64, fn: proc(values: [3]f64, min, mid, max: V4, s: f64) -> f64) -> Color {
        return Color{
            fn({values[0].r, values[1].r, values[2].r}, min, mid, max, s),
            fn({values[0].g, values[1].g, values[2].g}, min, mid, max, s),
            fn({values[0].b, values[1].b, values[2].b}, min, mid, max, s),
            fn({values[0].a, values[1].a, values[2].a}, min, mid, max, s)
        };
    }

    make_gradients :: inline proc(min, mid, max: Vertex) -> Gradients {
        using g: Gradients;

        one_over_dx := 1 / ((mid.pos.x - max.pos.x) * (min.pos.y - max.pos.y) - (min.pos.x - max.pos.x) * (mid.pos.y - max.pos.y));
        one_over_dy := -one_over_dx;

        one_over_w[0] = 1 / min.pos.w;
        one_over_w[1] = 1 / mid.pos.w;
        one_over_w[2] = 1 / max.pos.w;

        color[0] = mul_color(min.color, one_over_w[0]);
        color[1] = mul_color(mid.color, one_over_w[1]);
        color[2] = mul_color(max.color, one_over_w[2]);

        z[0] = min.pos.z;
        z[1] = mid.pos.z;
        z[2] = max.pos.z;

        color_x_step = calc_color_step(color, min.pos, mid.pos, max.pos, one_over_dx, calc_x_step);
        color_y_step = calc_color_step(color, min.pos, mid.pos, max.pos, one_over_dy, calc_y_step);

        one_over_w_x_step = calc_x_step(one_over_w, min.pos, mid.pos, max.pos, one_over_dx);
        one_over_w_y_step = calc_y_step(one_over_w, min.pos, mid.pos, max.pos, one_over_dy);

        z_x_step = calc_x_step(z, min.pos, mid.pos, max.pos, one_over_dx);
        z_y_step = calc_y_step(z, min.pos, mid.pos, max.pos, one_over_dy);

        return g;
    }

    make_edge :: inline proc(gs: Gradients, start, end: V4, start_index: int) -> Edge {
        using edge: Edge;

        y_start = int(math.ceil(start.y));
        y_end =   int(math.ceil(end.y));

        x_dist := end.x - start.x;
        y_dist := end.y - start.y;
        x_prestep := f64(int(start.x)) - start.x;
        y_prestep := f64(y_start) - start.y;

        x_step = x_dist / y_dist;
        x = start.x + y_prestep * x_step;

        color = add_color(gs.color[start_index], add_color(mul_color(gs.color_x_step, x_prestep), mul_color(gs.color_y_step, y_prestep)));
        color_step = add_color(mul_color(gs.color_x_step, x_step), gs.color_y_step);

        one_over_w = gs.one_over_w[start_index] + gs.one_over_w_x_step * x_prestep + gs.one_over_w_y_step * y_prestep;
        one_over_w_step = gs.one_over_w_y_step + gs.one_over_w_x_step * x_step;

        z = gs.z[start_index] + gs.z_x_step * x_prestep + gs.z_y_step * y_prestep;
        z_step = gs.z_y_step + gs.z_x_step * x_step;

        return edge;
    }

    step :: inline proc(using e: ^Edge) {
        x += x_step;
        color = add_color(color, color_step);
        one_over_w += one_over_w_step;
        z += z_step;
    }

    draw_scan_line :: inline proc(r: ^Renderer, left, right: Edge, y: int) {
        x_min := int(math.ceil(left.x));
        x_max := int(math.ceil(right.x));
        x_dist := right.x - left.x;
        x_prestep := f64(x_min) - left.x;

        color_x_step := mul_color(sub_color(right.color, left.color), 1 / x_dist);
        one_over_w_x_step := (right.one_over_w - left.one_over_w) / x_dist;
        z_x_step := (right.z - left.z) / x_dist;

        color := add_color(left.color, mul_color(color_x_step, x_prestep));
        one_over_w := left.one_over_w + one_over_w_x_step * x_prestep;
        z := left.z + z_x_step * x_prestep;

        for x in x_min..<x_max {
            i := x + y * r.fb.width;
            if z < r.depth_buffer[i] {
                r.depth_buffer[i] = z;

                w := 1 / one_over_w;
                draw_pixel(r.fb, x, y, mul_color(color, w));
            }

            color = add_color(color, color_x_step);
            one_over_w += one_over_w_x_step;
            z += z_x_step;
        }
    }

    scan_edges :: inline proc(r: ^Renderer, a, b: Edge, handedness: bool) {
        left := a;
        right := b;

        if handedness do swap(&left, &right);

        y_start := b.y_start;
        y_end := b.y_end;
        for y in y_start..<y_end {
            draw_scan_line(r, left, right, y);
            step(&left);
            step(&right);
        }
    }

    transform_and_perspective_divide_vertex :: inline proc(v: Vertex, m: M4) -> Vertex {
        return Vertex{
            perspective_divide(mul(v.pos, m)),
            v.color
        };
    }

    min := transform_and_perspective_divide_vertex(a, r.screen_space_transform);
    mid := transform_and_perspective_divide_vertex(b, r.screen_space_transform);
    max := transform_and_perspective_divide_vertex(c, r.screen_space_transform);

    if max.pos.y < mid.pos.y do swap(&max, &mid);
    if mid.pos.y < min.pos.y do swap(&mid, &min);
    if max.pos.y < mid.pos.y do swap(&max, &mid);

    handedness := linalg.cross2(V2{min.pos.x - max.pos.x, min.pos.y - max.pos.y}, V2{min.pos.x - mid.pos.x, min.pos.y - max.pos.y}) > 0;
    
    gradients := make_gradients(min, mid, max);

    min_to_max := make_edge(gradients, min.pos, max.pos, 0);
    min_to_mid := make_edge(gradients, min.pos, mid.pos, 0);
    mid_to_max := make_edge(gradients, mid.pos, max.pos, 1);

    scan_edges(r, min_to_max, min_to_mid, handedness);
    scan_edges(r, min_to_max, mid_to_max, handedness);
}