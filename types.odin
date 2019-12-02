package sgl

import "core:math"
import "core:math/linalg"

Color :: struct {
    r, g, b, a: f64
}

Pixel :: struct {
    r, g, b, a: u8
}

color_to_pixel :: inline proc(color: Color) -> Pixel {
    return Pixel{u8(color.r * 255 + 0.5), u8(color.g * 255 + 0.5), u8(color.b * 255 + 0.5), u8(color.a * 255 + 0.5)};
}

mul_color :: proc(c: Color, s: f64) -> Color {
    return Color{c.r * s, c.g * s, c.b * s, c.a * s};
}

add_color :: proc(a, b: Color) -> Color {
    return Color{a.r + b.r, a.g + b.g, a.b + b.b, a.a + b.a};
}

sub_color :: proc(a, b: Color) -> Color {
    return Color{a.r - b.r, a.g - b.g, a.b - b.b, a.a - b.a};
}

V2 :: distinct [2]f64;
V3 :: distinct [3]f64;
V4 :: distinct [4]f64;

M4 :: distinct [4][4]f64;

Vertex :: struct {
    pos: V4,
    color: Color
}

make_identity :: inline proc() -> M4 {
    return M4{
        {1, 0, 0, 0},
        {0, 1, 0, 0},
        {0, 0, 1, 0},
        {0, 0, 0, 1},
    };
}

make_screen_space_transform :: inline proc(width, height: f64) -> M4 {
    i := width / 2;
    j := height / 2;
    k := -j;
    return M4{
        {i, 0, 0, i - 0.5},
        {0, k, 0, j - 0.5},
        {0, 0, 1, 0},
        {0, 0, 0, 1},
    };
}

make_translation :: inline proc(v: V3) -> M4 {
    m := make_identity();
    m[3][0] = v[0];
    m[3][1] = v[1];
    m[3][2] = v[2];
    return m;
}

make_rotation :: inline proc(v: V3, a: f64) -> M4 {
    c := math.cos(a);
    s := math.sin(a);

    a := linalg.normalize(v);
    t := a * (1 - c);

    rot := make_identity();

    rot[0][0] = c + t[0] * a[0];
    rot[0][1] = 0 + t[0] * a[1] + s * a[2];
    rot[0][2] = 0 + t[0] * a[2] - s * a[1];
    rot[0][3] = 0;

    rot[1][0] = 0 + t[1] * a[0] - s * a[2];
    rot[1][1] = c + t[1] * a[1];
    rot[1][2] = 0 + t[1] * a[2] + s * a[0];
    rot[1][3] = 0;

    rot[2][0] = 0 + t[2] * a[0] + s * a[1];
    rot[2][1] = 0 + t[2] * a[1] - s * a[0];
    rot[2][2] = c + t[2] * a[2];
    rot[2][3] = 0;

    return rot;
}

make_perspective :: inline proc(fovy, aspect, near, far: f64) -> M4 {
    tan_half_fovy := math.tan(0.5 * math.to_radians(fovy));
    z_range := far - near;
    return M4{
        {1 / (aspect * tan_half_fovy), 0, 0, 0},
        {0, 1 / tan_half_fovy, 0, 0},
        {0, 0, -(far + near) / z_range, -1},
        {0, 0, -2 * far * near / z_range, 0}
    };
}

mul_matrix :: inline proc(a, b: M4) -> M4 {
    c: M4;
    for i in 0..<4 {
        for k in 0..<4 {
            for j in 0..<4 {
                c[k][i] += a[j][i] * b[k][j];
            }
        }
    }
    return c;
}

mul_matrix_vector :: inline proc(v: V4, m: M4) -> V4 {
    return V4{
        m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z + m[0][3] * v.w,
        m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z + m[1][3] * v.w,
        m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z + m[2][3] * v.w,
        m[3][0] * v.x + m[3][1] * v.y + m[3][2] * v.z + m[3][3] * v.w,
    };
}

mul :: proc{mul_matrix, mul_matrix_vector};

perspective_divide :: inline proc(v: V4) -> V4 {
    return V4{
        v.x / v.w,
        v.y / v.w,
        v.z / v.w,
        v.w
    };
}