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

Init_Gradients_Proc     :: #type proc(rawptr, rawptr, rawptr, rawptr);
Init_Edge_Proc          :: #type proc(rawptr, rawptr, V2, V2, i32);
Step_Proc               :: #type proc(rawptr);

Shader_Program :: struct {
    rc: ^Render_Context,
    
    v2_type: Type,
    v3_type: Type,
    v4_type: Type,
    color_type: Type,
    base_vertex_type: Type,

    vertex_type: Type,
    vertex_type_ptr: Type,

    edge_type: Type,
    edge_type_ptr: Type,
    gradients_type: Type,
    gradients_type_ptr: Type,
    
    init_edge_proc_signature: Type,
    init_edge_proc: Function,
    init_gradients_proc_signature: Type,
    init_gradients_proc: Function,
    step_proc_signature: Type,
    step_proc: Function,

    vertex_shader_signature: Type,
    vertex_shader: Function,
    fragment_shader_signature: Type,
    fragment_shader: Function,

    init_edge_proc_closure: Init_Edge_Proc,
    init_gradients_proc_closure: Init_Gradients_Proc,
    step_proc_closure: Step_Proc,

    storage: []u8,
    _gradients: rawptr,
    _min_to_max: rawptr,
    _min_to_mid: rawptr,
    _mid_to_max: rawptr,
    _left: rawptr,
    _right: rawptr
}

