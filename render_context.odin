package sgl

import "core:fmt"
import "core:math"

Vertex :: struct {
    pos: V4,
    color: Color
}

Vertex_Shader :: #type proc(vertex: Vertex) -> Vertex;
Fragment_Shader :: #type proc(uv: V2, color: Color) -> Color;

Render_Context :: struct {
    target: ^Bitmap,
    depth_buffer: []f64,
    screen_space_transform: M4,
    vertex_shader: Vertex_Shader,
    fragment_shader: Fragment_Shader
}

make_render_context :: proc(width, height: int, _vertex_shader: Vertex_Shader, _fragment_shader: Fragment_Shader) -> ^Render_Context {
    using r := new(Render_Context);
    target = make_bitmap(width, height);
    depth_buffer = make([]f64, width * height);
    screen_space_transform = make_screen_space_transform(f64(width), f64(height));
    vertex_shader = _vertex_shader;
    fragment_shader = _fragment_shader;
    return r;
}

delete_render_context :: proc(using r: ^Render_Context) {
    destroy(target);
    delete(depth_buffer);
}

clear :: proc(using r: ^Render_Context, color: Color) {
    clear_bitmap(target, color);
    for i in 0..<len(depth_buffer) do depth_buffer[i] = math.F64_MAX;
}

draw_indexed :: proc(rc: ^Render_Context, vbo, ibo: ^Buffer, m: M4) {
    i := 0;
    for i < len(ibo.data) / size_of(int) {
        i0 := read_buffer_element(ibo, i, int);
        i1 := read_buffer_element(ibo, i+1, int);
        i2 := read_buffer_element(ibo, i+2, int);

        a := read_buffer_element(vbo, i0, Vertex);
        b := read_buffer_element(vbo, i1, Vertex);
        c := read_buffer_element(vbo, i2, Vertex);

        a.pos = mul(a.pos, m);
        b.pos = mul(b.pos, m);
        c.pos = mul(c.pos, m);

        fill_triangle(rc, a, b, c);

        i += 3;
    }
}

