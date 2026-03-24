package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Light Volumes"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

MAX_LIGHTS :: 256

GRID_SIZE    :: 16
GRID_SPACING :: 16.0
CUBE_SIZE    :: 4.0   // horizontal (XZ) footprint of each cube
HEIGHT_MIN   :: 2.0   // shortest possible cube
HEIGHT_MAX   :: 14.0  // tallest possible cube

lights: [MAX_LIGHTS]Light


cube_vertices := []Vertex {
    // Left
    {{-0.5, -0.5, -0.5}, {-1, 0, 0}},
    {{-0.5, -0.5,  0.5}, {-1, 0, 0}},
    {{-0.5,  0.5,  0.5}, {-1, 0, 0}},
    {{-0.5,  0.5, -0.5}, {-1, 0, 0}},

    // Right
    {{ 0.5, -0.5,  0.5}, {1, 0, 0}},
    {{ 0.5, -0.5, -0.5}, {1, 0, 0}},
    {{ 0.5,  0.5, -0.5}, {1, 0, 0}},
    {{ 0.5,  0.5,  0.5}, {1, 0, 0}},

    // Bottom
    {{-0.5, -0.5, -0.5}, {0, -1, 0}},
    {{ 0.5, -0.5, -0.5}, {0, -1, 0}},
    {{ 0.5, -0.5,  0.5}, {0, -1, 0}},
    {{-0.5, -0.5,  0.5}, {0, -1, 0}},

    // Top
    {{-0.5,  0.5,  0.5}, {0, 1, 0}},
    {{ 0.5,  0.5,  0.5}, {0, 1, 0}},
    {{ 0.5,  0.5, -0.5}, {0, 1, 0}},
    {{-0.5,  0.5, -0.5}, {0, 1, 0}},

    // Back
    {{ 0.5, -0.5, -0.5}, {0, 0, -1}},
    {{-0.5, -0.5, -0.5}, {0, 0, -1}},
    {{-0.5,  0.5, -0.5}, {0, 0, -1}},
    {{ 0.5,  0.5, -0.5}, {0, 0, -1}},

    // Front
    {{-0.5, -0.5,  0.5}, {0, 0, 1}},
    {{ 0.5, -0.5,  0.5}, {0, 0, 1}},
    {{ 0.5,  0.5,  0.5}, {0, 0, 1}},
    {{-0.5,  0.5,  0.5}, {0, 0, 1}},
}

cube_indices := []u32 {
    // Left
    0, 1, 2, 0, 2, 3,

    // Right
    4, 5, 6, 4, 6, 7,

    // Bottom
    8, 9, 10, 8, 10, 11,

    // Top
    12, 13, 14, 12, 14, 15,

    // Back
    16, 17, 18, 16, 18, 19,

    // Front
    20, 21, 22, 20, 22, 23,
}

cube_index_count := len(cube_indices)

GBUFFER_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;

    // Per-instance: model matrix split into 4 columns, plus material data
    layout(location = 2) in vec4 i_model_c0;
    layout(location = 3) in vec4 i_model_c1;
    layout(location = 4) in vec4 i_model_c2;
    layout(location = 5) in vec4 i_model_c3;
    layout(location = 6) in vec3 i_mat_color;
    layout(location = 7) in vec4 i_mat_props;

    out vec3 v_normal;
    out vec3 v_world_pos;
    out vec3 v_mat_color;
    out vec4 v_mat_props;

    uniform mat4 u_projection;
    uniform mat4 u_view;

    void main() {
        mat4 model = mat4(i_model_c0, i_model_c1, i_model_c2, i_model_c3);
        vec4 world_pos = model * vec4(i_position, 1.0);

        gl_Position = u_projection * u_view * world_pos;
        v_normal = transpose(inverse(mat3(model))) * i_normal;
        v_world_pos = world_pos.xyz;
        v_mat_color = i_mat_color;
        v_mat_props = i_mat_props;
    }
