package proj4
import "base:runtime"
import "core:fmt"
import "core:reflect"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import math "core:math/linalg"

Vertex_Buffer :: struct { id : u32 }
Index_Buffer  :: struct { id : u32 }
Vertex_Array  :: struct { id : u32 }
Shader        :: struct { id : u32 }

Bindable :: union {
    Vertex_Buffer,
    Index_Buffer,
    Vertex_Array,
    Shader,
}

load_vertex_buffer :: proc(vertices: [] $V) -> Vertex_Buffer {
    using buffer : Vertex_Buffer
    gl.GenBuffers(1, &id)
    gl.BindBuffer(gl.ARRAY_BUFFER, id)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(V), raw_data(vertices), gl.STATIC_DRAW)
    return buffer
}

load_index_buffer :: proc(indices: [] $I) -> Index_Buffer {
    using buffer : Index_Buffer
    gl.GenBuffers(1, &id)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, id)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(I), raw_data(indices), gl.STATIC_DRAW)
    return buffer
}

create_vertex_array :: proc(vertex_type: typeid) -> Vertex_Array {
    using vertex_array : Vertex_Array
    gl.GenVertexArrays(1, &id)
    gl.BindVertexArray(id)

    types   := reflect.struct_field_types(vertex_type)
    offsets := reflect.struct_field_offsets(vertex_type)
    stride  := cast(i32) reflect.size_of_typeid(vertex_type)

    for i in 0..<len(types) {
        type, offset := types[i], offsets[i]
        info  := type.variant.(runtime.Type_Info_Array)
        index := cast(u32) i
        size  := cast(i32) info.count

        // if info.elem.id == i32 { } // type is hard-coded to be FLOAT always for not
        gl.EnableVertexAttribArray(index)
        check_gl_errors();
        gl.VertexAttribPointer(index, size, gl.FLOAT, gl.FALSE, stride, offset)
        Input :: struct {
            index:      u32,
            size:       i32,
            type:       u32,
            normalized: bool, 
	        stride:     i32, 
	        pointer:    uintptr, 
        }
        check_gl_errors();
    }

    return vertex_array
}

load_shader :: proc(vert_source, frag_source: string) -> Shader {
    program, ok := gl.load_shaders_file(vert_source, frag_source)
    if !ok { return {} }
    return { id = program }
}

bind :: proc(obj: Bindable) {
    switch b in obj {
    case Vertex_Buffer: gl.BindBuffer(gl.ARRAY_BUFFER, b.id)
    case Index_Buffer:  gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, b.id)
    case Vertex_Array:  gl.BindVertexArray(b.id)
    case Shader:        gl.UseProgram(b.id)
    }
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
        azimuth  = 0.0,
        incline  = 20.0,
    }
}

view_projection :: proc(using camera: Camera) -> glm.mat4 {
    world : glm.mat4
    world = glm.identity(glm.mat4)

    world[3][2] = distance
    world = math.matrix4_from_euler_angle_y(glm.radians(azimuth)) \
          * math.matrix4_from_euler_angle_x(glm.radians(incline)) \
          * world;
    view := glm.inverse(world)
    project := math.matrix4_perspective(glm.radians(fov), aspect, near, far);
    return project * view;
}

check_gl_errors :: proc(loc := #caller_location) {
    code := gl.GetError()
    for code != gl.NO_ERROR {
        what : string
        switch code {
            case gl.INVALID_ENUM:                  what = "INVALID_ENUM"
            case gl.INVALID_VALUE:                 what = "INVALID_VALUE"
            case gl.INVALID_OPERATION:             what = "INVALID_OPERATION"
            case gl.STACK_OVERFLOW:                what = "STACK_OVERFLOW"
            case gl.STACK_UNDERFLOW:               what = "STACK_UNDERFLOW"
            case gl.OUT_OF_MEMORY:                 what = "OUT_OF_MEMORY"
            case gl.INVALID_FRAMEBUFFER_OPERATION: what = "INVALID_FRAMEBUFFER_OPERATION"
        }
        fmt.eprintf("%w | %s (%i)", loc, what, code)
        code := gl.GetError()
        runtime.debug_trap()
    }
}

