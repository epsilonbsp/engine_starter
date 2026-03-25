package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Point"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

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

Mesh :: struct {
    translation: glm.vec3,
    rotation: glm.vec3,
    scale: glm.vec3,
    material: Material,
}

Vertex :: struct {
    position: glm.vec3,
    normal: glm.vec3,
}

SHADOW_MAP_SIZE :: 2048
SHADOW_NEAR :: f32(0.1)
SHADOW_FAR :: f32(32.0)

light := Light {
    position = {0, 3, 0},
    color = {1, 0.75, 0.4},
    constant = 1.0,
    linear = 0.022,
    quadratic = 0.0019,
}

meshes := []Mesh {
    {{ 0, -1,  0}, {}, {20, 2,  20}, {{0.6, 0.6, 0.6}, 0.02, 0.8, 0.1, 8.0  }},
    {{-4,  1,  0}, {}, {2,  2,  2 }, {{0.2, 0.4, 0.8}, 0.02, 0.9, 0.5, 32.0 }},
    {{ 4,  2,  0}, {}, {2,  4,  2 }, {{0.8, 0.5, 0.3}, 0.02, 1.0, 0.0, 1.0  }},
    {{ 0,  4, -4}, {}, {2,  8,  2 }, {{0.7, 0.7, 0.7}, 0.02, 0.6, 1.0, 256.0}},
    {{ 0,  6,  4}, {}, {2,  12, 2 }, {{0.6, 0.3, 0.7}, 0.02, 0.8, 0.3, 16.0 }},
}

mesh_vertices := []Vertex {
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

    out vec3 v_normal;
    out vec3 v_world_pos;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;
    uniform mat3 u_normal_matrix;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        gl_Position = u_projection * u_view * world_pos;
        v_normal = u_normal_matrix * i_normal;
        v_world_pos = world_pos.xyz;
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_normal;
    in vec3 v_world_pos;

    out vec4 o_frag_color;

    uniform vec3 u_view_pos;
    uniform vec3 u_light_pos;
    uniform vec3 u_light_color;
    uniform float u_light_constant;
    uniform float u_light_linear;
    uniform float u_light_quadratic;
    uniform vec3 u_mat_color;
    uniform float u_mat_ambient_strength;
    uniform float u_mat_diffuse_strength;
    uniform float u_mat_specular_strength;
    uniform float u_mat_specular_shine;
    uniform samplerCube u_shadow_map;
    uniform float u_shadow_far;

    const int PCF_SAMPLES = 20;

    const vec3 SAMPLE_DISK[20] = vec3[](
        vec3(1,  1,  1), vec3( 1, -1,  1), vec3(-1, -1,  1), vec3(-1,  1,  1),
        vec3(1,  1, -1), vec3( 1, -1, -1), vec3(-1, -1, -1), vec3(-1,  1, -1),
        vec3(1,  1,  0), vec3( 1, -1,  0), vec3(-1, -1,  0), vec3(-1,  1,  0),
        vec3(1,  0,  1), vec3(-1,  0,  1), vec3( 1,  0, -1), vec3(-1,  0, -1),
        vec3(0,  1,  1), vec3( 0, -1,  1), vec3( 0, -1, -1), vec3( 0,  1, -1)
    );

    float shadow_factor(vec3 world_pos) {
        vec3 frag_to_light = world_pos - u_light_pos;
        float current_depth = length(frag_to_light);
        float view_distance = length(u_view_pos - world_pos);
        float disk_radius = (1.0 + view_distance / u_shadow_far) / 25.0;
        float bias = 0.15;
        float shadow = 0.0;

        for (int i = 0; i < PCF_SAMPLES; i++) {
            // Depth of the nearest occluder at this sample offset
            float closest_depth = texture(u_shadow_map, frag_to_light + SAMPLE_DISK[i] * disk_radius).r * u_shadow_far;
            // Accumulate shadow, 1.0 = in shadow, 0.0 = lit
            shadow += current_depth - bias > closest_depth ? 1.0 : 0.0;
        }

        // Average shadow out by sample count
        return shadow / float(PCF_SAMPLES);
    }

    void main() {
        vec3 normal = normalize(v_normal);
        vec3 view_dir = normalize(u_view_pos - v_world_pos);
        vec3 light_dir = normalize(u_light_pos - v_world_pos);
        vec3 half_dir = normalize(light_dir + view_dir);

        float distance = length(u_light_pos - v_world_pos);
        float attenuation = 1.0 / (u_light_constant + u_light_linear * distance + u_light_quadratic * distance * distance);

        vec3 ambient = u_mat_color * u_light_color * u_mat_ambient_strength;
        vec3 diffuse = u_mat_color * u_light_color * max(dot(normal, light_dir), 0.0) * u_mat_diffuse_strength;
        vec3 specular = u_light_color * pow(max(dot(normal, half_dir), 0.0), u_mat_specular_shine) * u_mat_specular_strength;

        float shadow = shadow_factor(v_world_pos);
        vec3 result = ambient + (1.0 - shadow) * (diffuse + specular) * attenuation;

        o_frag_color = vec4(pow(result, vec3(1.0 / 2.2)), 1.0);
    }
`

LIGHT_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;

    void main() {
        gl_Position = u_projection * u_view * u_model * vec4(i_position, 1.0);
    }
`

LIGHT_FS :: GLSL_VERSION + `
    out vec4 o_frag_color;

    uniform vec3 u_color;

    void main() {
        o_frag_color = vec4(u_color, 1.0);
    }
`

DEPTH_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;

    out vec3 v_world_pos;

    uniform mat4 u_light_space;
    uniform mat4 u_model;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        gl_Position = u_light_space * world_pos;
        v_world_pos = world_pos.xyz;
    }
