package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Uniform Buffer"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

MAIN_VS :: GLSL_VERSION + `
    out vec2 v_tex_coord;
    out vec3 v_color;

    layout(std140, binding = 0) uniform Camera {
        mat4 u_projection;
        mat4 u_view;
    };

    const vec2 QUAD_SIZE = vec2(256.0);
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

    const vec3 COLORS[] = vec3[](
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, 1.0, 0.0),
        vec3(0.0, 0.0, 1.0),
        vec3(1.0, 1.0, 1.0)
    );

    void main() {
        gl_Position = u_projection * u_view * vec4(POSITIONS[gl_VertexID], 0.0, 1.0);
        v_tex_coord = TEX_COORDS[gl_VertexID];
        v_color = COLORS[gl_VertexID];
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

Camera :: struct {
    projection: glm.mat4,
    view: glm.mat4,
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

    if !main_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    camera_ubo: u32; gl.GenBuffers(1, &camera_ubo); defer gl.DeleteBuffers(1, &camera_ubo)
    gl.BindBuffer(gl.UNIFORM_BUFFER, camera_ubo)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(Camera), nil, gl.DYNAMIC_DRAW)
    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, camera_ubo)

    loop: for {
        time := f32(sdl.GetTicks()) / 1000.0

        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
            }
        }

        camera: Camera
        camera.projection = glm.mat4Ortho3d(-f32(viewport_x) / 2, f32(viewport_x) / 2, -f32(viewport_y) / 2, f32(viewport_y) / 2, -1, 1)
        camera.view = glm.mat4Translate({glm.sin(time) * 128, 0, 0})

        gl.NamedBufferSubData(camera_ubo, 0, size_of(Camera), &camera)

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.5, 0.5, 0.5, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(main_pg)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        sdl.GL_SwapWindow(window)
    }
}