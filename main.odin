package proj4
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:time"
import glfw "vendor:GLFW"
import gl   "vendor:OpenGL"
import glm  "core:math/linalg/glsl"
import math "core:math/linalg"

WIDTH  :: 800
HEIGHT :: 600
TITLE  :: "CSE 169 Cloth Simulation"

window    : glfw.WindowHandle
last_tick : time.Tick
current_time: f32 = 0
enable_sim : bool = true

env: struct {
    sky_shader:   Shader,
    cloth_shader: Shader,
    floor_shader: Shader,
    cloth:        Cloth,
    sphere:       Mesh,
}

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
    glfw.SetKeyCallback(window, on_key)

    glfw.MakeContextCurrent(window)
    gl.load_up_to(3, 3, glfw.gl_set_proc_address)
    gl.ClearColor(0.0, 0.0, 0.0, 1.0)
    gl.Enable(gl.DEPTH_TEST)

    { // Initialization
        using env
    
        sky_shader = load_shader (
            "shaders/skybox.vert",
            "shaders/skybox_like.frag"
        )
        cloth_shader = load_shader (
            "shaders/cloth.vert",
            "shaders/cloth.frag"
        )
        floor_shader = load_shader (
            "shaders/floor.vert",
            "shaders/floor.frag"
        )
        sphere = create_sphere(Vertex, {1,1,0.4})
        cloth = create_cloth(40, 30)
    
        reset_cloth(&cloth)
    }

    last_tick = time.tick_now()
    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        duration := time.tick_lap_time(&last_tick)
        dt := min(cast(f32) time.duration_seconds(duration), 1.0/60.0)
        draw_frame(dt)
        if enable_sim { current_time += dt }
        glfw.SwapBuffers(window)
        free_all(context.temp_allocator)
    }
}

draw_frame :: proc(dt: f32) {
    using env

    view, proj := view_projection(camera)
    model := math.identity(glm.mat4)
    view_proj := proj * glm.inverse(view)
    pos: glm.vec4 = view[3]

    if enable_sim {
        num_steps :: 16
        for k in 0..<num_steps {
            simulation_step(&cloth, dt / cast(f32) num_steps)
        }
    }
    
    gl.CullFace(gl.FRONT)
    gl.Disable(gl.CULL_FACE)
    gl.Disable(gl.BLEND)
    
    bind(cloth_shader)
    gl.Uniform3fv(gl.GetUniformLocation(cloth_shader.id, "u_ViewPos"), 1, auto_cast &pos)
    gl.UniformMatrix4fv(gl.GetUniformLocation(cloth_shader.id, "u_ViewProj"), 1, gl.FALSE, auto_cast &view_proj)
    gl.UniformMatrix4fv(gl.GetUniformLocation(cloth_shader.id, "u_Model"),    1, gl.FALSE, auto_cast &model)
    simulation_draw(&cloth)
    
    model = math.matrix4_scale_f32(0.48)
    gl.UniformMatrix4fv(gl.GetUniformLocation(cloth_shader.id, "u_Model"), 1, gl.FALSE, auto_cast &model)
    draw(sphere)
    
    gl.Enable(gl.CULL_FACE)
    bind(sky_shader)
    gl.UniformMatrix4fv(gl.GetUniformLocation(sky_shader.id, "u_ViewProj"), 1, gl.FALSE, auto_cast &view_proj)
    gl.DrawArrays(gl.TRIANGLES, 0, 36)
    
    gl.CullFace(gl.BACK)
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);  
    bind(floor_shader)
    gl.Uniform3fv(gl.GetUniformLocation(floor_shader.id, "u_ViewPos"), 1, auto_cast &pos)
    gl.UniformMatrix4fv(gl.GetUniformLocation(floor_shader.id, "u_ViewProj"), 1, gl.FALSE, auto_cast &view_proj)
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
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
on_key :: proc "cdecl" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    if action != glfw.PRESS { return } // Check for a key press.

    switch key {
        case glfw.KEY_ESCAPE:
            glfw.SetWindowShouldClose(window, glfw.TRUE)
        break;

        case glfw.KEY_R:
            current_time = 0
            context = runtime.default_context()
            reset_cloth(&env.cloth)
        break;

        case glfw.KEY_SPACE:
            enable_sim = !enable_sim
        break;

        case glfw.KEY_D:
            env.cloth.drop = true
        break;
    }
}

error_callback :: proc "cdecl" (code: i32, desc: cstring) {
    context = runtime.default_context()
    fmt.println(desc, code)
}