@private
fill_triangle :: proc(rc: ^Render_Context, a, b, c: Vertex) {
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

    calc_x_step :: inline proc(values: [3]f64, vertices: [3]V4, one_over_dx: f64) -> f64 {
        min := vertices[0];
        mid := vertices[1];
        max := vertices[2];
        return (((values[1] - values[2]) * (min.y - max.y)) - ((values[0] - values[2]) * (mid.y - max.y))) * one_over_dx;
    }

    calc_y_step :: inline proc(values: [3]f64, vertices: [3]V4, one_over_dy: f64) -> f64 {
        min := vertices[0];
        mid := vertices[1];
        max := vertices[2];
        return (((values[1] - values[2]) * (min.x - max.x)) - ((values[0] - values[2]) * (mid.x - max.x))) * one_over_dy;
    } 

    calc_color_step :: inline proc(values: [3]Color, vertices: [3]V4, s: f64, fn: proc(values: [3]f64, vertices: [3]V4, s: f64) -> f64) -> Color {
        return Color{
            fn({values[0].r, values[1].r, values[2].r}, vertices, s),
            fn({values[0].g, values[1].g, values[2].g}, vertices, s),
            fn({values[0].b, values[1].b, values[2].b}, vertices, s),
            fn({values[0].a, values[1].a, values[2].a}, vertices, s)
        };
    }

    make_gradients :: inline proc(min, mid, max: Vertex) -> Gradients {
        using g: Gradients;

        vertices := [3]Vertex{min, mid, max};
        positions := [3]V4{min.pos, mid.pos, max.pos};
        colors := [3]Color{min.color, mid.color, max.color};
        
        inline for i in 0..<3 do one_over_w[i] = 1 / positions[i].w;
        inline for i in 0..<3 do color[i] = mul_color(colors[i], one_over_w[i]);
        inline for i in 0..<3 do z[i] = positions[i].z;

        one_over_dx := 1 / ((mid.pos.x - max.pos.x) * (min.pos.y - max.pos.y) - (min.pos.x - max.pos.x) * (mid.pos.y - max.pos.y));
        one_over_dy := -one_over_dx;

        color_x_step = calc_color_step(color, positions, one_over_dx, calc_x_step);
        color_y_step = calc_color_step(color, positions, one_over_dy, calc_y_step);

        one_over_w_x_step = calc_x_step(one_over_w, positions, one_over_dx);
        one_over_w_y_step = calc_y_step(one_over_w, positions, one_over_dy);

        z_x_step = calc_x_step(z, positions, one_over_dx);
        z_y_step = calc_y_step(z, positions, one_over_dy);

        return g;
    }

    make_edge :: inline proc(gs: Gradients, start, end: V2, start_index: int) -> Edge {
        using edge: Edge;

        y_start = int(math.ceil(start.y));
        y_end =   int(math.ceil(end.y));

        x_dist := end.x - start.x;
        y_dist := end.y - start.y;
        y_prestep := f64(y_start) - start.y;

        x_step = x_dist / y_dist;
        x = start.x + y_prestep * x_step;

        x_prestep := x - start.x;

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

    draw_scan_line :: inline proc(rc: ^Render_Context, left, right: ^Edge, y: int) {
        x_min := int(math.ceil(left.x));
        x_max := int(math.ceil(right.x));
        x_dist := right.x - left.x;
        x_prestep := f64(x_min) - left.x;

        color_x_step := div_color(sub_color(right.color, left.color), x_dist);
        one_over_w_x_step := (right.one_over_w - left.one_over_w) / x_dist;
        z_x_step := (right.z - left.z) / x_dist;

        color := add_color(left.color, mul_color(color_x_step, x_prestep));
        one_over_w := left.one_over_w + one_over_w_x_step * x_prestep;
        z := left.z + z_x_step * x_prestep;

        for x in x_min..<x_max {
            i := x + y * rc.target.width;

            if z < rc.depth_buffer[i] {
                rc.depth_buffer[i] = z;

                w := 1 / one_over_w;
                real_color := mul_color(color, w);

                f := rc.fragment_shader(V2{f64(x) / f64(rc.target.width), f64(y) / f64(rc.target.height)}, real_color);

                draw_pixel(rc.target, x, y, f);
            }

            color = add_color(color, color_x_step);
            one_over_w += one_over_w_x_step;
            z += z_x_step;
        }
    }

    scan_edges :: inline proc(rc: ^Render_Context, a, b: ^Edge, handedness: bool) {
        left := a;
        right := b;

        if handedness do swap(&left, &right);

        y_start := b.y_start;
        y_end := b.y_end;
        for y in y_start..<y_end {
            draw_scan_line(rc, left, right, y);
            step(left);
            step(right);
        }
    }

    transform_and_perspective_divide_vertex :: inline proc(v: Vertex, m: M4) -> Vertex {
        perspective_divide :: inline proc(v: V4) -> V4 {
            return V4{
                v.x / v.w,
                v.y / v.w,
                v.z / v.w,
                v.w
            };
        }

        return Vertex{
            perspective_divide(mul(v.pos, m)),
            v.color
        };
    }

    as := rc.vertex_shader(a);
    bs := rc.vertex_shader(b);
    cs := rc.vertex_shader(c);

    min := transform_and_perspective_divide_vertex(as, rc.screen_space_transform);
    mid := transform_and_perspective_divide_vertex(bs, rc.screen_space_transform);
    max := transform_and_perspective_divide_vertex(cs, rc.screen_space_transform);

    if max.pos.y < mid.pos.y do swap(&max, &mid);
    if mid.pos.y < min.pos.y do swap(&mid, &min);
    if max.pos.y < mid.pos.y do swap(&max, &mid);

    handedness := triangle_area_times_two(swizzle(min.pos, 0, 1), swizzle(max.pos, 0, 1), swizzle(mid.pos, 0, 1)) > 0;
    
    gradients := make_gradients(min, mid, max);

    min_to_max := make_edge(gradients, swizzle(min.pos, 0, 1), swizzle(max.pos, 0, 1), 0);
    min_to_mid := make_edge(gradients, swizzle(min.pos, 0, 1), swizzle(mid.pos, 0, 1), 0);
    mid_to_max := make_edge(gradients, swizzle(mid.pos, 0, 1), swizzle(max.pos, 0, 1), 1);

    scan_edges(rc, &min_to_max, &min_to_mid, handedness);
    scan_edges(rc, &min_to_max, &mid_to_max, handedness);
}