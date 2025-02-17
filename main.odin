package example;
import "base:runtime"
import "core:mem"
import "core:math"
import "core:math/linalg"

@(default_calling_convention = "c")
foreign {
    set_view_projection   :: proc(view_proj: ^f32) ---
    get_aspect            :: proc() -> f32 ---
    draw_scene            :: proc() ---
    upload_cloth_vertices :: proc(count: int, positions, colors, normals: ^f32) ---
}

Particle :: struct {
    pos:    [3] f32,
    vel:    [3] f32,
    force:  [3] f32,
    fixed:  bool,
}

Spring_Damper :: struct {
    p0, p1: u32, // particles
    ks, kd: f32, // spring constant and damping factor
    l:      f32, // rest length
}

Fixed_State :: enum {
    FIX_NONE,
    FIX_TOP,
    FIX_TOP_CORNERS,
}

Cloth :: struct {
    // Memory
    arena:               mem.Arena,

    // Simulation Data
    dim:                 [2] i32,
    particles:           [] Particle,
    springs:             [] Spring_Damper,
    normals:             [] [3] f32,
    air_velocity:        [3] f32,
    air_constant:        f32, // p * cd
    mass:                f32, // mass of each particle
    sim_time:            f32,
    fixed_velocity:      [2] f32, // how to move the fixed particles (user interaction)
    fixed_state:         Fixed_State,

    // Draw Data
    positions: [] [3] f32,
    colors: [] [3] f32,
}

memory : [runtime.Megabyte] u8;
camera  : Camera;
cloth   : Cloth;

create_cloth :: proc(w, h: i32) -> Cloth {
    using runtime
    using cloth: Cloth

    // create a custom allocator 😊
    mem.arena_init(&arena, memory[:])
    allocator := mem.arena_allocator(&arena)

    // allocate memory for simulation data
    dim = { w, h }
    particles = make([] Particle, w * h, allocator)
    spring_count := w * (h - 1) + h * (w - 1) + 2 * (w - 1) * (h - 1)
    spring_count += 6 * (w - 2) * (h - 2);
    springs = make([] Spring_Damper, spring_count, allocator)
    normals   = make([] [3] f32, w * h, allocator)
    positions = make([] [3] f32, w * h, allocator)
    colors    = make([] [3] f32, w * h, allocator)

    for &s in springs {
        s.ks = 30000.0
        s.kd = 150.0
    }

    // set all spring connections
    i := 0
    for y in 0..<h {
        for x in 0..<w - 1 {
            springs[i].p0 = cast(u32) (y * w + x)
            springs[i].p1 = cast(u32) (y * w + x + 1)
            i += 1
        }
    }
    for y in 0..<h - 1 {
        for x in 0..<w {
            springs[i].p0 = cast(u32) ( y      * w + x)
            springs[i].p1 = cast(u32) ((y + 1) * w + x)
            i += 1
        }
    }
    for y in 0..<h - 1 {
        for x in 0..<w -1 {
            springs[i].p0 = cast(u32) ( y      * w + x)
            springs[i].p1 = cast(u32) ((y + 1) * w + x + 1)
            i += 1
            springs[i].p0 = cast(u32) ( y      * w + x + 1)
            springs[i].p1 = cast(u32) ((y + 1) * w + x)
            i += 1
        }
    }

    bend_constant :: 50.0;
    for y in 0..<h-2 {
        for x in 0..<w-2 {
            base := y * w + x;
            i0 := cast(u32) (base);
            i1 := cast(u32) (base + 2);
            i2 := cast(u32) (base + 2*w);
            i3 := cast(u32) (base + 2*w + 2);

            springs[i].p0 = i0
            springs[i].p1 = i1
            springs[i].ks = bend_constant;
            i += 1

            springs[i].p0 = i1
            springs[i].p1 = i3
            springs[i].ks = bend_constant;
            i += 1
            
            springs[i].p0 = i3
            springs[i].p1 = i2
            springs[i].ks = bend_constant;
            i += 1

            springs[i].p0 = i2
            springs[i].p1 = i0
            springs[i].ks = bend_constant;
            i += 1

            springs[i].p0 = i0
            springs[i].p1 = i3
            springs[i].ks = bend_constant;
            i += 1

            springs[i].p0 = i1
            springs[i].p1 = i2
            springs[i].ks = bend_constant;
            i += 1
        }
    }
    return cloth
}