`

DEPTH_FS :: GLSL_VERSION + `
    in vec3 v_world_pos;

    uniform vec3 u_light_pos;
    uniform float u_shadow_far;

    void main() {
        float dist = length(v_world_pos - u_light_pos);

        gl_FragDepth = dist / u_shadow_far;
    }
`

make_transform :: proc(translation: glm.vec3, rotation: glm.vec3, scale: glm.vec3) -> glm.mat4 {
    qx := glm.quatAxisAngle({1, 0, 0}, rotation.x)
    qy := glm.quatAxisAngle({0, 1, 0}, rotation.y)
    qz := glm.quatAxisAngle({0, 0, 1}, rotation.z)
    q := qz * qy * qx

    return glm.mat4Translate(translation) * glm.mat4FromQuat(q) * glm.mat4Scale(scale)
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
    assert(main_ok, "ERROR: Failed to compile program")

    light_pg, light_ok := gl.load_shaders_source(LIGHT_VS, LIGHT_FS); defer gl.DeleteProgram(light_pg)
    light_uf := gl.get_uniforms_from_program(light_pg); defer gl.destroy_uniforms(light_uf)
    assert(light_ok, "ERROR: Failed to compile program")

    depth_pg, depth_ok := gl.load_shaders_source(DEPTH_VS, DEPTH_FS); defer gl.DeleteProgram(depth_pg)
    depth_uf := gl.get_uniforms_from_program(depth_pg); defer gl.destroy_uniforms(depth_uf)
    assert(depth_ok, "ERROR: Failed to compile program")

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(mesh_vertices) * size_of(mesh_vertices[0]), &mesh_vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, normal))

    main_ibo: u32; gl.GenBuffers(1, &main_ibo); defer gl.DeleteBuffers(1, &main_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, mesh_index_count * size_of(mesh_indices[0]), &mesh_indices[0], gl.STATIC_DRAW)

    depth_cubemap: u32; gl.GenTextures(1, &depth_cubemap); defer gl.DeleteTextures(1, &depth_cubemap)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, depth_cubemap)

    for i in 0 ..< 6 {
        face := gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(i)

        gl.TexImage2D(face, 0, gl.DEPTH_COMPONENT, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, gl.DEPTH_COMPONENT, gl.FLOAT, nil)
    }

    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)

    depth_fbo: u32; gl.GenFramebuffers(1, &depth_fbo); defer gl.DeleteFramebuffers(1, &depth_fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, depth_fbo)
    gl.DrawBuffer(gl.NONE)
    gl.ReadBuffer(gl.NONE)
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    camera: Camera
    init_camera(&camera, position = {6, 6, 6})
    point_camera_at(&camera, {})

    camera_movement := Camera_Movement{move_speed = 5, yaw_speed = 0.002, pitch_speed = 0.002}

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    loop: for {
        time_curr = u64(sdl.GetTicks())
        time_delta = f32(time_curr - time_last) / 1000
        time_last = time_curr
        time_seconds := f32(time_curr) / 1000

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

        light.position = {0, 8, 0} + {glm.cos(time_seconds * 0.5) * 6, glm.sin(time_seconds * 0.5) * 4, glm.sin(time_seconds * 0.5) * 6}

        // Depth pass
        shadow_proj := glm.mat4Perspective(glm.radians(f32(90)), 1.0, SHADOW_NEAR, SHADOW_FAR)
        shadow_matrices := [6]glm.mat4{
            shadow_proj * glm.mat4LookAt(light.position, light.position + glm.vec3{ 1,  0,  0}, { 0, -1,  0}),
            shadow_proj * glm.mat4LookAt(light.position, light.position + glm.vec3{-1,  0,  0}, { 0, -1,  0}),
            shadow_proj * glm.mat4LookAt(light.position, light.position + glm.vec3{ 0,  1,  0}, { 0,  0,  1}),
            shadow_proj * glm.mat4LookAt(light.position, light.position + glm.vec3{ 0, -1,  0}, { 0,  0, -1}),
            shadow_proj * glm.mat4LookAt(light.position, light.position + glm.vec3{ 0,  0,  1}, { 0, -1,  0}),
            shadow_proj * glm.mat4LookAt(light.position, light.position + glm.vec3{ 0,  0, -1}, { 0, -1,  0}),
        }

        gl.Enable(gl.POLYGON_OFFSET_FILL)
        gl.PolygonOffset(2, 4)
        gl.Viewport(0, 0, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE)
        gl.BindFramebuffer(gl.FRAMEBUFFER, depth_fbo)

        gl.UseProgram(depth_pg)
        gl.Uniform3fv(depth_uf["u_light_pos"].location, 1, &light.position[0])
        gl.Uniform1f(depth_uf["u_shadow_far"].location, SHADOW_FAR)

        gl.BindVertexArray(main_vao)

        for i in 0 ..< 6 {
            face := gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(i)
            gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, face, depth_cubemap, 0)
            gl.Clear(gl.DEPTH_BUFFER_BIT)
            gl.UniformMatrix4fv(depth_uf["u_light_space"].location, 1, false, &shadow_matrices[i][0][0])

            for &mesh in meshes {
                model := make_transform(mesh.translation, mesh.rotation, mesh.scale)

                gl.UniformMatrix4fv(depth_uf["u_model"].location, 1, false, &model[0][0])
                gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
            }
        }

        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Disable(gl.POLYGON_OFFSET_FILL)

        // Draw meshes
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.15, 0.15, 0.15, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.BindVertexArray(main_vao)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(main_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3fv(main_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.Uniform3fv(main_uf["u_light_pos"].location, 1, &light.position[0])
        gl.Uniform3fv(main_uf["u_light_color"].location, 1, &light.color[0])
        gl.Uniform1f(main_uf["u_light_constant"].location, light.constant)
        gl.Uniform1f(main_uf["u_light_linear"].location, light.linear)
        gl.Uniform1f(main_uf["u_light_quadratic"].location, light.quadratic)
        gl.Uniform1f(main_uf["u_shadow_far"].location, SHADOW_FAR)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, depth_cubemap)
        gl.Uniform1i(main_uf["u_shadow_map"].location, 0)

        for &mesh in meshes {
            model := make_transform(mesh.translation, mesh.rotation, mesh.scale)
            normal_matrix := glm.transpose(glm.inverse(glm.mat3(model)))

            gl.UniformMatrix4fv(main_uf["u_model"].location, 1, false, &model[0][0])
            gl.UniformMatrix3fv(main_uf["u_normal_matrix"].location, 1, false, &normal_matrix[0][0])
            gl.Uniform3fv(main_uf["u_mat_color"].location, 1, &mesh.material.color[0])
            gl.Uniform1f(main_uf["u_mat_ambient_strength"].location, mesh.material.ambient_strength)
            gl.Uniform1f(main_uf["u_mat_diffuse_strength"].location, mesh.material.diffuse_strength)
            gl.Uniform1f(main_uf["u_mat_specular_strength"].location, mesh.material.specular_strength)
            gl.Uniform1f(main_uf["u_mat_specular_shine"].location, mesh.material.specular_shine)

            gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
        }

        // Draw light cube
        light_model := make_transform(light.position, {}, {0.3, 0.3, 0.3})

        gl.UseProgram(light_pg)
        gl.UniformMatrix4fv(light_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(light_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.UniformMatrix4fv(light_uf["u_model"].location, 1, false, &light_model[0][0])
        gl.Uniform3fv(light_uf["u_color"].location, 1, &light.color[0])
        gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)

        sdl.GL_SwapWindow(window)
    }
}
