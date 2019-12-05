package main

import "core:fmt"
import "core:os"
import "core:math"

import "shared:sgl"

t := 0.0;
projection: sgl.M4;

model_vertex_buffer: ^sgl.Buffer;
model_index_buffer: ^sgl.Buffer;

init :: proc() {
    projection = sgl.make_perspective(70, f64(WIDTH)/f64(HEIGHT), 0.1, 1000);

    data, ok := os.read_entire_file("models/icosphere.obj");
    if !ok do panic("Could not read model file");
    model := sgl.load_obj_model(string(data));
    defer sgl.delete_obj_model(model);

    model_vertex_buffer = sgl.make_buffer(size_of(sgl.Vertex) * len(model.positions));
    model_index_buffer = sgl.make_buffer(size_of(int) * len(model.indices));

    for i in 0..<len(model.positions) do sgl.write_buffer_element(model_vertex_buffer, i, sgl.Vertex{model.positions[i], sgl.Color{1, 1, 1, 1}});
    for i in 0..<len(model.indices) do  sgl.write_buffer_element(model_index_buffer, i, model.indices[i].vertex_index);
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

        a.color = sgl.Color{1, 0, 0, 1};
        b.color = sgl.Color{0, 1, 0, 1};
        c.color = sgl.Color{0, 0, 1, 1};

        sgl.fill_triangle(rc, a, b, c);

        i += 3;
    }
}

render :: proc(rc: ^sgl.Render_Context) {
    sgl.clear(rc, sgl.Color{0, 0, 0, 1});

    translation := sgl.make_translation(sgl.V3{0, 0, 3});
    rotation := sgl.make_rotation(sgl.V3{0, 1, 0}, t);

    m := sgl.mul(projection, sgl.mul(translation, rotation));

    draw_indexed(rc, model_vertex_buffer, model_index_buffer, m);
}