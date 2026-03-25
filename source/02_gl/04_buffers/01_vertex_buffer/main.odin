package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Vertex Buffer"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

QUAD_SIZE :: glm.vec2{256, 256}
HALF_SIZE :: glm.vec2{QUAD_SIZE.x / 2, QUAD_SIZE.y / 2}

Vertex :: struct {
    position: glm.vec2,
    tex_coord: glm.vec2,
    color: glm.vec3,
}

// Bottom left origin
vertices: []Vertex = {
    {{-HALF_SIZE.x, -HALF_SIZE.y}, {0, 0}, {1, 0, 0}},
    {{ HALF_SIZE.x, -HALF_SIZE.y}, {1, 0}, {0, 1, 0}},
    {{-HALF_SIZE.x,  HALF_SIZE.y}, {0, 1}, {0, 0, 1}},
    {{ HALF_SIZE.x,  HALF_SIZE.y}, {1, 1}, {1, 1, 1}},
}

vertex_count := len(vertices)

MAIN_VS :: GLSL_VERSION + `
    layout(location = 0) in vec2 i_position;
    layout(location = 1) in vec2 i_tex_coord;
    layout(location = 2) in vec3 i_color;

    out vec2 v_tex_coord;
    out vec3 v_color;

    uniform mat4 u_projection;

    void main() {
        gl_Position = u_projection * vec4(i_position, 0.0, 1.0);
        v_tex_coord = i_tex_coord;
        v_color = i_color;
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;
    in vec3 v_color;

    out vec4 o_frag_color;

    void main() {
        vec2 checker = floor(v_tex_coord * 8.0);
        float pattern = mod(checker.x + checker.y, 2.0);
        vec3 color = v_color + vec3(pattern * 0.2);

        o_frag_color = vec4(color, 1.0);
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

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);
    assert(main_ok, "ERROR: Failed to compile program")

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, vertex_count * size_of(Vertex), &vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, tex_coord))

    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, color))

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
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, i32(vertex_count))

        sdl.GL_SwapWindow(window)
    }
}
