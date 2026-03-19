package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Texture Generation GPU"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

TEXTURE_WIDTH :: 512
TEXTURE_HEIGHT :: 512
VORONOI_SEEDS :: 64

TEXTURE_VS :: GLSL_VERSION + `
    out vec2 v_tex_coord;

    // Bottom left origin
    const vec2 POSITIONS[] = vec2[](
        vec2(-1.0, -1.0),
        vec2( 1.0, -1.0),
        vec2(-1.0,  1.0),
        vec2( 1.0,  1.0)
    );

    const vec2 TEX_COORDS[] = vec2[](
        vec2(0.0, 0.0),
        vec2(1.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 1.0)
    );

    void main() {
        gl_Position = vec4(POSITIONS[gl_VertexID], 0.0, 1.0);
        v_tex_coord = TEX_COORDS[gl_VertexID];
    }
`

TEXTURE_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    const int VORONOI_SEEDS = 64;
    const float ANIM_RADIUS = 0.1;
    const float ANIM_SPEED = 0.3;

    uniform vec2 u_seed_positions[VORONOI_SEEDS];
    uniform vec3 u_seed_colors[VORONOI_SEEDS];
    uniform float u_time;

    void main() {
        float phase_offset = 0.0;
        vec2 position = u_seed_positions[0] + ANIM_RADIUS * vec2(sin(u_time * ANIM_SPEED + phase_offset), cos(u_time * ANIM_SPEED + phase_offset));
        float best_dist = distance(v_tex_coord, position);
        int nearest = 0;

        for (int i = 1; i < VORONOI_SEEDS; i++) {
            phase_offset = float(i);
            position = u_seed_positions[i] + ANIM_RADIUS * vec2(sin(u_time * ANIM_SPEED + phase_offset), cos(u_time * ANIM_SPEED + phase_offset));

            float d = distance(v_tex_coord, position);

            if (d < best_dist) {
                best_dist = d;
                nearest = i;
            }
        }

        o_frag_color = vec4(u_seed_colors[nearest], 1.0);
    }
`

MAIN_VS :: `#version 460 core
    out vec2 v_tex_coord;

    uniform mat4 u_projection;

    const vec2 QUAD_SIZE = vec2(512.0);
    const vec2 HALF_SIZE = QUAD_SIZE / 2.0;

    // Bottom left origin
    const vec2 POSITIONS[] = vec2[](
        vec2(-HALF_SIZE.x, -HALF_SIZE.y),
        vec2( HALF_SIZE.x, -HALF_SIZE.y),
        vec2(-HALF_SIZE.x,  HALF_SIZE.y),
        vec2( HALF_SIZE.x,  HALF_SIZE.y)
    );

    const vec2 TEX_COORDS[] = vec2[](
        vec2(0.0, 0.0),
        vec2(1.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 1.0)
    );

    void main() {
        gl_Position = u_projection * vec4(POSITIONS[gl_VertexID], 0.0, 1.0);
        v_tex_coord = TEX_COORDS[gl_VertexID];
    }
`

MAIN_FS :: `#version 460 core
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

    texture_pg, texture_ok := gl.load_shaders_source(TEXTURE_VS, TEXTURE_FS); defer gl.DeleteProgram(texture_pg)

    if !texture_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);

    if !main_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_tex: u32; gl.GenTextures(1, &main_tex); defer gl.DeleteTextures(1, &main_tex)
    gl.BindTexture(gl.TEXTURE_2D, main_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, TEXTURE_WIDTH, TEXTURE_HEIGHT, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    main_fbo: u32; gl.GenFramebuffers(1, &main_fbo); defer gl.DeleteFramebuffers(1, &main_fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, main_fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, main_tex, 0)
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    seed_positions: [VORONOI_SEEDS]glm.vec2
    seed_colors: [VORONOI_SEEDS]glm.vec3

    for i in 0 ..< VORONOI_SEEDS {
        seed_positions[i] = {rand.float32(), rand.float32()}
        seed_colors[i] = {rand.float32(), rand.float32(), rand.float32()}
    }

    seed_pos_loc := gl.GetUniformLocation(texture_pg, "u_seed_positions")
    seed_col_loc := gl.GetUniformLocation(texture_pg, "u_seed_colors")
    seed_time_loc := gl.GetUniformLocation(texture_pg, "u_time")

    gl.UseProgram(texture_pg)
    gl.Uniform2fv(seed_pos_loc, VORONOI_SEEDS, &seed_positions[0][0])
    gl.Uniform3fv(seed_col_loc, VORONOI_SEEDS, &seed_colors[0][0])

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
        gl.BindFramebuffer(gl.FRAMEBUFFER, main_fbo)
        gl.Viewport(0, 0, TEXTURE_WIDTH, TEXTURE_HEIGHT)
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(texture_pg)
        gl.Uniform1f(seed_time_loc, time_seconds)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        // Output to main window framebuffer
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &projection[0][0])
        gl.BindTexture(gl.TEXTURE_2D, main_tex)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        sdl.GL_SwapWindow(window)
    }
}
