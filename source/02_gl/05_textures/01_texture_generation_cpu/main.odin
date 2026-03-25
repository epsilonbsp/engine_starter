package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Texture Generation CPU"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

TEXTURE_WIDTH :: 512
TEXTURE_HEIGHT :: 512
VORONOI_SEEDS :: 64

MAIN_VS :: GLSL_VERSION + `
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

MAIN_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_texture;

    void main() {
        o_frag_color = texture(u_texture, v_tex_coord);
    }
`

Seed :: struct {
    position: glm.vec2,
    color: [3]u8,
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

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);
    assert(main_ok, "ERROR: Failed to compile program")

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    // Setup voronoi seeds
    seeds: [VORONOI_SEEDS]Seed

    for &seed in seeds {
        seed.position = {rand.float32_range(0, TEXTURE_WIDTH), rand.float32_range(0, TEXTURE_HEIGHT)}
        seed.color = {u8(rand.int31() % 256), u8(rand.int31() % 256), u8(rand.int31() % 256)}
    }

    // Generate image
    pixels := make([]u8, TEXTURE_WIDTH * TEXTURE_HEIGHT * 4); defer delete(pixels)

    for y in 0 ..< TEXTURE_HEIGHT {
        for x in 0 ..< TEXTURE_WIDTH {
            p := glm.vec2{f32(x), f32(y)}
            nearest := 0
            best_dist := glm.length(p - seeds[0].position)

            for i in 1 ..< VORONOI_SEEDS {
                d := glm.length(p - seeds[i].position)

                if d < best_dist {
                    best_dist = d
                    nearest = i
                }
            }

            idx := (y * TEXTURE_WIDTH + x) * 4
            pixels[idx + 0] = seeds[nearest].color[0]
            pixels[idx + 1] = seeds[nearest].color[1]
            pixels[idx + 2] = seeds[nearest].color[2]
            pixels[idx + 3] = 255
        }
    }

    main_tex: u32; gl.GenTextures(1, &main_tex); defer gl.DeleteTextures(1, &main_tex)
    gl.BindTexture(gl.TEXTURE_2D, main_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(TEXTURE_WIDTH), i32(TEXTURE_HEIGHT), 0, gl.RGBA, gl.UNSIGNED_BYTE, &pixels[0])
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    loop: for {
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

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.5, 0.5, 0.5, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &projection[0][0])
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        sdl.GL_SwapWindow(window)
    }
}
