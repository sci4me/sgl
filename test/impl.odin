package main

import "core:math"

import "shared:sgl"

t := 0.0;
projection: sgl.M4;

init :: proc() {
    projection = sgl.make_perspective(70, f64(WIDTH)/f64(HEIGHT), 0.1, 1000);
}

tick :: proc(dt: f64) {
    t += 1.5 * dt;
}

render :: proc(r: ^sgl.Renderer) {
    sgl.clear(r, sgl.Color{0, 0, 0, 1});

    {
        a := sgl.V4{-1, -1, 0, 1};
        b := sgl.V4{-1, 1, 0, 1};
        c := sgl.V4{1, 1, 0, 1};
        d := sgl.V4{1, -1, 0, 1};        

        translation := sgl.make_translation(sgl.V3{0, 0, 3.5});
        
        m := sgl.mul(projection, translation);

        color := sgl.Color{0, 1, 0, 1};

        sgl.fill_triangle(
            r,
            sgl.Vertex{sgl.mul(a, m), color},
            sgl.Vertex{sgl.mul(b, m), color},
            sgl.Vertex{sgl.mul(c, m), color}
        );

        sgl.fill_triangle(
            r,
            sgl.Vertex{sgl.mul(c, m), color},
            sgl.Vertex{sgl.mul(d, m), color},
            sgl.Vertex{sgl.mul(a, m), color}
        );
    }

    {
        a := sgl.V4{-1, -1, 0, 1};
        b := sgl.V4{0, 1, 0, 1};
        c := sgl.V4{1, -1, 0, 1};

        translation := sgl.make_translation(sgl.V3{0, 0, 3});
        rotation := sgl.make_rotation(sgl.V3{1, 1, 1}, t);
        
        m := sgl.mul(projection, sgl.mul(translation, rotation));

        sgl.fill_triangle(
            r,
            sgl.Vertex{sgl.mul(a, m), sgl.Color{1, 0, 0, 1}},
            sgl.Vertex{sgl.mul(b, m), sgl.Color{0, 1, 0, 1}},
            sgl.Vertex{sgl.mul(c, m), sgl.Color{0, 0, 1, 1}}
        );
    }
}