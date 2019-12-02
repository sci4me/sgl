package main

import "core:math"

import "shared:sgl"

angle := 0.0;
projection: sgl.M4;

init :: proc() {
    projection = sgl.make_perspective(70, f64(WIDTH)/f64(HEIGHT), 0.1, 1000);
}

tick :: proc() {
    angle += 0.01;
}

render :: proc(r: ^sgl.Renderer) {
    sgl.clear(r, sgl.Color{0, 0, 0, 0xFF});

    {
        a := sgl.V4{-1, -1, 0, 1};
        b := sgl.V4{-1, 1, 0, 1};
        c := sgl.V4{1, 1, 0, 1};
        d := sgl.V4{1, -1, 0, 1};        

        translation := sgl.make_translation(sgl.V3{0, 0, 3});
        
        m := sgl.mul(projection, translation);

        sgl.fill_triangle(
            r,
            sgl.mul(a, m),
            sgl.mul(b, m),
            sgl.mul(c, m),
            sgl.Color{0x00, 0xFF, 0x00, 0xFF}
        );

        sgl.fill_triangle(
            r,
            sgl.mul(c, m),
            sgl.mul(d, m),
            sgl.mul(a, m),
            sgl.Color{0x00, 0xFF, 0x00, 0xFF}
        );
    }

    {
        a := sgl.V4{-1, -1, 0, 1};
        b := sgl.V4{0, 1, 0, 1};
        c := sgl.V4{1, -1, 0, 1};

        translation := sgl.make_translation(sgl.V3{0, 0, 3});
        rotation := sgl.make_rotation(sgl.V3{0, 1, 0}, angle);
        
        m := sgl.mul(projection, sgl.mul(translation, rotation));

        sgl.fill_triangle(
            r,
            sgl.mul(a, m),
            sgl.mul(b, m),
            sgl.mul(c, m),
            sgl.Color{0xFF, 0x00, 0x00, 0xFF}
        );
    }
}