`

GBUFFER_FS :: GLSL_VERSION + `
    in vec3 v_normal;
    in vec3 v_world_pos;
    in vec3 v_mat_color;
    in vec4 v_mat_props;

    layout(location = 0) out vec3 o_position;
    layout(location = 1) out vec3 o_normal;
    layout(location = 2) out vec3 o_albedo;
    layout(location = 3) out vec4 o_material;

    void main() {
        o_position = v_world_pos;
        o_normal = normalize(v_normal);
        o_albedo = v_mat_color;
        o_material = v_mat_props;
    }
`

// Fullscreen quad — used for the ambient pass
AMBIENT_VS :: GLSL_VERSION + `
    const vec2 POSITIONS[4] = vec2[](
        vec2(-1, -1),
        vec2( 1, -1),
        vec2(-1,  1),
        vec2( 1,  1)
    );

    const vec2 TEXCOORDS[4] = vec2[](
        vec2(0, 0),
        vec2(1, 0),
        vec2(0, 1),
        vec2(1, 1)
    );

    out vec2 v_tex_coord;

    void main() {
        gl_Position = vec4(POSITIONS[gl_VertexID], 0.0, 1.0);
        v_tex_coord = TEXCOORDS[gl_VertexID];
    }
`

// Outputs albedo * ambient_strength — drawn once as a base before light volumes are added
AMBIENT_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_g_albedo;
    uniform sampler2D u_g_material;

    void main() {
        vec3 albedo = texture(u_g_albedo, v_tex_coord).rgb;
        float ambient_strength = texture(u_g_material, v_tex_coord).r;

        o_frag_color = vec4(albedo * ambient_strength, 1.0);
    }
`

// Sphere mesh — one draw call per light volume
LIGHTING_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;

    void main() {
        gl_Position = u_projection * u_view * u_model * vec4(i_position, 1.0);
    }
`

// Samples the gbuffer at the current screen pixel and computes lighting for one light.
// Drawn with additive blending so contributions from all light volumes accumulate.
LIGHTING_FS :: GLSL_VERSION + `
    out vec4 o_frag_color;

    uniform sampler2D u_g_position;
    uniform sampler2D u_g_normal;
    uniform sampler2D u_g_albedo;
    uniform sampler2D u_g_material;
    uniform vec2 u_viewport_size;
    uniform vec3 u_view_pos;
    uniform vec3 u_light_pos;
    uniform vec3 u_light_color;
    uniform float u_light_constant;
    uniform float u_light_linear;
    uniform float u_light_quadratic;

    void main() {
        vec2 tex_coord = gl_FragCoord.xy / u_viewport_size;

        vec3 world_pos = texture(u_g_position, tex_coord).rgb;
        vec3 normal = texture(u_g_normal, tex_coord).rgb;
        vec3 albedo = texture(u_g_albedo, tex_coord).rgb;
        vec4 material = texture(u_g_material, tex_coord);

        float diffuse_strength = material.g;
        float specular_strength = material.b;
        float specular_shine = material.a;

        vec3 view_dir = normalize(u_view_pos - world_pos);
        vec3 light_dir = normalize(u_light_pos - world_pos);
        vec3 half_dir = normalize(light_dir + view_dir);

        float dist = length(u_light_pos - world_pos);
        float attenuation = 1.0 / (u_light_constant + u_light_linear * dist + u_light_quadratic * dist * dist);

        vec3 diffuse = albedo * u_light_color * max(dot(normal, light_dir), 0.0) * diffuse_strength;
        vec3 specular = u_light_color * pow(max(dot(normal, half_dir), 0.0), specular_shine) * specular_strength;

        o_frag_color = vec4((diffuse + specular) * attenuation, 1.0);
    }
`

LIGHT_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;

    // Per-instance
    layout(location = 1) in vec4 i_model_c0;
    layout(location = 2) in vec4 i_model_c1;
    layout(location = 3) in vec4 i_model_c2;
    layout(location = 4) in vec4 i_model_c3;
    layout(location = 5) in vec3 i_color;

    out vec3 v_color;

    uniform mat4 u_projection;
    uniform mat4 u_view;

    void main() {
        mat4 model = mat4(i_model_c0, i_model_c1, i_model_c2, i_model_c3);

        gl_Position = u_projection * u_view * model * vec4(i_position, 1.0);
        v_color = i_color;
    }
`

