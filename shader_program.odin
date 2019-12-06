package sgl

import "core:os"
import "core:strings"
import "core:fmt"
import "core:runtime"
import "core:reflect"

using import "shared:odin-libjit"

foreign import libc "system:c"
        
foreign libc {
    stdout: rawptr;
}

/*

generate struct that contains shader edge and gradient data,
extracted from `VO`

actually, just generate an edge struct that can be used alongside the
`Edge` structs we have in `fill_triangle`

also generate code to initialize all of this data (calculate the
gradients themselves, basically)

and generate code to step these edges

then use these edges alongside the normal ones in the renderer
to interpolate user shader data

then call shader functions with this data

...

theoretically this means we need to generate our own Gradients structure as well?
and use it the same way we use the regular one
or can we just do that dynamically during compilation? that may be better....

*/

Shader_Program :: struct {
    rc: ^Render_Context,
    
    v2_type: Type,
    v3_type: Type,
    v4_type: Type,
    color_type: Type,
    base_vertex_type: Type,

    vertex_type: Type,

    edge_type: Type,
    gradients_type: Type,
    gradients_type_ptr: Type,
    
    init_edge_proc_signature: Type,
    init_edge_proc: Function,
    init_gradients_proc_signature: Type,
    init_gradients_proc: Function,

    vertex_shader_signature: Type,
    vertex_shader: Function,
    fragment_shader_signature: Type,
    fragment_shader: Function
}

