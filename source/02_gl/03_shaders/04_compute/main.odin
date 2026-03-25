package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Compute"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

QUAD_SIZE :: f32(256)
TEXTURE_WIDTH :: 256
TEXTURE_HEIGHT :: 256

COMPUTE_CS :: GLSL_VERSION + `
    layout(local_size_x = 16, local_size_y = 16) in;
    layout(rgba8, binding = 0) uniform writeonly image2D u_output;

    uniform float u_time;

    const vec3 COLOR_OUTSIDE = vec3(0.53, 0.81, 0.92);
    const vec3 COLOR_INSIDE = vec3(0.85, 0.10, 0.15);
    const float PULSE_AMPLITUDE = 0.1;
    const float PULSE_SPEED = 4.0;
    const float FALLOFF_SHARP = 6.0;
    const float RIPPLE_FREQ = 128.0;
    const float EDGE_SOFTNESS = 0.01;

    float dot2(vec2 v) {
        return dot(v, v);
    }

    // Source: https://iquilezles.org/articles/distfunctions2d/
    float sd_heart(in vec2 p) {
        p.y += 0.5;
        p.x = abs(p.x);

        if (p.y + p.x > 1.0) {
            return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
        }

        return sqrt(min(
            dot2(p - vec2(0.0, 1.0)),
            dot2(p - 0.5 * max(p.x + p.y, 0.0))
        )) * sign(p.x - p.y);
    }

    void main() {
        ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
        ivec2 size = imageSize(u_output);

        vec2 uv = (vec2(coord) + 0.5) / vec2(size);
        vec2 p = 2.0 * uv - 1.0;

        float scale = 1.0 + PULSE_AMPLITUDE * sin(u_time * PULSE_SPEED);
        float d = sd_heart(p / scale);

        vec3 color = (d > 0.0) ? COLOR_OUTSIDE : COLOR_INSIDE;
        color *= 1.0 - exp(-FALLOFF_SHARP * abs(d));
        color *= 0.8 + 0.2 * cos(RIPPLE_FREQ * d);
        color = mix(color, vec3(1.0), 1.0 - smoothstep(0.0, EDGE_SOFTNESS, abs(d)));

        imageStore(u_output, coord, vec4(color, 1.0));
    }
`

MAIN_VS :: GLSL_VERSION + `
    out vec2 v_tex_coord;

    uniform mat4 u_projection;
    uniform vec2 u_quad_size;

    // Bottom left origin
    const vec2 POSITIONS[] = vec2[](
        vec2(-0.5, -0.5),
        vec2( 0.5, -0.5),
        vec2(-0.5,  0.5),
        vec2( 0.5,  0.5)
    );

    const vec2 TEX_COORDS[] = vec2[](
        vec2(0.0, 0.0),
        vec2(1.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 1.0)
    );

    void main() {
        gl_Position = u_projection * vec4(POSITIONS[gl_VertexID] * u_quad_size, 0.0, 1.0);
        v_tex_coord = TEX_COORDS[gl_VertexID];
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_texture;

    void main() {
        o_frag_color = texture(u_texture, v_tex_coord);
    }
`

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

    compute_pg, compute_ok := gl.load_compute_source(COMPUTE_CS); defer gl.DeleteProgram(compute_pg)
    compute_uf := gl.get_uniforms_from_program(compute_pg); defer gl.destroy_uniforms(compute_uf);
    assert(compute_ok, "ERROR: Failed to compile program")

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);
    assert(main_ok, "ERROR: Failed to compile program")

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_tex: u32; gl.GenTextures(1, &main_tex); defer gl.DeleteTextures(1, &main_tex)
    gl.BindTexture(gl.TEXTURE_2D, main_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, TEXTURE_WIDTH, TEXTURE_HEIGHT, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    loop: for {
        time_seconds := f32(sdl.GetTicks()) / 1000.0

        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
            }
        }

        projection := glm.mat4Ortho3d(-f32(viewport_x) / 2, f32(viewport_x) / 2, -f32(viewport_y) / 2, f32(viewport_y) / 2, -1, 1)

        // Render to texture
        gl.UseProgram(compute_pg)
        gl.Uniform1f(compute_uf["u_time"].location, time_seconds)
        gl.BindImageTexture(0, main_tex, 0, false, 0, gl.WRITE_ONLY, gl.RGBA8)
        gl.DispatchCompute(u32((TEXTURE_WIDTH + 15) / 16), u32((TEXTURE_HEIGHT + 15) / 16), 1)
        gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)

        // Output to main window framebuffer
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.5, 0.5, 0.5, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &projection[0][0])
        gl.Uniform2f(main_uf["u_quad_size"].location, QUAD_SIZE, QUAD_SIZE)
        gl.BindTexture(gl.TEXTURE_2D, main_tex)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        sdl.GL_SwapWindow(window)
    }
}