LIGHT_FS :: GLSL_VERSION + `
    in vec3 v_color;

    out vec4 o_frag_color;

    void main() {
        o_frag_color = vec4(v_color, 1.0);
    }
`

SKYBOX_VS :: GLSL_VERSION + `
    out vec3 v_tex_coord;

    uniform mat4 u_projection;
    uniform mat4 u_view;

    const vec3 POSITIONS[14] = vec3[](
        // Back (-Z)
        vec3(-1, 1,-1), vec3( 1, 1,-1), vec3(-1,-1,-1), vec3( 1,-1,-1),

        // Right (+X)
        vec3( 1,-1, 1), vec3( 1, 1,-1), vec3( 1, 1, 1),

        // Top (+Y)
        vec3(-1, 1,-1), vec3(-1, 1, 1),

        // Left (-X)
        vec3(-1,-1,-1), vec3(-1,-1, 1),

        // Bottom (-Y) + front (+Z)
        vec3( 1,-1, 1), vec3(-1, 1, 1), vec3( 1, 1, 1)
    );

    void main() {
        vec3 position = POSITIONS[gl_VertexID];
        vec4 clip = u_projection * u_view * vec4(position, 1.0);

        gl_Position = clip.xyww;
        v_tex_coord = position;
    }
`

SKYBOX_FS :: GLSL_VERSION + `
    in vec3 v_tex_coord;

    out vec4 o_frag_color;

    const vec3 COLOR_TOP = vec3(0.0, 0.0, 0.02);
    const vec3 COLOR_HORIZON = vec3(0.03, 0.02, 0.06);
    const vec3 COLOR_BOTTOM = vec3(0.01, 0.0, 0.02);

    void main() {
        vec3 dir = normalize(v_tex_coord);

        vec3 color = dir.y >= 0.0
            ? mix(COLOR_HORIZON, COLOR_TOP, dir.y)
            : mix(COLOR_HORIZON, COLOR_BOTTOM, -dir.y);

        o_frag_color = vec4(pow(color, vec3(1.0 / 2.2)), 1.0);
    }
`

Light :: struct {
    position: glm.vec3,
    color: glm.vec3,
    constant: f32,
    linear: f32,
    quadratic: f32,
}

Material :: struct {
    color: glm.vec3,
    ambient_strength: f32,
    diffuse_strength: f32,
    specular_strength: f32,
    specular_shine: f32,
}

Cube :: struct {
    position: glm.vec3,
    scale: glm.vec3,
    material: Material,
}

Vertex :: struct {
    position: glm.vec3,
    normal: glm.vec3,
}

// Per-instance data for the geometry pass. model is split into columns for VertexAttribPointer.
// mat_props packs (ambient, diffuse, specular, shine) into one vec4.
Cube_Instance :: struct {
    model:    glm.mat4,
    color:    glm.vec3,
    _pad:     f32,
    mat_props: glm.vec4,
}

// Per-instance data for the emissive light cube forward pass.
Light_Instance :: struct {
    model: glm.mat4,
    color: glm.vec3,
    _pad:  f32,
}

GBuffer :: struct {
    fbo: u32,
    position_tex: u32,
    normal_tex: u32,
    albedo_tex: u32,
    material_tex: u32,
    depth_rbo: u32,
}

// Computes the sphere radius at which the light contribution drops below 5/256.
light_radius :: proc(l: Light) -> f32 {
    max_brightness := max(l.color.r, max(l.color.g, l.color.b))
    disc := l.linear * l.linear - 4.0 * l.quadratic * (l.constant - (256.0 / 5.0) * max_brightness)

    return (-l.linear + glm.sqrt(disc)) / (2.0 * l.quadratic)
}

