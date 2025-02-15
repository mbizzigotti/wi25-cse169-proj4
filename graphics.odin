package proj4
import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:slice"
import m "core:math"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import math "core:math/linalg"

Vertex_Buffer :: struct { vao, id : u32 }
Index_Buffer  :: struct { id : u32 }
Shader        :: struct { id : u32 }

load_vertex_buffer :: proc(vertices: [] $V) -> Vertex_Buffer {
    using buffer : Vertex_Buffer
    gl.GenVertexArrays(1, &vao)
    gl.GenBuffers(1, &id)
    gl.BindVertexArray(vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, id)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(V), raw_data(vertices), gl.STATIC_DRAW)

    types   := reflect.struct_field_types(V)
    offsets := reflect.struct_field_offsets(V)
    stride  := cast(i32) size_of(V)

    //fmt.println("BEGIN VERTEX_BUFFER");
    for i in 0..<len(types) {
        type, offset := types[i], offsets[i]
        info    := type.variant.(runtime.Type_Info_Array)
        index   := cast(u32) i
        size    := cast(i32) info.count
        gl_type : u32 = gl.FLOAT;
        normalize := gl.FALSE;
        
        if info.elem.id == u8 { gl_type = gl.UNSIGNED_BYTE; normalize = gl.TRUE; }

        //fmt.printf("%s <- %T (%i)\n", reflect.struct_field_names(V)[i], type, stride);
        
        gl.VertexAttribPointer(index, size, gl_type, normalize, stride, offset)
        gl.EnableVertexAttribArray(index)
    }
    //fmt.println("END   VERTEX_BUFFER");
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)

    return buffer
}

upload_vertex_buffer :: proc(using vb: Vertex_Buffer, vertices: [] $V) {
    gl.BindBuffer(gl.ARRAY_BUFFER, id)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(V), raw_data(vertices), gl.DYNAMIC_DRAW)
}

upload :: proc {
    upload_vertex_buffer,
}

load_index_buffer :: proc(indices: [] $I) -> Index_Buffer {
    using buffer : Index_Buffer
    gl.GenBuffers(1, &id)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, id)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(I), raw_data(indices), gl.STATIC_DRAW)
    return buffer
}

load_quads_index_buffer :: proc(count: int) -> Index_Buffer {
    using buffer : Index_Buffer
    gl.GenBuffers(1, &id)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, id)

    temp_indices := make([] u32, count * 6, context.temp_allocator);
    i := 0;
    for k in 0..<count {
        temp_indices[i] = cast(u32) (k*4 + 0); i += 1;
        temp_indices[i] = cast(u32) (k*4 + 1); i += 1;
        temp_indices[i] = cast(u32) (k*4 + 2); i += 1;
        temp_indices[i] = cast(u32) (k*4 + 2); i += 1;
        temp_indices[i] = cast(u32) (k*4 + 0); i += 1;
        temp_indices[i] = cast(u32) (k*4 + 3); i += 1;
    }

    //for j in 0..<10 {
    //    t := &temp_indices
    //    fmt.println(t[j*6+0], t[j*6+1], t[j*6+2], t[j*6+3], t[j*6+4], t[j*6+5])
    //}

    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, i * size_of(u32), raw_data(temp_indices), gl.STATIC_DRAW)
    return buffer
}

load_shader :: proc(vert_source, frag_source: string) -> Shader {
    program, ok := gl.load_shaders_file(vert_source, frag_source)
    if !ok { return {} }
    return { id = program }
}

bind_vertex_buffer :: proc(vb: Vertex_Buffer) { gl.BindVertexArray(vb.vao) }
bind_index_buffer  :: proc(ib: Index_Buffer)  { gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib.id) }
bind_shader        :: proc(sh: Shader)        { gl.UseProgram(sh.id) }

bind :: proc {
    bind_vertex_buffer, 
    bind_index_buffer, 
    bind_shader, 
}

Mesh :: struct {
    vertex_buffer: Vertex_Buffer,
    index_buffer:  Index_Buffer,
    index_count:   i32,
}

