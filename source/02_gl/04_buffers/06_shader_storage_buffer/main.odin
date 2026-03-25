package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Shared Storage Buffer"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

PARTICLE_CAP :: 1024
PARTICLE_POS_MIN :: f32(-256)
PARTICLE_POS_MAX :: f32(256)
PARTICLE_RADIUS_MIN :: f32(4)
PARTICLE_RADIUS_MAX :: f32(12)
PARTICLE_SPEED_MIN :: f32(200)
PARTICLE_SPEED_MAX :: f32(400)

COMPUTE_CS :: GLSL_VERSION + `
    layout(local_size_x = 64) in;

    struct Particle {
        vec2 position;
        vec2 velocity;
        float radius;
        int color;
    };

    layout(std430, binding = 0) buffer Particle_Buffer {
        Particle particles[];
    };

    uniform vec2 u_viewport;
    uniform float u_delta_time;

    void main() {
        uint i = gl_GlobalInvocationID.x;

        if (i >= particles.length()) {
            return;
        }

        // Integrate
        particles[i].position += particles[i].velocity * u_delta_time;

        // Resolve collision
        vec2 bounds = u_viewport / 2.0;

        if (abs(particles[i].position.x) + particles[i].radius > bounds.x) {
            particles[i].velocity.x *= -1.0;
            particles[i].position.x = sign(particles[i].position.x) * (bounds.x - particles[i].radius);
        }

        if (abs(particles[i].position.y) + particles[i].radius > bounds.y) {
            particles[i].velocity.y *= -1.0;
            particles[i].position.y = sign(particles[i].position.y) * (bounds.y - particles[i].radius);
        }
    }
`

MAIN_VS :: GLSL_VERSION + `
    struct Particle {
        vec2 position;
        vec2 velocity;
        float radius;
        int color;
    };

    layout(std430, binding = 0) readonly buffer Particle_Buffer {
        Particle particles[];
    };

    out vec2 v_tex_coord;
    out vec3 v_color;

    uniform mat4 u_projection;

    // Top left origin
    const vec2 POSITIONS[] = vec2[](
        vec2(-1.0,  1.0),
        vec2(-1.0, -1.0),
        vec2( 1.0,  1.0),
        vec2( 1.0, -1.0)
    );

    const vec2 TEX_COORDS[] = vec2[](
        vec2(0.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 0.0),
        vec2(1.0, 1.0)
    );

    vec3 unpack_color(int color) {
        return vec3(
            (color >> 16) & 0xFF,
            (color >> 8) & 0xFF,
            color & 0xFF
        ) / 255.0;
    }

    void main() {
        Particle particle = particles[gl_InstanceID];
        vec2 position = POSITIONS[gl_VertexID] * particle.radius + particle.position;

        gl_Position = u_projection * vec4(position, 0.0, 1.0);
        v_tex_coord = TEX_COORDS[gl_VertexID];
        v_color = unpack_color(particle.color);
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;
    in vec3 v_color;

    out vec4 o_frag_color;

    void main() {
        vec2 uv = v_tex_coord;
        vec2 cp = uv * 2.0 - 1.0;
        float alpha = 1.0 - smoothstep(0.9, 1.0, length(cp));

        o_frag_color = vec4(v_color, alpha);
    }
`

Particle :: struct {
    position: glm.vec2,
    velocity: glm.vec2,
    radius: f32,
    color: i32,
}

pack_color :: proc(color: glm.ivec3) -> i32 {
    return (color.x << 16) | (color.y << 8) | color.z
}

random_color :: proc() -> i32 {
    return pack_color({rand.int31() % 256, rand.int31() % 256, rand.int31() % 256})
}

main :: proc() {
    if !sdl.Init({.VIDEO}) {
        fmt.printf("SDL ERROR: %s\n", sdl.GetError())

        return
    }

    defer sdl.Quit()

    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, auto_cast(sdl.GLProfile.CORE))
    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_VERSION_MAJOR)
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_VERSION_MINOR)

    window := sdl.CreateWindow(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, {.OPENGL, .RESIZABLE})
    defer sdl.DestroyWindow(window)

    gl_context := sdl.GL_CreateContext(window)
    defer sdl.GL_DestroyContext(gl_context)

    gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, sdl.gl_set_proc_address)

    sdl.SetWindowPosition(window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)

    viewport_x, viewport_y: i32; sdl.GetWindowSize(window, &viewport_x, &viewport_y)
    time_curr := u64(sdl.GetTicks())
    time_last: u64
    time_delta: f32

    compute_pg, compute_ok := gl.load_compute_source(COMPUTE_CS); defer gl.DeleteProgram(compute_pg)
    compute_uf := gl.get_uniforms_from_program(compute_pg); defer gl.destroy_uniforms(compute_uf);
    assert(compute_ok, "ERROR: Failed to compile program")

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);
    assert(main_ok, "ERROR: Failed to compile program")

    particles: [PARTICLE_CAP]Particle

    for &particle in particles {
        angle := rand.float32_range(0, glm.TAU)
        speed := rand.float32_range(PARTICLE_SPEED_MIN, PARTICLE_SPEED_MAX)

        particle.position = {rand.float32_range(PARTICLE_POS_MIN, PARTICLE_POS_MAX), rand.float32_range(PARTICLE_POS_MIN, PARTICLE_POS_MAX)}
        particle.radius = rand.float32_range(PARTICLE_RADIUS_MIN, PARTICLE_RADIUS_MAX)
        particle.velocity = {glm.cos(angle) * speed, glm.sin(angle) * speed}
        particle.color = random_color()
    }

    particle_ssbo: u32; gl.GenBuffers(1, &particle_ssbo); defer gl.DeleteBuffers(1, &particle_ssbo)
    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, particle_ssbo)
    gl.BufferData(gl.SHADER_STORAGE_BUFFER, PARTICLE_CAP * size_of(Particle), &particles, gl.DYNAMIC_DRAW)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, particle_ssbo)

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    loop: for {
        time_curr = u64(sdl.GetTicks())
        time_delta = f32(time_curr - time_last) / 1000
        time_last = time_curr

        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
            }
        }

        bounds := glm.vec2{f32(viewport_x) / 2, f32(viewport_y) / 2}
        projection := glm.mat4Ortho3d(-f32(viewport_x) / 2, f32(viewport_x) / 2, -f32(viewport_y) / 2, f32(viewport_y) / 2, -1, 1)

        // Update
        gl.UseProgram(compute_pg)
        gl.Uniform2f(compute_uf["u_viewport"].location, f32(viewport_x), f32(viewport_y))
        gl.Uniform1f(compute_uf["u_delta_time"].location, time_delta)
        gl.DispatchCompute(u32((PARTICLE_CAP + 63) / 64), 1, 1)
        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT)

        // Render
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.5, 0.5, 0.5, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &projection[0][0])
        gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, PARTICLE_CAP)

        sdl.GL_SwapWindow(window)
    }
}
