package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Triangle Fan"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

Vertex :: struct {
    position: glm.vec2,
    color: glm.vec3,
}

CIRCLE_RADIUS :: f32(128)
CIRCLE_POINT_COUNT :: 12

MAIN_VS :: GLSL_VERSION + `
    layout(location = 0) in vec2 i_position;
    layout(location = 1) in vec3 i_color;

    out vec3 v_color;

    uniform mat4 u_projection;

    void main() {
        gl_Position = u_projection * vec4(i_position, 0.0, 1.0);
        v_color = i_color;
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_color;

    out vec4 o_frag_color;

    void main() {
        o_frag_color = vec4(v_color, 1.0);
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

    if !main_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    vertices: [CIRCLE_POINT_COUNT]Vertex
    vertex_count := len(vertices)

    for i in 0 ..< CIRCLE_POINT_COUNT {
        a := glm.PI * 2 / CIRCLE_POINT_COUNT * f32(i)
        x := glm.cos(a) * CIRCLE_RADIUS
        y := glm.sin(a) * CIRCLE_RADIUS

        vertices[i] = {{x, y}, {rand.float32(), rand.float32(), rand.float32()}}
    }

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, vertex_count * size_of(Vertex), &vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, color))

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
        gl.DrawArrays(gl.TRIANGLE_FAN, 0, i32(vertex_count))

        sdl.GL_SwapWindow(window)
    }
}
