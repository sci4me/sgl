package main

import "core:fmt"
import "core:os"
import "core:math"
import "core:mem"

import "shared:sgl"

rc: ^sgl.Render_Context;

t := 0.0;
projection: sgl.M4;

model_vbo: ^sgl.Buffer;
model_ibo: ^sgl.Buffer;

plane_vbo: ^sgl.Buffer;
plane_ibo: ^sgl.Buffer;

init :: proc() {
    rc = sgl.make_render_context(WIDTH, HEIGHT, vertex_shader_impl, fragment_shader_impl);

    projection = sgl.make_perspective(70, f64(WIDTH)/f64(HEIGHT), 0.1, 1000);

    data, ok := os.read_entire_file("models/icosphere.obj");
    if !ok do panic("Could not read model file");
    defer delete(data);

    model := sgl.load_obj_model(string(data));
    defer sgl.delete_obj_model(model);

    model_vbo = sgl.make_buffer(size_of(sgl.Vertex) * len(model.positions));
    model_ibo = sgl.make_buffer(size_of(int) * len(model.indices));

    for i in 0..<len(model.positions) do sgl.write_buffer_element(model_vbo, i, sgl.Vertex{model.positions[i], sgl.Color{1, 1, 1, 1}});
    for i in 0..<len(model.indices) do   sgl.write_buffer_element(model_ibo, i, model.indices[i].vertex_index);

    plane_vbo = sgl.make_buffer(size_of(sgl.Vertex) * 4);
    plane_ibo = sgl.make_buffer(size_of(int) * 6);

    sgl.write_buffer_element(plane_vbo, 0, sgl.Vertex{sgl.V4{-1, -1, 0, 1}, sgl.Color{0, 1, 0, 1}});
    sgl.write_buffer_element(plane_vbo, 1, sgl.Vertex{sgl.V4{-1,  1, 0, 1}, sgl.Color{0, 1, 0, 1}});
    sgl.write_buffer_element(plane_vbo, 2, sgl.Vertex{sgl.V4{ 1, -1, 0, 1}, sgl.Color{0, 1, 0, 1}});
    sgl.write_buffer_element(plane_vbo, 3, sgl.Vertex{sgl.V4{ 1,  1, 0, 1}, sgl.Color{0, 1, 0, 1}});
    sgl.write_buffer_element(plane_ibo, 0, 0);
    sgl.write_buffer_element(plane_ibo, 1, 1);
    sgl.write_buffer_element(plane_ibo, 2, 3);
    sgl.write_buffer_element(plane_ibo, 3, 0);
    sgl.write_buffer_element(plane_ibo, 4, 2);
    sgl.write_buffer_element(plane_ibo, 5, 3);
}

shutdown :: proc() {
    sgl.delete_render_context(rc);

    sgl.delete_buffer(model_vbo);
    sgl.delete_buffer(model_ibo);

    sgl.delete_buffer(plane_vbo);
    sgl.delete_buffer(plane_ibo);
}

tick :: proc(dt: f64) {
    t += 1 * dt;
}

draw_indexed :: proc(rc: ^sgl.Render_Context, vbo, ibo: ^sgl.Buffer, m: sgl.M4) {
    i := 0;
    for i < len(ibo.data) / size_of(int) {
        i0 := sgl.read_buffer_element(ibo, i, int);
        i1 := sgl.read_buffer_element(ibo, i+1, int);
        i2 := sgl.read_buffer_element(ibo, i+2, int);

        a := sgl.read_buffer_element(vbo, i0, sgl.Vertex);
        b := sgl.read_buffer_element(vbo, i1, sgl.Vertex);
        c := sgl.read_buffer_element(vbo, i2, sgl.Vertex);

        a.pos = sgl.mul(a.pos, m);
        b.pos = sgl.mul(b.pos, m);
        c.pos = sgl.mul(c.pos, m);

        sgl.fill_triangle(rc, a, b, c);

        i += 3;
    }
}

render :: proc(fb: ^sgl.Bitmap) {
    sgl.clear(rc, sgl.Color{0, 0, 0, 1});

    {
        translation := sgl.make_translation(sgl.V3{0, 0, 3 + math.sin(t)});
        rotation := sgl.make_rotation(sgl.V3{0, 0, 1}, t);

        m := sgl.mul(projection, sgl.mul(translation, rotation));

        draw_indexed(rc, model_vbo, model_ibo, m);
    }

    {
        translation := sgl.make_translation(sgl.V3{0, 0, 3});

        m := sgl.mul(projection, translation);

        draw_indexed(rc, plane_vbo, plane_ibo, m);
    }

    mem.copy(&fb.buffer.data[0], &rc.target.buffer.data[0], len(fb.buffer.data));
}

vertex_shader_impl :: proc(v: sgl.Vertex) -> sgl.Vertex {
    return v;
}

fragment_shader_impl :: proc(frag_uv: sgl.V2, color: sgl.Color) -> sgl.Color {
    return color;
}