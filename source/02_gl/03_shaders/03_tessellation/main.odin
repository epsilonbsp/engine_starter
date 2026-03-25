package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Tessellation"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

TESS_LEVEL :: f32(8)

MAIN_VS :: GLSL_VERSION + `
    out vec2 v_position;
    out vec2 v_tex_coord;
    out vec3 v_color;

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
        v_position = POSITIONS[gl_VertexID];
        v_tex_coord = TEX_COORDS[gl_VertexID];
        v_color = COLORS[gl_VertexID];
    }
`

MAIN_TCS :: GLSL_VERSION + `
    layout(vertices = 4) out;

    in vec2 v_position[];
    in vec2 v_tex_coord[];
    in vec3 v_color[];

    out vec2 tc_position[];
    out vec2 tc_tex_coord[];
    out vec3 tc_color[];

    uniform float u_tess_level;

    void main() {
        tc_position[gl_InvocationID] = v_position[gl_InvocationID];
        tc_tex_coord[gl_InvocationID] = v_tex_coord[gl_InvocationID];
        tc_color[gl_InvocationID] = v_color[gl_InvocationID];

        if (gl_InvocationID == 0) {
            gl_TessLevelInner[0] = u_tess_level;
            gl_TessLevelInner[1] = u_tess_level;
            gl_TessLevelOuter[0] = u_tess_level;
            gl_TessLevelOuter[1] = u_tess_level;
            gl_TessLevelOuter[2] = u_tess_level;
            gl_TessLevelOuter[3] = u_tess_level;
        }
    }
`

MAIN_TES :: GLSL_VERSION + `
    layout(quads, equal_spacing, ccw) in;

    in vec2 tc_position[];
    in vec2 tc_tex_coord[];
    in vec3 tc_color[];

    out vec2 v_tex_coord;
    out vec3 v_color;

    uniform mat4 u_projection;

    void main() {
        float u = gl_TessCoord.x;
        float v = gl_TessCoord.y;

        // Bilinear interpolation: 0=BL, 1=BR, 2=TL, 3=TR
        vec2 position = mix(mix(tc_position[0], tc_position[1], u), mix(tc_position[2], tc_position[3], u), v);
        v_tex_coord = mix(mix(tc_tex_coord[0], tc_tex_coord[1], u), mix(tc_tex_coord[2], tc_tex_coord[3], u), v);
        v_color = mix(mix(tc_color[0], tc_color[1], u), mix(tc_color[2], tc_color[3], u), v);

        gl_Position = u_projection * vec4(position, 0.0, 1.0);
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

load_shaders_source :: proc(vs_source, tcs_source, tes_source, fs_source: string, binary_retrievable := false) -> (program_id: u32, ok: bool) {
    vertex_shader_id := gl.compile_shader_from_source(vs_source, gl.Shader_Type.VERTEX_SHADER) or_return
    defer gl.DeleteShader(vertex_shader_id)

    tcs_shader_id := gl.compile_shader_from_source(tcs_source, gl.Shader_Type.TESS_CONTROL_SHADER) or_return
    defer gl.DeleteShader(tcs_shader_id)

    tes_shader_id := gl.compile_shader_from_source(tes_source, gl.Shader_Type.TESS_EVALUATION_SHADER) or_return
    defer gl.DeleteShader(tes_shader_id)

    fragment_shader_id := gl.compile_shader_from_source(fs_source, gl.Shader_Type.FRAGMENT_SHADER) or_return
    defer gl.DeleteShader(fragment_shader_id)

    return gl.create_and_link_program([]u32{vertex_shader_id, tcs_shader_id, tes_shader_id, fragment_shader_id}, binary_retrievable)
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

    main_pg, main_ok := load_shaders_source(MAIN_VS, MAIN_TCS, MAIN_TES, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf)
    assert(main_ok, "ERROR: Failed to compile program")

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

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

        gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &projection[0][0])
        gl.Uniform1f(main_uf["u_tess_level"].location, TESS_LEVEL)
        gl.PatchParameteri(gl.PATCH_VERTICES, 4)
        gl.DrawArrays(gl.PATCHES, 0, 4)
        gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)

        sdl.GL_SwapWindow(window)
    }
}
