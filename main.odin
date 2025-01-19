package proj4
import "base:runtime"
import "core:fmt"
import time "core:time"
import glfw "vendor:GLFW"
import gl   "vendor:OpenGL"
import glm  "core:math/linalg/glsl"
import math "core:math/linalg"

WIDTH  :: 800
HEIGHT :: 600
TITLE  :: "CSE 169 Cloth Simulation"

window    : glfw.WindowHandle
last_tick : time.Tick

main :: proc() {
    if !bool(glfw.Init()) {
        fmt.eprintln("GLFW Init failed");
        return
    }
    defer glfw.Terminate()

    glfw.SetErrorCallback(error_callback)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)

	window = glfw.CreateWindow(WIDTH, HEIGHT, TITLE, nil, nil)
    if window == nil {
        fmt.eprintln("GLFW CreateWindow failed")
        return
    }
	defer glfw.DestroyWindow(window)

    glfw.SetCursorPosCallback(window, on_cursor)
    glfw.SetMouseButtonCallback(window, on_mouse)

    glfw.MakeContextCurrent(window)
    gl.load_up_to(3, 3, glfw.gl_set_proc_address)
    gl.ClearColor(0.0, 0.0, 0.0, 1.0)
    gl.Enable(gl.DEPTH_TEST)
    create()

    last_tick = time.tick_now()
    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        duration := time.tick_lap_time(&last_tick)
        dt := cast(f32) time.duration_seconds(duration)
        draw_frame(dt)
        glfw.SwapBuffers(window)
    }
}

Vertex :: struct {
    position : [3] f32,
    color    : [3] f32,
}
vertex_buffer : Vertex_Buffer
vertex_array  : Vertex_Array
shader        : Shader
sky_shader    : Shader
mesh          : Mesh

create :: proc() {
    shader = load_shader (
        "shaders/solid_color.vert",
        "shaders/solid_color.frag"
    )
    sky_shader = load_shader (
        "shaders/solid_color.vert",
        "shaders/skybox_like.frag"
    )

    vertices : [] Vertex : {
        {{0,0,10}, {1,1,1}},
        {{0,1,10}, {0,0,1}},
        {{1,0,10}, {1,1,1}},
    }

    vertex_buffer = load_vertex_buffer(vertices)

    {
        vertices: [] Vertex : {
            // Front face
            {{-0.5, -0.5,  0.5}, {0,0,1}}, // 0 Bottom-left
            {{ 0.5, -0.5,  0.5}, {1,0,1}}, // 1 Bottom-right
            {{ 0.5,  0.5,  0.5}, {1,1,1}}, // 2 Top-right
            {{-0.5,  0.5,  0.5}, {0,1,1}}, // 3 Top-left

            // Back face
            {{-0.5, -0.5, -0.5}, {0,0,0}}, // 4 Bottom-left
            {{ 0.5, -0.5, -0.5}, {1,0,0}}, // 5 Bottom-right
            {{ 0.5,  0.5, -0.5}, {1,1,0}}, // 6 Top-right
            {{-0.5,  0.5, -0.5}, {0,1,0}}, // 7 Top-left
        }

        indices: [] u32 : {
            // Front face
            0, 1, 2,
            2, 3, 0,

            // Back face
            4, 5, 6,
            6, 7, 4,

            // Left face
            4, 0, 3,
            3, 7, 4,

            // Right face
            1, 5, 6,
            6, 2, 1,

            // Top face
            3, 2, 6,
            6, 7, 3,

            // Bottom face
            4, 5, 1,
            1, 0, 4,
        }

        mesh = create_mesh(vertices, indices)
    }

    vertex_array = create_vertex_array(Vertex)
}

t : f32 = 0

draw_frame :: proc(dt: f32) {
    mvp : glm.mat4
    bind(shader)
    bind(vertex_array)

    gl.DepthMask(gl.FALSE)
    bind(vertex_buffer)
    mvp = math.identity(glm.mat4)
    gl.UniformMatrix4fv(gl.GetUniformLocation(shader.id, "u_transform"), 1, gl.FALSE, auto_cast &mvp)
    gl.DrawArrays(gl.TRIANGLES, 0, 3)

    gl.DepthMask(gl.TRUE)
    mvp = view_projection(camera) //* math.matrix4_from_euler_angle_y(t)
    gl.UniformMatrix4fv(gl.GetUniformLocation(shader.id, "u_transform"), 1, gl.FALSE, auto_cast &mvp)
    draw(mesh)

    bind(sky_shader)
    mvp = view_projection(camera) * math.matrix4_scale_f32(20) //* math.matrix4_from_euler_angle_y(t)
    gl.UniformMatrix4fv(gl.GetUniformLocation(shader.id, "u_transform"), 1, gl.FALSE, auto_cast &mvp)
    draw(mesh)
    t += dt
}

LeftDown, RightDown: bool
MouseX,   MouseY:    int
camera: Camera = default_camera()

on_mouse :: proc "cdecl" (window: glfw.WindowHandle, button, action, mods: i32) {
    if button == glfw.MOUSE_BUTTON_LEFT {
        LeftDown = (action == glfw.PRESS)
    }
    if button == glfw.MOUSE_BUTTON_RIGHT {
        RightDown = (action == glfw.PRESS)
    }
}

on_cursor :: proc "cdecl" (window: glfw.WindowHandle, currX, currY: f64) {
    maxDelta :: 100
    dx := cast(f32) clamp(cast(int) currX - MouseX, -maxDelta, maxDelta)
    dy := cast(f32) clamp(-(cast(int) currY - MouseY), -maxDelta, maxDelta)

    MouseX = cast(int) currX
    MouseY = cast(int) currY

    // Move camera
    // NOTE: this should really be part of Camera::Update()
    if (LeftDown) {
        rate :: 1.0
        camera.azimuth = camera.azimuth + dx * rate;
        camera.incline = clamp(camera.incline - dy * rate, -90.0, 90.0);
    }
    if (RightDown) {
        rate :: 0.005
        camera.distance = clamp(camera.distance * (1.0 - dx * rate), 0.01, 1000.0);
    }
}

error_callback :: proc "cdecl" (code: i32, desc: cstring) {
    context = runtime.default_context()
    fmt.println(desc, code)
}

