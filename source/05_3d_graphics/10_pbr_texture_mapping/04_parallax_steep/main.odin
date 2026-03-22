package example

import "core:fmt"
import "core:image/png"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Parallax Steep"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

Light :: struct {
    dir: glm.vec3,
    color: glm.vec3,
}

Material :: struct {
    albedo: glm.vec3,
    metallic: f32,
    roughness: f32,
    ao: f32,
}

Mesh :: struct {
    translation: glm.vec3,
    rotation: glm.vec3,
    scale: glm.vec3,
    material: Material,
}

Vertex :: struct {
    position: glm.vec3,
    normal: glm.vec3,
    tex_coord: glm.vec2,
    tangent: glm.vec3,
}

light := Light{
    glm.normalize(glm.vec3{1, 2, 3}),
    {1, 0.8, 0.6}
}

exposure := f32(2.0)
height_scale := f32(0.05)

meshes := []Mesh {
    {{-4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.8, 0.5, 0.3}, 0.0, 0.8, 1.0}},
    {{ 0, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.2, 0.4, 0.8}, 0.0, 0.4, 1.0}},
    {{ 4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.7, 0.7, 0.7}, 1.0, 0.2, 1.0}},
}

mesh_vertices := []Vertex {
    // Left
    {{-0.5, -0.5, -0.5}, {-1, 0, 0}, {0, 1}, { 0, 0, 1}},
    {{-0.5, -0.5,  0.5}, {-1, 0, 0}, {1, 1}, { 0, 0, 1}},
    {{-0.5,  0.5,  0.5}, {-1, 0, 0}, {1, 0}, { 0, 0, 1}},
    {{-0.5,  0.5, -0.5}, {-1, 0, 0}, {0, 0}, { 0, 0, 1}},

    // Right
    {{ 0.5, -0.5,  0.5}, {1, 0, 0}, {0, 1}, {0, 0, -1}},
    {{ 0.5, -0.5, -0.5}, {1, 0, 0}, {1, 1}, {0, 0, -1}},
    {{ 0.5,  0.5, -0.5}, {1, 0, 0}, {1, 0}, {0, 0, -1}},
    {{ 0.5,  0.5,  0.5}, {1, 0, 0}, {0, 0}, {0, 0, -1}},

    // Bottom
    {{-0.5, -0.5, -0.5}, {0, -1, 0}, {0, 1}, {1, 0, 0}},
    {{ 0.5, -0.5, -0.5}, {0, -1, 0}, {1, 1}, {1, 0, 0}},
    {{ 0.5, -0.5,  0.5}, {0, -1, 0}, {1, 0}, {1, 0, 0}},
    {{-0.5, -0.5,  0.5}, {0, -1, 0}, {0, 0}, {1, 0, 0}},

    // Top
    {{-0.5,  0.5,  0.5}, {0, 1, 0}, {0, 1}, {1, 0, 0}},
    {{ 0.5,  0.5,  0.5}, {0, 1, 0}, {1, 1}, {1, 0, 0}},
    {{ 0.5,  0.5, -0.5}, {0, 1, 0}, {1, 0}, {1, 0, 0}},
    {{-0.5,  0.5, -0.5}, {0, 1, 0}, {0, 0}, {1, 0, 0}},

    // Back
    {{ 0.5, -0.5, -0.5}, {0, 0, -1}, {0, 1}, {-1, 0, 0}},
    {{-0.5, -0.5, -0.5}, {0, 0, -1}, {1, 1}, {-1, 0, 0}},
    {{-0.5,  0.5, -0.5}, {0, 0, -1}, {1, 0}, {-1, 0, 0}},
    {{ 0.5,  0.5, -0.5}, {0, 0, -1}, {0, 0}, {-1, 0, 0}},

    // Front
    {{-0.5, -0.5,  0.5}, {0, 0, 1}, {0, 1}, {1, 0, 0}},
    {{ 0.5, -0.5,  0.5}, {0, 0, 1}, {1, 1}, {1, 0, 0}},
    {{ 0.5,  0.5,  0.5}, {0, 0, 1}, {1, 0}, {1, 0, 0}},
    {{-0.5,  0.5,  0.5}, {0, 0, 1}, {0, 0}, {1, 0, 0}},
}