gen_sphere :: proc(rings, segments: int) -> (verts: []glm.vec3, inds: []u32) {
    vert_count := (rings + 1) * (segments + 1)
    verts = make([]glm.vec3, vert_count)

    for r in 0 ..= rings {
        phi := glm.PI * f32(r) / f32(rings)

        for s in 0 ..= segments {
            theta := 2.0 * glm.PI * f32(s) / f32(segments)
            i := r * (segments + 1) + s
            verts[i] = {
                glm.sin(phi) * glm.cos(theta),
                glm.cos(phi),
                glm.sin(phi) * glm.sin(theta),
            }
        }
    }

    ind_count := rings * segments * 6
    inds = make([]u32, ind_count)
    idx := 0

    for r in 0 ..< rings {
        for s in 0 ..< segments {
            a := u32(r * (segments + 1) + s)
            b := u32(r * (segments + 1) + s + 1)
            c := u32((r + 1) * (segments + 1) + s)
            d := u32((r + 1) * (segments + 1) + s + 1)

            inds[idx + 0] = a
            inds[idx + 1] = b
            inds[idx + 2] = c
            inds[idx + 3] = b
            inds[idx + 4] = d
            inds[idx + 5] = c
            idx += 6
        }
    }

    return
}

gen_grid :: proc(size: int, spacing: f32) -> []Cube {
    cubes := make([]Cube, size * size)
    half := f32(size - 1) * spacing * 0.5
    shines := [4]f32{8.0, 32.0, 64.0, 256.0}

    for row in 0 ..< size {
        for col in 0 ..< size {
            i := row * size + col
            t := f32(i)

            height := HEIGHT_MIN + (HEIGHT_MAX - HEIGHT_MIN) * glm.abs(glm.sin(t * 0.9 + f32(row) * 1.3))

            cubes[i] = Cube{
                position = {f32(col) * spacing - half, height * 0.5, f32(row) * spacing - half},
                scale    = {CUBE_SIZE, height, CUBE_SIZE},
                material = Material{
                    color = {
                        0.5 + 0.5 * glm.sin(t * 0.7),
                        0.5 + 0.5 * glm.sin(t * 1.1 + 1.0),
                        0.5 + 0.5 * glm.sin(t * 1.3 + 2.0),
                    },
                    ambient_strength  = 0.02,
                    diffuse_strength  = 0.7 + 0.3 * glm.abs(glm.sin(t * 2.3)),
                    specular_strength = 0.5 + 0.5 * glm.abs(glm.sin(t * 1.7)),
                    specular_shine    = shines[i % 4],
                },
            }
        }
    }

    return cubes
}

make_transform :: proc(translation: glm.vec3, rotation: glm.vec3, scale: glm.vec3) -> glm.mat4 {
    qx := glm.quatAxisAngle({1, 0, 0}, rotation.x)
    qy := glm.quatAxisAngle({0, 1, 0}, rotation.y)
    qz := glm.quatAxisAngle({0, 0, 1}, rotation.z)
    q := qz * qy * qx

    return glm.mat4Translate(translation) * glm.mat4FromQuat(q) * glm.mat4Scale(scale)
}

init_gbuffer :: proc(gbuffer: ^GBuffer, width, height: i32) {
    gl.GenFramebuffers(1, &gbuffer.fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo)

    gl.GenTextures(1, &gbuffer.position_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.position_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB32F, width, height, 0, gl.RGB, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, gbuffer.position_tex, 0)

    gl.GenTextures(1, &gbuffer.normal_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.normal_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, width, height, 0, gl.RGB, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, gbuffer.normal_tex, 0)

    gl.GenTextures(1, &gbuffer.albedo_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.albedo_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB8, width, height, 0, gl.RGB, gl.UNSIGNED_BYTE, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT2, gl.TEXTURE_2D, gbuffer.albedo_tex, 0)

    gl.GenTextures(1, &gbuffer.material_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.material_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, width, height, 0, gl.RGBA, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT3, gl.TEXTURE_2D, gbuffer.material_tex, 0)

    attachments := [4]u32{gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1, gl.COLOR_ATTACHMENT2, gl.COLOR_ATTACHMENT3}
    gl.DrawBuffers(4, &attachments[0])

    gl.GenRenderbuffers(1, &gbuffer.depth_rbo)
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.depth_rbo)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT, width, height)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, gbuffer.depth_rbo)

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

