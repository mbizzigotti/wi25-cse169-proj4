package proj4
import "base:runtime"
import "core:fmt"
import time "core:time"
import glfw "vendor:GLFW"
import gl   "vendor:OpenGL"

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
        fmt.eprintln("GLFW CreateWindow failed");
        return
    }
	defer glfw.DestroyWindow(window)

    glfw.MakeContextCurrent(window)
    gl.load_up_to(3, 3, glfw.gl_set_proc_address)
    gl.ClearColor(0.0, 0.0, 1.0, 1.0)

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

draw_frame :: proc(dt: f32) {


}

error_callback :: proc "cdecl" (code: i32, desc: cstring) {
    context = runtime.default_context()
    fmt.println(desc, code)
}

