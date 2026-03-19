package example

import "core:fmt"
import "core:math"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Instancing Multiple Meshes"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

INSTANCE_CAP :: 1024
INSTANCE_CAP_HALF :: INSTANCE_CAP / 2
INSTANCE_POS_MIN :: f32(-512)
INSTANCE_POS_MAX :: f32(512)
INSTANCE_SCALE_MIN :: f32(4)
INSTANCE_SCALE_MAX :: f32(32)

Vertex :: struct {
    position: glm.vec2,
}

Instance :: struct {
    transform: glm.mat3x2,
    color: i32,
}

HEART_VERTEX_COUNT :: 13
STAR_VERTEX_COUNT :: 12

// Heart shape
heart_vertices := [HEART_VERTEX_COUNT]Vertex{
    {{ 0.0,  0.1 }},
    {{ 0.0, -1.0 }},
    {{-0.6, -0.4 }},
    {{-1.0,  0.2 }},
    {{-0.9,  0.6 }},
    {{-0.5,  0.9 }},
    {{ 0.0,  0.65}},
    {{ 0.5,  0.9 }},
    {{ 0.9,  0.6 }},
    {{ 1.0,  0.2 }},
    {{ 0.6, -0.4 }},
    {{ 0.0, -1.0 }},
    {{ 0.0, -1.0 }},
}

// Star shape
star_vertices := [STAR_VERTEX_COUNT]Vertex{
    {{ 0.0,    0.0  }},
    {{ 0.0,    1.0  }},
    {{-0.235,  0.324}},
    {{-0.951,  0.309}},
    {{-0.381, -0.124}},
    {{-0.588, -0.809}},
    {{ 0.0,   -0.4  }},
    {{ 0.588, -0.809}},
    {{ 0.381, -0.124}},
    {{ 0.951,  0.309}},
    {{ 0.235,  0.324}},
    {{ 0.0,    1.0  }},
}

MAIN_VS :: GLSL_VERSION + `
    layout(location = 0) in vec2 i_position;
    layout(location = 1) in mat3x2 i_transform;
    layout(location = 4) in int i_color;

    out vec3 v_color;

    uniform mat4 u_projection;

    vec3 unpack_color(int color) {
        return vec3(
            (color >> 16) & 0xFF,
            (color >> 8) & 0xFF,
            color & 0xFF
        ) / 255.0;
    }

    void main() {
        vec2 position = i_transform * vec3(i_position, 1.0);

        gl_Position = u_projection * vec4(position, 0.0, 1.0);
        v_color = unpack_color(i_color);
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_color;

    out vec4 o_frag_color;

    void main() {
        o_frag_color = vec4(v_color, 1.0);
    }
`

make_transform :: proc(translation: glm.vec2, rotation: f32, scale: glm.vec2) -> glm.mat3x2 {
    c := math.cos(rotation)
    s := math.sin(rotation)

    return glm.mat3x2{
        c * scale.x, -s * scale.y, translation.x,
        s * scale.x,  c * scale.y, translation.y
    }
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

    // Anti-aliasing
    sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
    sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 4)

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

    instances: [INSTANCE_CAP]Instance

    for &inst in instances {
        position := glm.vec2{rand.float32_range(INSTANCE_POS_MIN, INSTANCE_POS_MAX), rand.float32_range(INSTANCE_POS_MIN, INSTANCE_POS_MAX)}
        angle := rand.float32_range(0, math.TAU)
        size := rand.float32_range(INSTANCE_SCALE_MIN, INSTANCE_SCALE_MAX)

        inst.transform = make_transform(position, angle, {size, size})
        inst.color = random_color()
    }

    geo_vertices: [HEART_VERTEX_COUNT + STAR_VERTEX_COUNT]Vertex
    copy(geo_vertices[:HEART_VERTEX_COUNT], heart_vertices[:])
    copy(geo_vertices[HEART_VERTEX_COUNT:], star_vertices[:])

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    geo_vbo: u32; gl.GenBuffers(1, &geo_vbo); defer gl.DeleteBuffers(1, &geo_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, geo_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(geo_vertices), &geo_vertices, gl.STATIC_DRAW)

    geo_offset: uintptr
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), geo_offset)

    inst_vbo: u32; gl.GenBuffers(1, &inst_vbo); defer gl.DeleteBuffers(1, &inst_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, inst_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(instances), &instances, gl.STATIC_DRAW)

    inst_base_loc :: u32(1)
    mat3x2_cols :: 3
    color_loc :: inst_base_loc + mat3x2_cols

    inst_offset: uintptr

    for i in 0 ..< mat3x2_cols {
        loc := inst_base_loc + u32(i)

        gl.EnableVertexAttribArray(loc)
        gl.VertexAttribPointer(loc, 2, gl.FLOAT, gl.FALSE, size_of(Instance), inst_offset)
        gl.VertexAttribDivisor(loc, 1)

        inst_offset += size_of(glm.vec2)
    }

    gl.EnableVertexAttribArray(color_loc)
    gl.VertexAttribIPointer(color_loc, 1, gl.INT, size_of(Instance), inst_offset)
    gl.VertexAttribDivisor(color_loc, 1)

    gl.Enable(gl.MULTISAMPLE)

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

        // Hearts
        gl.DrawArraysInstancedBaseInstance(
            gl.TRIANGLE_FAN,    // Drawing mode
            0,                  // Mesh vertex offset
            HEART_VERTEX_COUNT, // Mesh vertex count
            INSTANCE_CAP_HALF,  // Instance count
            0                   // Base instance
        )

        // Stars
        gl.DrawArraysInstancedBaseInstance(
            gl.TRIANGLE_FAN,    // Drawing mode
            HEART_VERTEX_COUNT, // Mesh vertex offset
            STAR_VERTEX_COUNT,  // Mesh vertex count
            INSTANCE_CAP_HALF,  // Instance count
            INSTANCE_CAP_HALF   // Base instance
        )

        sdl.GL_SwapWindow(window)
    }
}