simulation_step :: proc(using cloth: ^Cloth, dt: f32) {
    // Reset all forces and normals
    gravity :: [3] f32 { 0, -9.8, 0 }
    for &p in particles { p.force = gravity * mass }
    for &n in normals { n = {} }
    // Calculate normals & Apply forces from aerodynamics
    for y in 0..<dim.y - 1 {
        for x in 0..<dim.x - 1 {
            i0 :=  y    * dim.x +  x   
            i1 :=  y    * dim.x + (x+1)
            i2 := (y+1) * dim.x +  x   
            i3 := (y+1) * dim.x + (x+1)
            
            v0, p0 := particles[i0].vel, particles[i0].pos
            v1, p1 := particles[i1].vel, particles[i1].pos
            v2, p2 := particles[i2].vel, particles[i2].pos
            v3, p3 := particles[i3].vel, particles[i3].pos
            
            n0 := linalg.cross(p1 - p0, p2 - p0);
            a0 := linalg.length(n0)
            n0 /= a0
            n1 := linalg.cross(p2 - p3, p1 - p3);
            a1 := linalg.length(n1)
            n1 /= a1
            
            vs0 := (v0 + v1 + v2) / 3.0 - air_velocity
            vs1 := (v1 + v2 + v3) / 3.0 - air_velocity
            
            a0 *= linalg.dot(vs0, n0) / linalg.length(vs0)
            a1 *= linalg.dot(vs1, n1) / linalg.length(vs1)
            
            f0 := air_constant * linalg.dot(vs0, vs0) * a0 * n0
            f1 := air_constant * linalg.dot(vs1, vs1) * a1 * n1
            
            particles[i0].force += f0 / 3.0
            particles[i1].force += f0 / 3.0
            particles[i2].force += f0 / 3.0
            particles[i1].force += f1 / 3.0
            particles[i2].force += f1 / 3.0
            particles[i3].force += f1 / 3.0
            
            normals[i0] += n0
            normals[i1] += n0
            normals[i2] += n0
            normals[i1] += n1
            normals[i2] += n1
            normals[i3] += n1
        }
    }
    for &n in normals {
        n = linalg.normalize(n)
    }
    // Apply forces from springs
    for s in springs {
        to_p1 := particles[s.p1].pos - particles[s.p0].pos
        l := linalg.length(to_p1)
        tangent := to_p1 / l
        v1 := linalg.dot(particles[s.p0].vel, tangent)
        v2 := linalg.dot(particles[s.p1].vel, tangent)

        f := s.ks * (l - s.l) - s.kd * (v1 - v2)
        particles[s.p0].force += f * to_p1
        particles[s.p1].force -= f * to_p1
    }
    // Integrate
    for &p, i in particles {
        using p
        
        if p.fixed {
            pos += {fixed_velocity.x, 0, fixed_velocity.y} * dt;
            continue;
        }

        acc := force / mass
        vel = vel + acc * dt
        pos = pos + vel * dt

        // sphere object
        if linalg.dot(pos, pos) < (0.5 * 0.5) {
            pos = linalg.normalize(pos)
            len := linalg.length(vel)
            vel += vel * min(linalg.dot(pos, vel), 0.0)
            if linalg.dot(vel, vel) > 0.01 {
                vel = linalg.normalize(vel) * len // try best to conserve energy
            }
            pos *= 0.5
        }

        // ground plane
        y0, elasticity, friction :: -1.0, 1.0, 0.1;
        if pos.y < y0 {
            pos.y= 2*y0 - pos.y;
            vel.y= - elasticity * vel.y;
            vel.x= (1-friction) * vel.x; // cheezy
            vel.z= (1-friction) * vel.z; // cheezy
        }
    }

    sim_time += dt
}

set_fixed :: proc(using cloth: ^Cloth, state: Fixed_State) {
    for &p in particles {
        p.fixed = false;
    }
    #partial switch state {
    case .FIX_TOP:
        for &p in particles[:dim.x] {
            p.fixed = true;
        }
    break;
    case .FIX_TOP_CORNERS:
        particles[0]      .fixed = true;
        particles[dim.x-1].fixed = true;
    break;
    }
    cloth.fixed_state = state; 
}

