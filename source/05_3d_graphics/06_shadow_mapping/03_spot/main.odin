package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Spot"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

SHADOW_MAP_SIZE :: 2048
SHADOW_NEAR :: f32(0.1)
SHADOW_FAR :: f32(64)
SHADOW_OUTSIDE_COLOR := glm.vec4{1, 1, 1, 1}

Light :: struct {
    position: glm.vec3,
    dir: glm.vec3,
    color: glm.vec3,
    constant: f32,
    linear: f32,
    quadratic: f32,
    inner_cutoff: f32,
    outer_cutoff: f32,
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

light := Light {
    color = {1, 0.75, 0.4},
    constant = 1.0,
    linear = 0.022,
    quadratic = 0.0019,
    inner_cutoff = glm.cos(glm.radians(f32(24))),
    outer_cutoff = glm.cos(glm.radians(f32(32))),
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
    out vec4 v_light_space_pos;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;
    uniform mat3 u_normal_matrix;
    uniform mat4 u_light_space;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        gl_Position = u_projection * u_view * world_pos;
        v_normal = u_normal_matrix * i_normal;
        v_world_pos = world_pos.xyz;
        v_light_space_pos = u_light_space * world_pos;
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_normal;
    in vec3 v_world_pos;
    in vec4 v_light_space_pos;

    out vec4 o_frag_color;

    uniform vec3 u_view_pos;
    uniform vec3 u_light_pos;
    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;
    uniform float u_light_constant;
    uniform float u_light_linear;
    uniform float u_light_quadratic;
    uniform float u_light_inner_cutoff;
    uniform float u_light_outer_cutoff;
    uniform vec3 u_mat_color;
    uniform float u_mat_ambient_strength;
    uniform float u_mat_diffuse_strength;
    uniform float u_mat_specular_strength;
    uniform float u_mat_specular_shine;
    uniform sampler2D u_shadow_map;

    const int PCF_RADIUS = 1;
    const int PCF_SAMPLES = (2 * PCF_RADIUS + 1) * (2 * PCF_RADIUS + 1);

    float shadow_factor(vec4 light_space_pos) {
        vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
        proj_coords = proj_coords * 0.5 + 0.5;

        if (proj_coords.z > 1.0) {
            return 0.0;
        }

        vec2 texel_size = 1.0 / textureSize(u_shadow_map, 0);
        float bias = 0.00001;
        float shadow = 0.0;

        for (int x = -PCF_RADIUS; x <= PCF_RADIUS; x++) {
            for (int y = -PCF_RADIUS; y <= PCF_RADIUS; y++) {
                float closest_depth = texture(u_shadow_map, proj_coords.xy + vec2(x, y) * texel_size).r;
                shadow += proj_coords.z - bias > closest_depth ? 1.0 : 0.0;
            }
        }

        return shadow / float(PCF_SAMPLES);
    }

    void main() {
        vec3 normal = normalize(v_normal);
        vec3 view_dir = normalize(u_view_pos - v_world_pos);
        vec3 light_dir = normalize(u_light_pos - v_world_pos);
        vec3 half_dir = normalize(light_dir + view_dir);

        float distance = length(u_light_pos - v_world_pos);
        float attenuation = 1.0 / (u_light_constant + u_light_linear * distance + u_light_quadratic * distance * distance);

        float theta = dot(light_dir, normalize(-u_light_dir));
        float intensity = smoothstep(u_light_outer_cutoff, u_light_inner_cutoff, theta);

        vec3 ambient = u_mat_color * u_light_color * u_mat_ambient_strength;
        vec3 diffuse = u_mat_color * u_light_color * max(dot(normal, light_dir), 0.0) * u_mat_diffuse_strength;
        vec3 specular = u_light_color * pow(max(dot(normal, half_dir), 0.0), u_mat_specular_shine) * u_mat_specular_strength;

        float shadow = shadow_factor(v_light_space_pos);
        vec3 result = ambient + (1.0 - shadow) * (diffuse + specular) * attenuation * intensity;

        o_frag_color = vec4(pow(result, vec3(1.0 / 2.2)), 1.0);
    }
`

DEPTH_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;

    uniform mat4 u_light_space;
    uniform mat4 u_model;

    void main() {
        gl_Position = u_light_space * u_model * vec4(i_position, 1.0);
    }
`

DEPTH_FS :: GLSL_VERSION + `
    void main() {}
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

    depth_tex: u32; gl.GenTextures(1, &depth_tex); defer gl.DeleteTextures(1, &depth_tex)
    gl.BindTexture(gl.TEXTURE_2D, depth_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, gl.DEPTH_COMPONENT, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
    gl.TexParameterfv(gl.TEXTURE_2D, gl.TEXTURE_BORDER_COLOR, &SHADOW_OUTSIDE_COLOR[0])

    depth_fbo: u32; gl.GenFramebuffers(1, &depth_fbo); defer gl.DeleteFramebuffers(1, &depth_fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, depth_fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, depth_tex, 0)
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

        light.position = camera.position + camera.forward + camera.right
        light.dir = glm.normalize(glm.vec3{-camera.view[0][2], -camera.view[1][2], -camera.view[2][2]})
        // light.position = {8, 4, 8}
        // light.dir = glm.normalize(glm.vec3{-0.9, -1, -0.9})

        // Depth pass
        light_up := abs(light.dir.y) > 0.99 ? glm.vec3{0, 0, 1} : glm.vec3{0, 1, 0}
        light_fov := glm.acos(light.outer_cutoff) * 2
        light_proj := glm.mat4Perspective(light_fov, 1.0, SHADOW_NEAR, SHADOW_FAR)
        light_view := glm.mat4LookAt(light.position, light.position + light.dir, light_up)
        light_space := light_proj * light_view

        gl.Enable(gl.POLYGON_OFFSET_FILL)
        gl.PolygonOffset(2, 4)
        gl.Viewport(0, 0, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE)
        gl.BindFramebuffer(gl.FRAMEBUFFER, depth_fbo)
        gl.Clear(gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(depth_pg)
        gl.UniformMatrix4fv(depth_uf["u_light_space"].location, 1, false, &light_space[0][0])
        gl.BindVertexArray(main_vao)

        for &mesh in meshes {
            model := make_transform(mesh.translation, mesh.rotation, mesh.scale)

            gl.UniformMatrix4fv(depth_uf["u_model"].location, 1, false, &model[0][0])
            gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
        }

        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Disable(gl.POLYGON_OFFSET_FILL)

        // Main pass
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.15, 0.15, 0.15, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        // Draw meshes
        gl.BindVertexArray(main_vao)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(main_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3fv(main_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.Uniform3fv(main_uf["u_light_pos"].location, 1, &light.position[0])
        gl.Uniform3fv(main_uf["u_light_dir"].location, 1, &light.dir[0])
        gl.Uniform3fv(main_uf["u_light_color"].location, 1, &light.color[0])
        gl.Uniform1f(main_uf["u_light_constant"].location, light.constant)
        gl.Uniform1f(main_uf["u_light_linear"].location, light.linear)
        gl.Uniform1f(main_uf["u_light_quadratic"].location, light.quadratic)
        gl.Uniform1f(main_uf["u_light_inner_cutoff"].location, light.inner_cutoff)
        gl.Uniform1f(main_uf["u_light_outer_cutoff"].location, light.outer_cutoff)
        gl.UniformMatrix4fv(main_uf["u_light_space"].location, 1, false, &light_space[0][0])

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, depth_tex)
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

        sdl.GL_SwapWindow(window)
    }
}
