package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Instancing"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

POINT_CAP :: 1024
POINT_POS_MIN :: f32(-512)
POINT_POS_MAX :: f32(512)
POINT_RADIUS_MIN :: f32(4)
POINT_RADIUS_MAX :: f32(16)

MAIN_VS :: GLSL_VERSION + `
    layout(location = 0) in vec2 i_position;
    layout(location = 1) in float i_radius;
    layout(location = 2) in int i_color;

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
        vec2 position = POSITIONS[gl_VertexID] * i_radius + i_position;

        gl_Position = u_projection * vec4(position, 0.0, 1.0);
        v_tex_coord = TEX_COORDS[gl_VertexID];
        v_color = unpack_color(i_color);
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

Point :: struct {
    position: glm.vec2,
    radius: f32,
    color: i32,
}

pack_color :: proc(color: glm.ivec3) -> i32 {
    return (color.x << 16) | (color.y << 8) | color.z;
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

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);
    assert(main_ok, "ERROR: Failed to compile program")

    points : [POINT_CAP]Point

    for &point in points {
        point.position = {rand.float32_range(POINT_POS_MIN, POINT_POS_MAX), rand.float32_range(POINT_POS_MIN, POINT_POS_MAX)}
        point.radius = rand.float32_range(POINT_RADIUS_MIN, POINT_RADIUS_MAX)
        point.color = random_color()
    }

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, POINT_CAP * size_of(Point), &points, gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Point), 0)
    gl.VertexAttribDivisor(0, 1)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 1, gl.FLOAT, gl.FALSE, size_of(Point), offset_of(Point, radius))
    gl.VertexAttribDivisor(1, 1)

    gl.EnableVertexAttribArray(2)
    gl.VertexAttribIPointer(2, 1, gl.INT, size_of(Point), offset_of(Point, color))
    gl.VertexAttribDivisor(2, 1)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

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
        gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, POINT_CAP)

        sdl.GL_SwapWindow(window)
    }
}