reset_cloth :: proc(using cloth: ^Cloth) {
    sim_time = 0;
    air_velocity = {0,0,10};
    air_constant = -10.0;
    mass = 1.0;

    // reset particle data
    size  := [2] f32 { 5.0, 2.0 }
    scale := size / [2] f32 { cast(f32) (dim.x - 1), cast(f32) (dim.y - 1) }
    posz  : f32 = -1;
    for y in 0..<dim.y {
        posy := (size.y - cast(f32) y * scale.y) - size.y * 0.3
        for x in 0..<dim.x {
            i := y * dim.x + x
            particles[i].pos = {
                cast(f32) x * scale.x - size.x * 0.5,
                posy,
                posz,
            }
            particles[i].vel = {}
        }
    }
    set_fixed(cloth, .FIX_TOP);

    // reset spring data
    for &s in springs {
        s.l  = linalg.length(particles[s.p0].pos - particles[s.p1].pos)
    }
}

@export
setup :: proc() {
    camera = default_camera();
    cloth = create_cloth(40, 30);
    reset_cloth(&cloth);
}

@export
update :: proc(dt: f32) {
    if cloth.sim_time > 5.0 {
        set_fixed(&cloth, .FIX_NONE);
    }

    num_steps :: 16
    dt := min(dt, 1.0 / 60);
    for k in 0..<num_steps {
        simulation_step(&cloth, dt / cast(f32) num_steps)
    }

    {
        for p, i in cloth.particles {
            cloth.positions[i] = p.pos;
            cloth.colors[i] = {0.7,0.8,1};
        }
        
        pos := &(cloth.positions[0].x);
        col := &(cloth.colors   [0].x);
        nor := &(cloth.normals  [0].x);

        upload_cloth_vertices(40 * 30, pos, col, nor);
    }

    view_proj := view_projection_from_camera(&camera);
    set_view_projection(&view_proj[0][0]);
    draw_scene();
}


LeftDown, RightDown : bool;
MouseX,   MouseY    : i32;

@export
on_mouse_down :: proc() {
    LeftDown = true;
}

@export
on_mouse_up :: proc() {
    LeftDown = false;
}

@export
on_mouse_move :: proc(x, y: f32) {
    maxDelta :: 100;

    dx := cast(f32) clamp(  cast(i32) x - MouseX,  -maxDelta, maxDelta);
    dy := cast(f32) clamp(-(cast(i32) y - MouseY), -maxDelta, maxDelta);

    MouseX = cast(i32) x
    MouseY = cast(i32) y

    // Move camera
    if (LeftDown) {
        rate :: 0.01
        camera.azimuth = camera.azimuth + dx * rate;
        camera.incline = clamp(camera.incline - dy * rate, -math.PI / 2, math.PI / 2);
    }
    if (RightDown) {
        rate :: 0.005
        camera.distance = clamp(camera.distance * (1.0 - dx * rate), 0.01, 1000.0);
    }
}

@export
on_key_down :: proc(key: int) {
    switch key {
        case 'r': reset_cloth(&cloth);
    }
}

Camera :: struct {
    fov,      // Field of View Angle (degrees)
    aspect,   // Aspect Ratio
    near,     // Near clipping plane distance
    far,      // Far clipping plane distance
    distance, // Distance of the camera eye position to the origin (meters)
    azimuth,  // Rotation of the camera eye position around the Y axis (degrees)
    incline,  // Angle of the camera eye position over the XZ plane (degrees)
    : f32
}

default_camera :: proc() -> Camera {
    return {
        fov      = math.PI / 4,
        aspect   = 1.0,
        near     = 0.1,
        far      = 100.0,
        distance = 8.0,
        azimuth  = math.PI / 3,
        incline  = math.PI / 18,
    }
}

view_projection_from_camera :: proc(using camera: ^Camera) -> matrix [4,4] f32 {
    aspect = get_aspect();
    world := linalg.identity(matrix [4,4] f32);
    world[3][2] = distance;
    world = linalg.matrix4_from_euler_angle_y(azimuth) \
          * linalg.matrix4_from_euler_angle_x(incline) \
          * world;
    view := linalg.matrix4_inverse(world);
    project := linalg.matrix4_perspective(fov, aspect, near, far);
    return project * view;
}