mesh_indices := []u32 {
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

mesh_index_count := len(mesh_indices)

MAIN_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;
    layout(location = 2) in vec2 i_tex_coord;
    layout(location = 3) in vec3 i_tangent;

    out vec3 v_normal;
    out vec2 v_tex_coord;
    out mat3 v_tbn;
    out vec3 v_world_pos;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;
    uniform mat3 u_normal_matrix;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        vec3 normal = normalize(u_normal_matrix * i_normal);
        vec3 tangent = normalize(u_normal_matrix * i_tangent);
        tangent = normalize(tangent - dot(tangent, normal) * normal);
        vec3 bitangent = cross(normal, tangent);

        gl_Position = u_projection * u_view * world_pos;
        v_normal = u_normal_matrix * i_normal;
        v_tex_coord = i_tex_coord;
        v_tbn = mat3(tangent, bitangent, normal);
        v_world_pos = world_pos.xyz;
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_normal;
    in vec2 v_tex_coord;
    in mat3 v_tbn;
    in vec3 v_world_pos;

    out vec4 o_frag_color;

    uniform vec3 u_view_pos;
    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;
    uniform float u_exposure;
    uniform vec3 u_mat_albedo;
    uniform float u_mat_metallic;
    uniform float u_mat_roughness;
    uniform float u_mat_ao;
    uniform sampler2D u_albedo_tex;
    uniform sampler2D u_arm_tex;
    uniform sampler2D u_normal_tex;
    uniform sampler2D u_displacement_tex;
    uniform float u_height_scale;

    const float PI = 3.14159265359;

    float distribution_ggx(vec3 n, vec3 h, float roughness) {
        float a = roughness * roughness;
        float a2 = a * a;
        float n_dot_h = max(dot(n, h), 0.0);
        float denom = (n_dot_h * n_dot_h * (a2 - 1.0) + 1.0);

        return a2 / (PI * denom * denom);
    }

    float geometry_schlick_ggx(float n_dot_v, float roughness) {
        float k = (roughness + 1.0);
        k = (k * k) / 8.0;
    
        return n_dot_v / (n_dot_v * (1.0 - k) + k);
    }

    float geometry_smith(vec3 n, vec3 v, vec3 l, float roughness) {
        float nv = geometry_schlick_ggx(max(dot(n, v), 0.0), roughness);
        float nl = geometry_schlick_ggx(max(dot(n, l), 0.0), roughness);

        return nv * nl;
    }

    vec3 fresnel_schlick(float cos_theta, vec3 f0) {
        return f0 + (1.0 - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
    }

    vec2 parallax_mapping(vec2 tc, vec3 tangent_v) {
        float num_layers = mix(32.0, 8.0, abs(dot(vec3(0.0, 0.0, 1.0), tangent_v)));
        float layer_depth = 1.0 / num_layers;
        vec2 delta_tc = (tangent_v.xy / tangent_v.z * u_height_scale) / num_layers;

        float current_layer_depth = 0.0;
        float current_height = texture(u_displacement_tex, tc).r;

        while (current_layer_depth < current_height) {
            tc -= delta_tc;
            current_height = texture(u_displacement_tex, tc).r;
            current_layer_depth += layer_depth;
        }

        return tc;
    }

    void main() {
        // Parallax UV offset
        vec3 v = normalize(u_view_pos - v_world_pos);
        vec3 tangent_v = normalize(transpose(v_tbn) * v);
        vec2 tex_coord = parallax_mapping(v_tex_coord, tangent_v);

        vec3 albedo = texture(u_albedo_tex, tex_coord).rgb * u_mat_albedo;
        vec3 arm = texture(u_arm_tex, tex_coord).rgb;
        float ao = arm.r * u_mat_ao;
        float roughness = arm.g * u_mat_roughness;
        float metallic = arm.b * u_mat_metallic;

        // Direction vectors
        vec3 n = texture(u_normal_tex, tex_coord).rgb * 2.0 - 1.0;
        n = normalize(v_tbn * n);
        vec3 l = normalize(u_light_dir);
        vec3 h = normalize(v + l);

        // Base reflectivity: 0.04 for dielectrics, albedo for metals
        vec3 f0 = mix(vec3(0.04), albedo, metallic);

        // Cook-torrance BRDF terms
        float ndf = distribution_ggx(n, h, roughness);
        float g = geometry_smith(n, v, l, roughness);
        vec3 f = fresnel_schlick(clamp(dot(h, v), 0.0, 1.0), f0);

        // Diffuse, metals have no diffuse
        vec3 kd = (vec3(1.0) - f) * (1.0 - metallic);

        // Specular
        vec3 specular = (ndf * g * f) / (4.0 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0) + 0.0001);

        // Outgoing radiance
        float n_dot_l = max(dot(n, l), 0.0);
        vec3 lo = (kd * albedo / PI + specular) * u_light_color * n_dot_l;

        // Ambient
        vec3 ambient = vec3(0.03) * albedo * ao;

        // Color
        vec3 color = ambient + lo;

        // Exposure tone mapping
        color = vec3(1.0) - exp(-color * u_exposure);

        // Gamma correction
        color = pow(color, vec3(1.0 / 2.2));

        o_frag_color = vec4(color, 1.0);
    }
`

make_transform :: proc(translation: glm.vec3, rotation: glm.vec3, scale: glm.vec3) -> glm.mat4 {
    qx := glm.quatAxisAngle({1, 0, 0}, rotation.x)
    qy := glm.quatAxisAngle({0, 1, 0}, rotation.y)
    qz := glm.quatAxisAngle({0, 0, 1}, rotation.z)
    q := qz * qy * qx

    return glm.mat4Translate(translation) * glm.mat4FromQuat(q) * glm.mat4Scale(scale)
}

load_texture_from_bytes :: proc(bytes: []u8, srgb := false) -> u32 {
    image, _ := png.load_from_bytes(bytes, {.alpha_add_if_missing}); defer png.destroy(image)

    tex: u32; gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D, tex)

    w, h := i32(image.width), i32(image.height)

    if image.depth == 16 {
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16, w, h, 0, gl.RGBA, gl.UNSIGNED_SHORT, &image.pixels.buf[0])
    } else {
        internal_format := srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8
        gl.TexImage2D(gl.TEXTURE_2D, 0, i32(internal_format), w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, &image.pixels.buf[0])
    }

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)

    return tex
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
    time_curr := u64(sdl.GetTicks())
    time_last: u64
    time_delta: f32

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);

    if !main_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(mesh_vertices) * size_of(mesh_vertices[0]), &mesh_vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, normal))

    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, tex_coord))

    gl.EnableVertexAttribArray(3)
    gl.VertexAttribPointer(3, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, tangent))

    main_ibo: u32; gl.GenBuffers(1, &main_ibo); defer gl.DeleteBuffers(1, &main_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, mesh_index_count * size_of(mesh_indices[0]), &mesh_indices[0], gl.STATIC_DRAW)

    // Source: https://polyhaven.com/a/rusty_metal_04
    albedo_tex := load_texture_from_bytes(#load("textures/albedo.png"), true); defer gl.DeleteTextures(1, &albedo_tex)
    arm_tex := load_texture_from_bytes(#load("textures/arm.png")); defer gl.DeleteTextures(1, &arm_tex)
    normal_tex := load_texture_from_bytes(#load("textures/normal.png")); defer gl.DeleteTextures(1, &normal_tex)
    displacement_tex := load_texture_from_bytes(#load("textures/displacement.png")); defer gl.DeleteTextures(1, &displacement_tex)

    camera: Camera;
    init_camera(&camera, position = {6, 6, 6})
    point_camera_at(&camera, {})

    camera_movement := Camera_Movement{move_speed = 5, yaw_speed = 0.002, pitch_speed = 0.002}

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    loop: for {
        time_curr = u64(sdl.GetTicks())
        time_delta = f32(time_curr - time_last) / 1000
        time_last = time_curr

        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
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

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.5, 0.5, 0.5, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(main_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3fv(main_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.Uniform3fv(main_uf["u_light_dir"].location, 1, &light.dir[0])
        gl.Uniform3fv(main_uf["u_light_color"].location, 1, &light.color[0])
        gl.Uniform1f(main_uf["u_exposure"].location, exposure)
        gl.Uniform1f(main_uf["u_height_scale"].location, height_scale)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, albedo_tex)
        gl.Uniform1i(main_uf["u_albedo_tex"].location, 0)

        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, arm_tex)
        gl.Uniform1i(main_uf["u_arm_tex"].location, 1)

        gl.ActiveTexture(gl.TEXTURE2)
        gl.BindTexture(gl.TEXTURE_2D, normal_tex)
        gl.Uniform1i(main_uf["u_normal_tex"].location, 2)

        gl.ActiveTexture(gl.TEXTURE3)
        gl.BindTexture(gl.TEXTURE_2D, displacement_tex)
        gl.Uniform1i(main_uf["u_displacement_tex"].location, 3)

        for &mesh in meshes {
            model := make_transform(mesh.translation, mesh.rotation, mesh.scale)
            normal_matrix := glm.transpose(glm.inverse(glm.mat3(model)))

            gl.UniformMatrix4fv(main_uf["u_model"].location, 1, false, &model[0][0])
            gl.UniformMatrix3fv(main_uf["u_normal_matrix"].location, 1, false, &normal_matrix[0][0])
            gl.Uniform3fv(main_uf["u_mat_albedo"].location, 1, &mesh.material.albedo[0])
            gl.Uniform1f(main_uf["u_mat_metallic"].location, mesh.material.metallic)
            gl.Uniform1f(main_uf["u_mat_roughness"].location, mesh.material.roughness)
            gl.Uniform1f(main_uf["u_mat_ao"].location, mesh.material.ao)

            gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
        }

        sdl.GL_SwapWindow(window)
    }
}
