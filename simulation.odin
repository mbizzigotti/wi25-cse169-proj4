package proj4
import "base:runtime"
import "core:mem"
import "core:fmt"
import m "core:math"
import math "core:math/linalg"

Particle :: struct {
    pos:    [3] f32,
    vel:    [3] f32,
    force:  [3] f32,
    mass:       f32,
}

Spring_Damper :: struct {
    p0, p1: u32, // particles
    ks, kd: f32, // spring constant and damping factor
    l:      f32, // rest length
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
    sim_time:            f32,
    drop:                bool,

    // Draw Data
    mesh:                Mesh,
}

Vertex :: struct {
    position : [3] f32,
    color    : [3] f32,
    normal   : [3] f32,
}

create_cloth :: proc(w, h: i32) -> Cloth {
    using runtime
    using cloth: Cloth

    // create a custom allocator 😊
    mem.arena_init(&arena, make([] u8, runtime.Megabyte))
    allocator := mem.arena_allocator(&arena)

    // allocate memory for simulation data
    dim = { w, h }
    particles = make([] Particle, w * h, allocator)
    spring_count := w * (h - 1) + h * (w - 1) + 2 * (w - 1) * (h - 1)
    springs = make([] Spring_Damper, spring_count, allocator)
    normals = make([] [3] f32, w * h, allocator)

    // allocate (GPU) memory for draw data
    temp_vertices := make([] Vertex, w * h, context.temp_allocator)
    mesh.vertex_buffer = load_vertex_buffer(temp_vertices)
    temp_indices := make([] u32, 3 * 2 * (w - 1) * (h - 1), context.temp_allocator)
    i := 0
    for y in 0..<(h-1) {
        for x in 0..<(w-1) {
            base := y * w + x
            temp_indices[i] = cast(u32) (base + 0);     i += 1
            temp_indices[i] = cast(u32) (base + 1);     i += 1
            temp_indices[i] = cast(u32) (base + w);     i += 1
            temp_indices[i] = cast(u32) (base + 1);     i += 1
            temp_indices[i] = cast(u32) (base + w + 1); i += 1
            temp_indices[i] = cast(u32) (base + w);     i += 1
        }
    }
    mesh.index_buffer = load_index_buffer(temp_indices)
    mesh.index_count = cast(i32) len(temp_indices)
    free_all(context.temp_allocator)

    // set all spring connections
    i = 0
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
    return cloth
}


cloth_default_z :: proc(t: f32) -> f32 {
    return -1.0
    //return m.sin(t) * 0.1 - 1.0;
    //t := 0.1 * t
    //return 6 * m.abs(m.mod(t + 1, 2) - 1) - 3
    //t := 0.5 * t
    //return m.cos(t) + m.cos(3 * t) * 0.5
}

reset_cloth :: proc(using cloth: ^Cloth) {
    sim_time = 0
    drop = false
    air_velocity = {0,0,10}
    air_constant = -10.0

    // reset particle data
    size  := [2] f32 { 5.0, 2.0 }
    scale := size / [2] f32 { cast(f32) (dim.x - 1), cast(f32) (dim.y - 1) }
    posz  := cloth_default_z(sim_time)
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
            particles[i].mass = 1.0
        }
    }

    // reset spring data
    for &s in springs {
        s.ks = 150000.0
        s.kd = 1500.0
        s.l  = math.length(particles[s.p0].pos - particles[s.p1].pos)
    }
}

simulation_draw :: proc(using cloth: ^Cloth) {
    // First we need to generate our vertex data
    temp_vertices := make([] Vertex, dim.x * dim.y, context.temp_allocator)
    for p, i in particles {
        temp_vertices[i] = { position = p.pos, color = {0.7,0.8,1}, normal = normals[i] }
    }

    // Then we pass the data to the GPU
    upload(mesh.vertex_buffer, temp_vertices)

    // Now we can Draw!
    draw(mesh)
}

simulation_step :: proc(using cloth: ^Cloth, dt: f32) {
    // Reset all forces and normals
    gravity :: [3] f32 { 0, -9.8, 0 }
    for &p in particles { p.force = gravity * p.mass }
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
            
            n0 := math.cross(p1 - p0, p2 - p0);
            a0 := math.length(n0)
            n0 /= a0
            n1 := math.cross(p2 - p3, p1 - p3);
            a1 := math.length(n1)
            n1 /= a1
            
            vs0 := (v0 + v1 + v2) / 3.0 - air_velocity
            vs1 := (v1 + v2 + v3) / 3.0 - air_velocity
            
            a0 *= math.dot(vs0, n0) / math.length(vs0)
            a1 *= math.dot(vs1, n1) / math.length(vs1)
            
            f0 := air_constant * math.dot(vs0, vs0) * a0 * n0
            f1 := air_constant * math.dot(vs1, vs1) * a1 * n1
            
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
        n = math.normalize(n)
    }
    // Apply forces from springs
    for s in springs {
        to_p1 := particles[s.p1].pos - particles[s.p0].pos
        l := math.length(to_p1)
        tangent := to_p1 / l
        v1 := math.dot(particles[s.p0].vel, tangent)
        v2 := math.dot(particles[s.p1].vel, tangent)

        f := s.ks * (l - s.l) - s.kd * (v1 - v2)
        particles[s.p0].force += f * to_p1
        particles[s.p1].force -= f * to_p1
    }
    // Integrate
    for &p, i in particles {
        if !drop && (i < cast(int) dim.x) {
        //if !drop && (i == 0 || i == cast(int) dim.x - 1 || i == cast(int) dim.x / 2) {
            continue
        }
        using p
        acc := force / mass
        vel += acc * dt
        pos = pos + vel * dt

        // sphere object
        if math.dot(pos, pos) < (0.5 * 0.5) {
            pos = math.normalize(pos)
            len := math.length(vel)
            vel += vel * min(math.dot(pos, vel), 0.0)
            if math.dot(vel, vel) > 0.01 {
                vel = math.normalize(vel) * len // try best to conserve energy
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
    // fun
    if !drop {
        z := cloth_default_z(sim_time)
        for &p in particles[:dim.x] {
            p.pos.z = z
        }
        //particles[0]      .pos.z = z
        //particles[dim.x/2].pos.z = z
        //particles[dim.x-1].pos.z = z
    }

    sim_time += dt
}