make_shader_program :: proc(_rc: ^Render_Context, _vertex_shader: proc($VI) -> $VO, _fragment_shader: proc(VO) -> Color) -> ^Shader_Program {
    using p := new(Shader_Program);

    rc = _rc;

    vi_info := type_info_of(VI);
    assert(reflect.is_struct(vi_info));

    types := reflect.struct_field_types(VI);
    assert(types[0] == type_info_of(Vertex));
    field_types := types[1:];

    init_base_types :: inline proc(using p: ^Shader_Program) {
        /*
            v2:                 (f64,f64)
            v3:                 (f64,f64,f64)
            v4:                 (f64,f64,f64,f64)
            color:              (f64, f64, f64, f64)
            base_vertex_type:   (v4)
        */

        v2_fields := [2]Type{jit_type_float64, jit_type_float64};
        v2_type = type_create_struct(&v2_fields[0], 2, 1);
        v3_fields := [3]Type{jit_type_float64, jit_type_float64, jit_type_float64};
        v3_type = type_create_struct(&v3_fields[0], 3, 1);
        v4_fields := [4]Type{jit_type_float64, jit_type_float64, jit_type_float64, jit_type_float64};
        v4_type = type_create_struct(&v4_fields[0], 4, 1);
        color_fields := [4]Type{jit_type_float64, jit_type_float64, jit_type_float64, jit_type_float64};
        color_type = type_create_struct(&color_fields[0], 4, 1);
        base_vertex_fields := [1]Type{v4_type};
        base_vertex_type = type_create_struct(&base_vertex_fields[0], 1, 1);
    }

    init_vertex_type :: inline proc(using p: ^Shader_Program, types: []^runtime.Type_Info) {
        fields := make([]Type, len(types) + 1, context.temp_allocator);

        fields[0] = type_copy(base_vertex_type);

        for i in 0..<len(types) {
            fields[i+1] = copy_base_type(p, types[i]);
        }

        vertex_type = type_create_struct(&fields[0], u32(len(fields)), 1);
    }

    copy_base_type :: inline proc(using p: ^Shader_Program, type: ^runtime.Type_Info) -> Type {
        switch type {
            case type_info_of(V2):      return type_copy(v2_type);
            case type_info_of(V3):      return type_copy(v3_type);
            case type_info_of(V4):      return type_copy(v4_type);
            case type_info_of(Color):   return type_copy(color_type);
            case type_info_of(f64):     return type_copy(jit_type_float64);
            case:                       assert(false);
        }
        unreachable();
        return nil;
    }

    init_edge_type :: inline proc(using p: ^Shader_Program, types: []^runtime.Type_Info) {
        /*
            Edge {
                (value,step)*
            }
        */
        
        fields := make([]Type, len(types)*2, context.temp_allocator);

        for i in 0..<len(types) {
            j := i * 2;
            inline for k in 0..1 do fields[j + k] = copy_base_type(p, types[i]);
        }

        edge_type = type_create_struct(&fields[0], u32(len(fields)), 1);
    }

    init_gradients_type :: inline proc(using p: ^Shader_Program, types: []^runtime.Type_Info) {
        /*
            Gradients {
                (min, mid, max, x_step, y_step)*
            }
        */
        fields := make([]Type, len(types)*5, context.temp_allocator);

        for i in 0..<len(types) {
            j := i * 2;
            inline for k in 0..4 do fields[j + k] = copy_base_type(p, types[i]);
        }

        gradients_type = type_create_struct(&fields[0], u32(len(fields)), 1);
        gradients_type_ptr = type_create_pointer(gradients_type, 1);
    }

    init_init_edge_proc :: inline proc(using p: ^Shader_Program, types: []^runtime.Type_Info) {

    }

    init_init_gradients_proc :: inline proc(using p: ^Shader_Program, types: []^runtime.Type_Info) {
        params := [4]Type{gradients_type_ptr, vertex_type, vertex_type, vertex_type};
        init_gradients_proc_signature = type_create_signature(.Cdecl, gradients_type, &params[0], len(params), 1);

        j := rc.jit_ctx;
        f := function_create(j, init_gradients_proc_signature);

        gradients := value_get_param(f, 0);

        min := value_get_param(f, 1);
        min_a := insn_address_of(f, min);
        mid := value_get_param(f, 2);
        mid_a := insn_address_of(f, mid);
        max := value_get_param(f, 3);
        max_a := insn_address_of(f, max);

        min_x := insn_load_relative(f, min_a, i64(offset_of(Vertex, pos)), jit_type_float64);
        mid_x := insn_load_relative(f, mid_a, i64(offset_of(Vertex, pos)), jit_type_float64);
        max_x := insn_load_relative(f, max_a, i64(offset_of(Vertex, pos)), jit_type_float64);
        min_y := insn_load_relative(f, min_a, i64(offset_of(Vertex, pos) + size_of(f64)), jit_type_float64);
        mid_y := insn_load_relative(f, mid_a, i64(offset_of(Vertex, pos) + size_of(f64)), jit_type_float64);
        max_y := insn_load_relative(f, max_a, i64(offset_of(Vertex, pos) + size_of(f64)), jit_type_float64);

        one := value_create_float64_constant(f, jit_type_float64, 1);
        one_over_dx := insn_div(f, 
            one,
            insn_sub(f,
                insn_mul(f, 
                    insn_sub(f, mid_x, max_x),
                    insn_sub(f, min_y, max_y)
                ),
                insn_mul(f,
                    insn_sub(f, min_x, max_x),
                    insn_sub(f, mid_y, max_y)
                )
            )
        );
        one_over_dy := insn_neg(f, one_over_dx);

        offset := i64(0);
        gradient_offset := i64(0);
        for i in 0..<len(types) {
            c_type := copy_base_type(p, types[i]);
            c_type_size := i64(type_get_size(c_type));
            
            min_value := insn_load_relative(f, min_a, offset, c_type);
            mid_value := insn_load_relative(f, mid_a, offset, c_type);
            max_value := insn_load_relative(f, max_a, offset, c_type);
            
            insn_store_relative(f, gradients, gradient_offset, min_value);
            insn_store_relative(f, gradients, gradient_offset + c_type_size, mid_value);
            insn_store_relative(f, gradients, gradient_offset + c_type_size * 2, max_value);

            calc_x_step :: inline proc(f: Function, values: [3]Value, vertices: [3]Value, one_over_dx: Value) -> Value {
                min := vertices[0];
                mid := vertices[1];
                max := vertices[2];

                min_y := insn_load_relative(f, min, i64(offset_of(Vertex, pos) + size_of(f64)), jit_type_float64);
                mid_y := insn_load_relative(f, mid, i64(offset_of(Vertex, pos) + size_of(f64)), jit_type_float64);
                max_y := insn_load_relative(f, max, i64(offset_of(Vertex, pos) + size_of(f64)), jit_type_float64);

                return insn_mul(f,
                    insn_sub(f,
                        insn_mul(f,
                            insn_sub(f, values[1], values[2]),
                            insn_sub(f, min_y, max_y)
                        ),
                        insn_mul(f,
                            insn_sub(f, values[0], values[2]),
                            insn_sub(f, mid_y, max_y)
                        )
                    ),
                    one_over_dx
                );
            }

            calc_y_step :: inline proc(f: Function, values: [3]Value, vertices: [3]Value, one_over_dy: Value) -> Value {
                min := vertices[0];
                mid := vertices[1];
                max := vertices[2];

                min_x := insn_load_relative(f, min, i64(offset_of(Vertex, pos)), jit_type_float64);
                mid_x := insn_load_relative(f, mid, i64(offset_of(Vertex, pos)), jit_type_float64);
                max_x := insn_load_relative(f, max, i64(offset_of(Vertex, pos)), jit_type_float64);

                return insn_mul(f,
                    insn_sub(f,
                        insn_mul(f,
                            insn_sub(f, values[1], values[2]),
                            insn_sub(f, min_x, max_x)
                        ),
                        insn_mul(f,
                            insn_sub(f, values[0], values[2]),
                            insn_sub(f, mid_x, max_x)
                        )
                    ),
                    one_over_dy
                );
            } 

            switch types[i] {
                case type_info_of(V2):
                    ax := insn_load_relative(f, min_value, 0, jit_type_float64);
                    ay := insn_load_relative(f, min_value, size_of(f64), jit_type_float64);
                    bx := insn_load_relative(f, mid_value, 0, jit_type_float64);
                    by := insn_load_relative(f, mid_value, size_of(f64), jit_type_float64);
                    cx := insn_load_relative(f, max_value, 0, jit_type_float64);
                    cy := insn_load_relative(f, max_value, size_of(f64), jit_type_float64);

                    x_step := calc_x_step(f, [3]Value{ax, bx, cx}, [3]Value{min_a, mid_a, max_a}, one_over_dx);
                    y_step := calc_y_step(f, [3]Value{ay, by, cy}, [3]Value{min_a, mid_a, max_a}, one_over_dy);

                case type_info_of(V3):
                    ax := insn_load_relative(f, min_value, 0, jit_type_float64);
                    ay := insn_load_relative(f, min_value, size_of(f64), jit_type_float64);
                    az := insn_load_relative(f, min_value, size_of(f64) * 2, jit_type_float64);

                case type_info_of(V4):
                    ax := insn_load_relative(f, min_value, 0, jit_type_float64);
                    ay := insn_load_relative(f, min_value, size_of(f64), jit_type_float64);
                    az := insn_load_relative(f, min_value, size_of(f64) * 2, jit_type_float64);
                    aw := insn_load_relative(f, min_value, size_of(f64) * 3, jit_type_float64);

                case type_info_of(Color):
                    ar := insn_load_relative(f, min_value, 0, jit_type_float64);
                    ag := insn_load_relative(f, min_value, size_of(f64), jit_type_float64);
                    ab := insn_load_relative(f, min_value, size_of(f64) * 2, jit_type_float64);
                    aa := insn_load_relative(f, min_value, size_of(f64) * 3, jit_type_float64);

                    br := insn_load_relative(f, mid_value, 0, jit_type_float64);
                    bg := insn_load_relative(f, mid_value, size_of(f64), jit_type_float64);
                    bb := insn_load_relative(f, mid_value, size_of(f64) * 2, jit_type_float64);
                    ba := insn_load_relative(f, mid_value, size_of(f64) * 3, jit_type_float64);

                    cr := insn_load_relative(f, max_value, 0, jit_type_float64);
                    cg := insn_load_relative(f, max_value, size_of(f64), jit_type_float64);
                    cb := insn_load_relative(f, max_value, size_of(f64) * 2, jit_type_float64);
                    ca := insn_load_relative(f, max_value, size_of(f64) * 3, jit_type_float64);

                    x_step_r := calc_x_step(f, [3]Value{ar, br, cr}, [3]Value{min_a, mid_a, max_a}, one_over_dx);
                    x_step_g := calc_x_step(f, [3]Value{ag, bg, cg}, [3]Value{min_a, mid_a, max_a}, one_over_dx);
                    x_step_b := calc_x_step(f, [3]Value{ab, bb, cb}, [3]Value{min_a, mid_a, max_a}, one_over_dx);
                    x_step_a := calc_x_step(f, [3]Value{aa, ba, ca}, [3]Value{min_a, mid_a, max_a}, one_over_dx);
                    y_step_r := calc_y_step(f, [3]Value{ar, br, cr}, [3]Value{min_a, mid_a, max_a}, one_over_dy);
                    y_step_g := calc_y_step(f, [3]Value{ag, bg, cg}, [3]Value{min_a, mid_a, max_a}, one_over_dy);
                    y_step_b := calc_y_step(f, [3]Value{ab, bb, cb}, [3]Value{min_a, mid_a, max_a}, one_over_dy);
                    y_step_a := calc_y_step(f, [3]Value{aa, ba, ca}, [3]Value{min_a, mid_a, max_a}, one_over_dy);

                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 3, x_step_r);
                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 3 + size_of(f64), x_step_g);
                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 3 + size_of(f64) * 2, x_step_b);
                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 3 + size_of(f64) * 3, x_step_a);
                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 4, y_step_r);
                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 4 + size_of(f64), y_step_g);
                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 4 + size_of(f64) * 2, y_step_b);
                    insn_store_relative(f, gradients, gradient_offset + size_of(f64) * 4 * 4 + size_of(f64) * 3, y_step_a);
                case type_info_of(f64):

                case:
                    assert(false);
            }

            gradient_offset += c_type_size * 5;
        }

        insn_return(f, nil);

        init_gradients_proc = f;
        dump_function(stdout, init_gradients_proc, strings.unsafe_string_to_cstring("init_gradients_proc"));
        function_compile(init_gradients_proc);
    }

    j := rc.jit_ctx;
    context_build_start(j);

    init_base_types(p);    
    init_vertex_type(p, field_types);
    init_edge_type(p, field_types);
    init_gradients_type(p, field_types);
    init_init_edge_proc(p, field_types);
    init_init_gradients_proc(p, field_types);

    context_build_end(j);

    return p;
}

delete_shader_program :: proc(using p: ^Shader_Program) {
    type_free(v2_type);
    type_free(v3_type);
    type_free(v4_type);
    type_free(color_type);
}