destroy_gbuffer :: proc(gbuffer: ^GBuffer) {
    gl.DeleteTextures(1, &gbuffer.position_tex)
    gl.DeleteTextures(1, &gbuffer.normal_tex)
    gl.DeleteTextures(1, &gbuffer.albedo_tex)
    gl.DeleteTextures(1, &gbuffer.material_tex)
    gl.DeleteRenderbuffers(1, &gbuffer.depth_rbo)
    gl.DeleteFramebuffers(1, &gbuffer.fbo)
}

resize_gbuffer :: proc(gbuffer: ^GBuffer, width, height: i32) {
    destroy_gbuffer(gbuffer)
    init_gbuffer(gbuffer, width, height)
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
    _ = sdl.SetWindowRelativeMouseMode(window, true)

    viewport_x, viewport_y: i32; sdl.GetWindowSize(window, &viewport_x, &viewport_y)
    key_state := sdl.GetKeyboardState(nil)
    time: u64 = sdl.GetTicks()
    time_delta: f32
    time_last := time

    gbuffer_pg, gbuffer_ok := gl.load_shaders_source(GBUFFER_VS, GBUFFER_FS); defer gl.DeleteProgram(gbuffer_pg)
    gbuffer_uf := gl.get_uniforms_from_program(gbuffer_pg); defer gl.destroy_uniforms(gbuffer_uf)

    if !gbuffer_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    ambient_pg, ambient_ok := gl.load_shaders_source(AMBIENT_VS, AMBIENT_FS); defer gl.DeleteProgram(ambient_pg)
    ambient_uf := gl.get_uniforms_from_program(ambient_pg); defer gl.destroy_uniforms(ambient_uf)

    if !ambient_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    lighting_pg, lighting_ok := gl.load_shaders_source(LIGHTING_VS, LIGHTING_FS); defer gl.DeleteProgram(lighting_pg)
    lighting_uf := gl.get_uniforms_from_program(lighting_pg); defer gl.destroy_uniforms(lighting_uf)

    if !lighting_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    light_pg, light_ok := gl.load_shaders_source(LIGHT_VS, LIGHT_FS); defer gl.DeleteProgram(light_pg)
    light_uf := gl.get_uniforms_from_program(light_pg); defer gl.destroy_uniforms(light_uf)

    if !light_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    skybox_pg, skybox_ok := gl.load_shaders_source(SKYBOX_VS, SKYBOX_FS); defer gl.DeleteProgram(skybox_pg)
    skybox_uf := gl.get_uniforms_from_program(skybox_pg); defer gl.destroy_uniforms(skybox_uf)

    if !skybox_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    // Shared cube mesh buffers
    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(cube_vertices) * size_of(cube_vertices[0]), &cube_vertices[0], gl.STATIC_DRAW)

    main_ibo: u32; gl.GenBuffers(1, &main_ibo); defer gl.DeleteBuffers(1, &main_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, cube_index_count * size_of(cube_indices[0]), &cube_indices[0], gl.STATIC_DRAW)

    cubes := gen_grid(GRID_SIZE, GRID_SPACING)
    defer delete(cubes)

    cube_instances := make([]Cube_Instance, len(cubes))
    defer delete(cube_instances)

    for cube, i in cubes {
        model := make_transform(cube.position, {}, cube.scale)

        cube_instances[i] = Cube_Instance{
            model     = model,
            color     = cube.material.color,
            mat_props = {cube.material.ambient_strength, cube.material.diffuse_strength, cube.material.specular_strength, cube.material.specular_shine},
        }
    }

    cube_instance_vbo: u32; gl.GenBuffers(1, &cube_instance_vbo); defer gl.DeleteBuffers(1, &cube_instance_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, cube_instance_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(cube_instances) * size_of(Cube_Instance), &cube_instances[0], gl.STATIC_DRAW)

    // Geometry pass VAO: cube mesh + per-instance material/transform
    cube_vao: u32; gl.GenVertexArrays(1, &cube_vao); defer gl.DeleteVertexArrays(1, &cube_vao)
    gl.BindVertexArray(cube_vao)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), uintptr(0))
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), uintptr(offset_of(Vertex, normal)))
    gl.BindBuffer(gl.ARRAY_BUFFER, cube_instance_vbo)

    for col in 0 ..< 4 {
        loc := u32(2 + col)
        gl.EnableVertexAttribArray(loc)
        gl.VertexAttribPointer(loc, 4, gl.FLOAT, gl.FALSE, size_of(Cube_Instance), uintptr(col * size_of(glm.vec4)))
        gl.VertexAttribDivisor(loc, 1)
    }

    gl.EnableVertexAttribArray(6)
    gl.VertexAttribPointer(6, 3, gl.FLOAT, gl.FALSE, size_of(Cube_Instance), uintptr(offset_of(Cube_Instance, color)))
    gl.VertexAttribDivisor(6, 1)
    gl.EnableVertexAttribArray(7)
    gl.VertexAttribPointer(7, 4, gl.FLOAT, gl.FALSE, size_of(Cube_Instance), uintptr(offset_of(Cube_Instance, mat_props)))
    gl.VertexAttribDivisor(7, 1)

    // Forward pass VAO: cube mesh + per-instance light transform/color
    light_instance_vbo: u32; gl.GenBuffers(1, &light_instance_vbo); defer gl.DeleteBuffers(1, &light_instance_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, light_instance_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, MAX_LIGHTS * size_of(Light_Instance), nil, gl.STREAM_DRAW)

    light_cube_vao: u32; gl.GenVertexArrays(1, &light_cube_vao); defer gl.DeleteVertexArrays(1, &light_cube_vao)
    gl.BindVertexArray(light_cube_vao)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), uintptr(0))
    gl.BindBuffer(gl.ARRAY_BUFFER, light_instance_vbo)

    for col in 0 ..< 4 {
        loc := u32(1 + col)
        gl.EnableVertexAttribArray(loc)
        gl.VertexAttribPointer(loc, 4, gl.FLOAT, gl.FALSE, size_of(Light_Instance), uintptr(col * size_of(glm.vec4)))
        gl.VertexAttribDivisor(loc, 1)
    }

    gl.EnableVertexAttribArray(5)
    gl.VertexAttribPointer(5, 3, gl.FLOAT, gl.FALSE, size_of(Light_Instance), uintptr(offset_of(Light_Instance, color)))
    gl.VertexAttribDivisor(5, 1)

    sphere_verts, sphere_inds := gen_sphere(8, 12)
    sphere_index_count := len(sphere_inds)

    sphere_vao: u32; gl.GenVertexArrays(1, &sphere_vao); defer gl.DeleteVertexArrays(1, &sphere_vao)
    gl.BindVertexArray(sphere_vao)

    sphere_vbo: u32; gl.GenBuffers(1, &sphere_vbo); defer gl.DeleteBuffers(1, &sphere_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, sphere_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(sphere_verts) * size_of(sphere_verts[0]), &sphere_verts[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(glm.vec3), 0)

    sphere_ibo: u32; gl.GenBuffers(1, &sphere_ibo); defer gl.DeleteBuffers(1, &sphere_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, sphere_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(sphere_inds) * size_of(sphere_inds[0]), &sphere_inds[0], gl.STATIC_DRAW)

    delete(sphere_verts)
    delete(sphere_inds)

    quad_vao: u32; gl.GenVertexArrays(1, &quad_vao); defer gl.DeleteVertexArrays(1, &quad_vao)

    skybox_vao: u32; gl.GenVertexArrays(1, &skybox_vao); defer gl.DeleteVertexArrays(1, &skybox_vao)
    gl.BindVertexArray(skybox_vao)

    gbuffer: GBuffer
    init_gbuffer(&gbuffer, viewport_x, viewport_y)
    defer destroy_gbuffer(&gbuffer)

    light_instances: [MAX_LIGHTS]Light_Instance

    // Evenly-spaced hues across all lights using cosine colour wheel
    for i in 0 ..< MAX_LIGHTS {
        t := f32(i) * glm.PI * 2.0 / f32(MAX_LIGHTS)

        lights[i] = Light{
            color     = {
                0.5 + 0.5 * glm.cos(t),
                0.5 + 0.5 * glm.cos(t + glm.PI * 2.0 / 3.0),
                0.5 + 0.5 * glm.cos(t + glm.PI * 4.0 / 3.0),
            },
            constant  = 1.0,
            linear    = 0.09,
            quadratic = 0.032,
        }
    }

    camera: Camera; init_camera(&camera, position = {2, 2, 2})
    point_camera_at(&camera, {})

    camera_movement := Camera_Movement{move_speed = 20, yaw_speed = 0.002, pitch_speed = 0.002}

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    loop: for {
        time = sdl.GetTicks()
        time_delta = f32(time - time_last) / 1000
        time_last = time
        seconds := f32(time) / 1000

        // Split lights evenly: half patrol along Z (one per column lane),
        // half patrol along X (one per row lane). Lanes are evenly spaced
        // across the full grid width regardless of how many lights there are.
        grid_half  := f32(GRID_SIZE - 1) * GRID_SPACING * 0.5
        col_lights := MAX_LIGHTS / 2
        row_lights := MAX_LIGHTS - col_lights

        for i in 0 ..< col_lights {
            t     := f32(i) / f32(col_lights)
            col_x := t * f32(GRID_SIZE) * GRID_SPACING - grid_half + GRID_SPACING * 0.5
            phase := t * glm.PI * 2.0
            lights[i].position = {col_x, 3, glm.sin(seconds * 0.6 + phase) * grid_half}
        }

        for i in 0 ..< row_lights {
            t     := f32(i) / f32(row_lights)
            row_z := t * f32(GRID_SIZE) * GRID_SPACING - grid_half + GRID_SPACING * 0.5
            phase := t * glm.PI * 2.0
            lights[col_lights + i].position = {glm.sin(seconds * 0.4 + phase) * grid_half, 3, row_z}
        }

        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
                resize_gbuffer(&gbuffer, viewport_x, viewport_y)
            case .KEY_DOWN:
                if event.key.scancode == sdl.Scancode.ESCAPE {
                    _ = sdl.SetWindowRelativeMouseMode(window, !sdl.GetWindowRelativeMouseMode(window))
                }
            case .MOUSE_MOTION:
                if sdl.GetWindowRelativeMouseMode(window) {
                    rotate_camera(&camera, event.motion.xrel * camera_movement.yaw_speed, event.motion.yrel * camera_movement.pitch_speed, 0)
                }
            }
        }

        if (sdl.GetWindowRelativeMouseMode(window)) {
            input_fly_camera(
                &camera,
                {key_state[sdl.Scancode.A], key_state[sdl.Scancode.D], key_state[sdl.Scancode.S], key_state[sdl.Scancode.W]},
                time_delta * camera_movement.move_speed
            )
        }

        compute_camera_projection(&camera, f32(viewport_x) / f32(viewport_y))
        compute_camera_view(&camera)

        // Geometry pass — render scene into gbuffer
        gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo)
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(gbuffer_pg)
        gl.UniformMatrix4fv(gbuffer_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(gbuffer_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.BindVertexArray(cube_vao)
        gl.DrawElementsInstanced(gl.TRIANGLES, i32(cube_index_count), gl.UNSIGNED_INT, nil, i32(len(cubes)))

        // Blit depth from gbuffer so light volumes and forward passes depth-test correctly
        gl.BindFramebuffer(gl.READ_FRAMEBUFFER, gbuffer.fbo)
        gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
        gl.BlitFramebuffer(0, 0, viewport_x, viewport_y, 0, 0, viewport_x, viewport_y, gl.DEPTH_BUFFER_BIT, gl.NEAREST)
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

        // Ambient pass — fullscreen quad, writes albedo * ambient as the base color
        gl.Disable(gl.DEPTH_TEST)

        gl.UseProgram(ambient_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.albedo_tex)
        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.material_tex)
        gl.Uniform1i(ambient_uf["u_g_albedo"].location, 0)
        gl.Uniform1i(ambient_uf["u_g_material"].location, 1)
        gl.BindVertexArray(quad_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        // Light volume pass — one sphere per light, additively blended.
        // Depth test is disabled: the sphere's 2D projection limits which pixels are shaded,
        // and attenuation in the fragment shader handles the 3D falloff.
        gl.Enable(gl.BLEND)
        gl.BlendEquation(gl.FUNC_ADD)
        gl.BlendFunc(gl.ONE, gl.ONE)
        gl.CullFace(gl.FRONT)
        gl.Disable(gl.DEPTH_TEST)

        gl.UseProgram(lighting_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.position_tex)
        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.normal_tex)
        gl.ActiveTexture(gl.TEXTURE2)
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.albedo_tex)
        gl.ActiveTexture(gl.TEXTURE3)
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.material_tex)
        gl.Uniform1i(lighting_uf["u_g_position"].location, 0)
        gl.Uniform1i(lighting_uf["u_g_normal"].location, 1)
        gl.Uniform1i(lighting_uf["u_g_albedo"].location, 2)
        gl.Uniform1i(lighting_uf["u_g_material"].location, 3)
        gl.Uniform2f(lighting_uf["u_viewport_size"].location, f32(viewport_x), f32(viewport_y))
        gl.Uniform3fv(lighting_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.UniformMatrix4fv(lighting_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(lighting_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.BindVertexArray(sphere_vao)

        for i in 0 ..< MAX_LIGHTS {
            radius := light_radius(lights[i])
            light_model := make_transform(lights[i].position, {}, {radius, radius, radius})

            gl.UniformMatrix4fv(lighting_uf["u_model"].location, 1, false, &light_model[0][0])
            gl.Uniform3fv(lighting_uf["u_light_pos"].location, 1, &lights[i].position[0])
            gl.Uniform3fv(lighting_uf["u_light_color"].location, 1, &lights[i].color[0])
            gl.Uniform1f(lighting_uf["u_light_constant"].location, lights[i].constant)
            gl.Uniform1f(lighting_uf["u_light_linear"].location, lights[i].linear)
            gl.Uniform1f(lighting_uf["u_light_quadratic"].location, lights[i].quadratic)
            gl.DrawElements(gl.TRIANGLES, i32(sphere_index_count), gl.UNSIGNED_INT, nil)
        }

        gl.Disable(gl.BLEND)
        gl.CullFace(gl.BACK)
        gl.Enable(gl.DEPTH_TEST)

        // Draw light cubes (forward pass — uses blitted depth)
        for i in 0 ..< MAX_LIGHTS {
            light_instances[i] = Light_Instance{
                model = make_transform(lights[i].position, {}, {0.2, 0.2, 0.2}),
                color = lights[i].color,
            }
        }

        gl.BindBuffer(gl.ARRAY_BUFFER, light_instance_vbo)
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, MAX_LIGHTS * size_of(Light_Instance), &light_instances[0])

        gl.UseProgram(light_pg)
        gl.UniformMatrix4fv(light_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(light_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.BindVertexArray(light_cube_vao)
        gl.DrawElementsInstanced(gl.TRIANGLES, i32(cube_index_count), gl.UNSIGNED_INT, nil, MAX_LIGHTS)

        // Draw skybox
        sky_view := glm.mat4(glm.mat3(camera.view))

        gl.DepthFunc(gl.LEQUAL)
        gl.Disable(gl.CULL_FACE)

        gl.UseProgram(skybox_pg)
        gl.UniformMatrix4fv(skybox_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(skybox_uf["u_view"].location, 1, false, &sky_view[0][0])
        gl.BindVertexArray(skybox_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 14)

        gl.DepthFunc(gl.LESS)
        gl.Enable(gl.CULL_FACE)

        sdl.GL_SwapWindow(window)
    }
}