create_mesh :: proc(vertices: [] $V, indices: [] u32) -> Mesh {
    return {
        vertex_buffer = load_vertex_buffer(vertices),
        index_buffer = load_index_buffer(indices),
        index_count = cast(i32) len(indices),
    }
}

create_sphere :: proc($vt: typeid, color: [3] f32 = {1,0,0}) -> Mesh {
    Y, X :: 18, 30

    vertices := make([] vt, X * Y + 2, context.temp_allocator)
    indices  := make([] u32, (X * (Y-1) + X-1)*6, context.temp_allocator)
    defer free_all(context.temp_allocator)

    vertices[0] = {position = {0,1,0}, color = color}
    for y in 0..<Y {
        b : f32 = (m.PI * cast(f32) (y + 1) / (Y + 1))
        rotZ: matrix [3,3] f32 = {
             m.cos(b), m.sin(b), 0,
            -m.sin(b), m.cos(b), 0,
             0,        0,        1,
        }
        for x in 0..<X {
            a : f32 = m.TAU * cast(f32) x / (X - 1)
            rotY: matrix [3,3] f32 = {
                m.cos(a), 0,-m.sin(a),
                0,        1, 0,
                m.sin(a), 0, m.cos(a),
            }
            p := [3] f32 { 0, 1, 0 }
            p = rotY * rotZ * p
            vertices[y * X + x + 1] = {position = p, color = color}
        }
    }
    vertices[X * Y + 1] = {position = {0,-1,0}, color = color}
    
    if slice.contains(reflect.struct_field_names(vt), "normal") {
        for &v in vertices {
            v.normal = v.position // wow!!!!!!!
        }
    }

    i := 0
    for x in 1..<X {
        indices[i] = cast(u32) (0);     i += 1
        indices[i] = cast(u32) (x + 1); i += 1
        indices[i] = cast(u32) (x);     i += 1
    }
    for y in 0..<Y-1 {
        for x in 0..<X {
            b := y * X + x + 1

            indices[i] = cast(u32) (b);         i += 1
            indices[i] = cast(u32) (b + 1);     i += 1
            indices[i] = cast(u32) (b + X);     i += 1
            indices[i] = cast(u32) (b + 1);     i += 1
            indices[i] = cast(u32) (b + X + 1); i += 1
            indices[i] = cast(u32) (b + X);     i += 1
        }
    }
    for x in 1..<X {
        b := X * Y + 1
        indices[i] = cast(u32) (b);     i += 1
        indices[i] = cast(u32) (b-x-1); i += 1
        indices[i] = cast(u32) (b-x);   i += 1
    }

    return {
        vertex_buffer = load_vertex_buffer(vertices),
        index_buffer = load_index_buffer(indices),
        index_count = cast(i32) len(indices),
    }
}

draw :: proc(using mesh: Mesh) {
    bind(vertex_buffer)
    bind(index_buffer)
    gl.DrawElements(gl.TRIANGLES, index_count, gl.UNSIGNED_INT, nil)
}

Camera :: struct {
    fov,      // Field of View Angle (degrees)
    aspect,   // Aspect Ratio
    near,     // Near clipping plane distance
    far,      // Far clipping plane distance
    distance, // Distance of the camera eye position to the origin (meters)
    azimuth,  // Rotation of the camera eye position around the Y axis (degrees)
    incline:  // Angle of the camera eye position over the XZ plane (degrees)
    f32
}

default_camera :: proc() -> Camera {
    return {
        fov      = 45.0,
        aspect   = 1.33,
        near     = 0.1,
        far      = 100.0,
        distance = 10.0,
        azimuth  = 60.0,
        incline  = 10.0,
    }
}

view_projection :: proc(using camera: Camera) -> (glm.mat4, glm.mat4) {
    world : glm.mat4
    world = glm.identity(glm.mat4)
    world[3][2] = distance
    world = math.matrix4_from_euler_angle_y(glm.radians(azimuth)) \
          * math.matrix4_from_euler_angle_x(glm.radians(incline)) \
          * world;
    view := world
    project := math.matrix4_perspective(glm.radians(fov), aspect, near, far);
    return view, project;
}