make_shader_program :: proc(_rc: ^Render_Context, _vertex_shader: proc "c" ($VI) -> $VO, _fragment_shader: proc "c" (VO) -> Color) -> ^Shader_Program {
    using p := new(Shader_Program);

    rc = _rc;

    vi_info := type_info_of(VI);
    assert(reflect.is_struct(vi_info));

    types := reflect.struct_field_types(VI);
    assert(types[0] == type_info_of(Vertex));
    field_types := types[1:];

    init_base_types :: inline proc(using p: ^Shader_Program) {
        /*
            v2:                 (f64, f64)
            v3:                 (f64, f64, f64)
            v4:                 (f64, f64, f64,f64)
            color:              (f64, f64, f64, f64)
            base_vertex_type:   (v4)
            vertex_type:        (base_vertex_type, VI\*)
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
        vertex_type_ptr = type_create_pointer(vertex_type, 1);
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
        edge_type_ptr = type_create_pointer(edge_type, 1);
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
        params := [5]Type{edge_type_ptr, gradients_type_ptr, v2_type, v2_type, jit_type_int};
        init_edge_proc_signature = type_create_signature(.Cdecl, jit_type_void, &params[0], len(params), 1);
    
        j := rc.jit_ctx;
        f := function_create(j, init_edge_proc_signature);

        edge := value_get_param(f, 0);
        gradients := value_get_param(f, 1);
        start := value_get_param(f, 2);
        end := value_get_param(f, 3);
        start_index := value_get_param(f, 4);

        start_a := insn_address_of(f, start);
        end_a := insn_address_of(f, end);

        start_x := insn_load_relative(f, start_a, 0, jit_type_float64);
        start_y := insn_load_relative(f, start_a, size_of(f64), jit_type_float64);
        end_x := insn_load_relative(f, end_a, 0, jit_type_float64);
        end_y := insn_load_relative(f, end_a, size_of(f64), jit_type_float64);

        y_start := insn_convert(f, insn_ceil(f, start_y), jit_type_int, 0);
        y_end := insn_convert(f, insn_ceil(f, end_y), jit_type_int, 0);

        x_dist := insn_sub(f, end_x, start_x);
        y_dist := insn_sub(f, end_y, start_y);

        y_prestep := insn_sub(f, insn_convert(f, y_start, jit_type_float64, 0), start_y);
            
        x_step := insn_div(f, x_dist, y_dist);
        x := insn_add(f, start_x, insn_mul(f, y_prestep, x_step));

        x_prestep := insn_sub(f, x, start_x);

        offset := i64(0);
        gradient_offset := i64(0);
        for i in 0..<len(types) {
            c_type := copy_base_type(p, types[i]);
            c_type_size := i64(type_get_size(c_type));
            c_type_size_value := value_create_nint_constant(f, jit_type_int, c_type_size);

            base_addr := insn_add(f, gradients, value_create_nint_constant(f, jit_type_int, gradient_offset));

            switch types[i] {
                case type_info_of(V2):
                    unimplemented();
                case type_info_of(V3):
                    unimplemented();
                case type_info_of(V4):
                    unimplemented();
                case type_info_of(Color):
                    start := insn_load_elem_address(f, base_addr, start_index, color_type);
                    x_step := insn_load_elem_address(f, base_addr, value_create_nint_constant(f, jit_type_int, 3), color_type);
                    y_step := insn_load_elem_address(f, base_addr, value_create_nint_constant(f, jit_type_int, 4), color_type);

                    start_r := insn_load_relative(f, start, 0, jit_type_float64);
                    start_g := insn_load_relative(f, start, size_of(f64), jit_type_float64);
                    start_b := insn_load_relative(f, start, size_of(f64) * 2, jit_type_float64);
                    start_a := insn_load_relative(f, start, size_of(f64) * 3, jit_type_float64);

                    x_step_r := insn_load_relative(f, x_step, 0, jit_type_float64);
                    x_step_g := insn_load_relative(f, x_step, size_of(f64), jit_type_float64);
                    x_step_b := insn_load_relative(f, x_step, size_of(f64) * 2, jit_type_float64);
                    x_step_a := insn_load_relative(f, x_step, size_of(f64) * 3, jit_type_float64);

                    y_step_r := insn_load_relative(f, y_step, 0, jit_type_float64);
                    y_step_g := insn_load_relative(f, y_step, size_of(f64), jit_type_float64);
                    y_step_b := insn_load_relative(f, y_step, size_of(f64) * 2, jit_type_float64);
                    y_step_a := insn_load_relative(f, y_step, size_of(f64) * 3, jit_type_float64);

                    value_r := insn_add(f, 
                        start_r, 
                        insn_add(f,
                            insn_mul(f, x_step_r, x_prestep),
                            insn_mul(f, y_step_r, y_prestep)
                        )
                    );
                    value_g := insn_add(f, 
                        start_g, 
                        insn_add(f,
                            insn_mul(f, x_step_g, x_prestep),
                            insn_mul(f, y_step_g, y_prestep)
                        )
                    );
                    value_b := insn_add(f, 
                        start_b, 
                        insn_add(f,
                            insn_mul(f, x_step_b, x_prestep),
                            insn_mul(f, y_step_b, y_prestep)
                        )
                    );
                    value_a := insn_add(f, 
                        start_a, 
                        insn_add(f,
                            insn_mul(f, x_step_a, x_prestep),
                            insn_mul(f, y_step_a, y_prestep)
                        )
                    );

                    insn_store_relative(f, edge, offset, value_r);
                    insn_store_relative(f, edge, offset + size_of(f64), value_g);
                    insn_store_relative(f, edge, offset + size_of(f64) * 2, value_b);
                    insn_store_relative(f, edge, offset + size_of(f64) * 3, value_a);

                    step_r := insn_add(f,
                        insn_mul(f, x_step_r, x_step),
                        y_step_r
                    );
                    step_g := insn_add(f,
                        insn_mul(f, x_step_g, x_step),
                        y_step_g
                    );
                    step_b := insn_add(f,
                        insn_mul(f, x_step_b, x_step),
                        y_step_b
                    );
                    step_a := insn_add(f,
                        insn_mul(f, x_step_a, x_step),
                        y_step_a
                    );

                    insn_store_relative(f, edge, offset + size_of(f64) * 4, value_r);
                    insn_store_relative(f, edge, offset + size_of(f64) * 4 + size_of(f64), value_g);
                    insn_store_relative(f, edge, offset + size_of(f64) * 4 + size_of(f64) * 2, value_b);
                    insn_store_relative(f, edge, offset + size_of(f64) * 4 + size_of(f64) * 3, value_a);
                case type_info_of(f64):
                    unimplemented();
                case:
                    assert(false);
            }

            offset += c_type_size * 2;
            gradient_offset += c_type_size * 5;
        }

        insn_return(f, nil);

        function_compile(f);
        init_edge_proc = f;
        init_edge_proc_closure = transmute(Init_Edge_Proc) function_to_closure(init_edge_proc);
    }

    init_init_gradients_proc :: inline proc(using p: ^Shader_Program, types: []^runtime.Type_Info) {
        params := [4]Type{gradients_type_ptr, vertex_type_ptr, vertex_type_ptr, vertex_type_ptr};
        init_gradients_proc_signature = type_create_signature(.Cdecl, jit_type_void, &params[0], len(params), 1);

        j := rc.jit_ctx;
        f := function_create(j, init_gradients_proc_signature);

        gradients := value_get_param(f, 0);
        min_a := value_get_param(f, 1);
        mid_a := value_get_param(f, 2);
        max_a := value_get_param(f, 3);

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
                    unimplemented();
                case type_info_of(V3):
                    unimplemented();
                case type_info_of(V4):
                    unimplemented();
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
                    unimplemented();
                case:
                    assert(false);
            }

            offset += c_type_size;
            gradient_offset += c_type_size * 5;
        }

        insn_return(f, nil);
        
        function_compile(f);
        init_gradients_proc = f;
        init_gradients_proc_closure = transmute(Init_Gradients_Proc) function_to_closure(init_gradients_proc);
    }

    init_step_proc :: inline proc(using p: ^Shader_Program, types: []^runtime.Type_Info) {
        params := [1]Type{edge_type_ptr};
        step_proc_signature = type_create_signature(.Cdecl, jit_type_void, &params[0], len(params), 1);
    
        j := rc.jit_ctx;
        f := function_create(j, init_gradients_proc_signature);

        edge := value_get_param(f, 0);

        offset := i64(0);
        for i in 0..<len(types) {
            c_type := copy_base_type(p, types[i]);
            c_type_size := i64(type_get_size(c_type));
            
            n_floats := c_type_size / size_of(f64);
            for i in 0..<n_floats {
                j := i * size_of(f64);
                a := insn_load_relative(f, edge, offset + j, jit_type_float64);
                b := insn_load_relative(f, edge, offset + c_type_size + j, jit_type_float64);
                c := insn_add(f, a, b);    
                insn_store_relative(f, edge, offset + j, c);
            }

            offset += c_type_size;
        } 

        insn_return(f, nil);

        function_compile(f);
        step_proc = f;
        step_proc_closure = transmute(Step_Proc) function_to_closure(step_proc);
    }

    j := rc.jit_ctx;

    context_build_start(j);
    defer context_build_end(j);

    init_base_types(p);    
    init_vertex_type(p, field_types);
    init_edge_type(p, field_types);
    init_gradients_type(p, field_types);
    init_init_edge_proc(p, field_types);
    init_init_gradients_proc(p, field_types);
    init_step_proc(p, field_types);

    storage = make([]u8, type_get_size(gradients_type) + 3 * type_get_size(edge_type));
    _gradients = &storage[0];
    _min_to_max = &storage[type_get_size(gradients_type)];
    _min_to_mid = &storage[type_get_size(gradients_type) + type_get_size(edge_type)];
    _mid_to_max = &storage[type_get_size(gradients_type) + type_get_size(edge_type) * 2];

    return p;
}

delete_shader_program :: proc(using p: ^Shader_Program) {
    type_free(v2_type);
    type_free(v3_type);
    type_free(v4_type);
    type_free(color_type);
    type_free(base_vertex_type);

    type_free(vertex_type);

    type_free(edge_type);
    type_free(edge_type_ptr);

    type_free(gradients_type);
    type_free(gradients_type_ptr);

    type_free(init_edge_proc_signature);
    type_free(init_gradients_proc_signature);

    type_free(vertex_shader_signature);
    type_free(fragment_shader_signature);

    delete(storage);
}

begin_shading :: proc(using p: ^Shader_Program, min, mid, max: $VI) {
    a, b, c := min, mid, max;
    
    init_gradients_proc_closure(_gradients, &a, &b, &c);
    init_edge_proc_closure(_min_to_max, _gradients, swizzle(min.pos, 0, 1), swizzle(max.pos, 0, 1), 0);
    init_edge_proc_closure(_min_to_mid, _gradients, swizzle(min.pos, 0, 1), swizzle(mid.pos, 0, 1), 0);
    init_edge_proc_closure(_mid_to_max, _gradients, swizzle(mid.pos, 0, 1), swizzle(max.pos, 0, 1), 1);
}

begin_shading_edges :: proc(using p: ^Shader_Program, mid_to_max: bool, handedness: bool) {
    left := _min_to_max;
    
    right: rawptr;
    if mid_to_max   do right = _mid_to_max;
    else            do right = _min_to_mid;

    if handedness do swap(&left, &right);

    _left = left;
    _right = right;
}

step_shading :: proc(using p: ^Shader_Program) {
    step_proc_closure(_left);
    step_proc_closure(_right);
}