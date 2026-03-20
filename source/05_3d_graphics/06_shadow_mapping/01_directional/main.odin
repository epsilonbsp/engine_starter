package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Directional"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

Light :: struct {
    dir: glm.vec3,
    color: glm.vec3,
}

Skybox :: struct {
    top: glm.vec3,
    horizon: glm.vec3,
    bottom: glm.vec3,
    sun_disc_threshold: f32,
    sun_inner_power: f32,
    sun_inner_strength: f32,
    sun_outer_power: f32,
    sun_outer_strength: f32,
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

SHADOW_CENTER :: glm.vec3{}
SHADOW_LIGHT_DIST :: f32(80)
SHADOW_ORTHO_SIZE :: f32(32)
SHADOW_NEAR :: f32(0.1)
SHADOW_FAR :: f32(100)
SHADOW_MAP_SIZE :: 4096
SHADOW_OUTSIDE_COLOR := glm.vec4{1, 1, 1, 1}

light := Light{
    glm.normalize(glm.vec3{1, 2, 3}),
    {1, 0.8, 0.6}
}

skybox := Skybox{
    top = {0.0, 0.0, 0.02},
    horizon = {0.03, 0.02, 0.06},
    bottom = {0.0, 0.0, 0.02},
    sun_disc_threshold = 0.9995,
    sun_inner_power = 64.0,
    sun_inner_strength = 0.5,
    sun_outer_power = 64.0,
    sun_outer_strength = 0.3,
}

meshes := []Mesh {
    {{ 0, -1,  0}, {}, {40, 2,  40}, {{0.6, 0.6, 0.6}, 0.05, 0.8, 0.1, 8.0  }},
    {{-8,  4, -8}, {}, {2,  8,  2 }, {{0.2, 0.4, 0.8}, 0.02, 0.9, 0.5, 32.0 }},
    {{-4,  8,  4}, {}, {4,  16, 4 }, {{0.8, 0.5, 0.3}, 0.02, 1.0, 0.0, 1.0  }},
    {{ 8,  2,  0}, {}, {2,  4,  2 }, {{0.7, 0.7, 0.7}, 0.02, 0.6, 1.0, 256.0}},
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
    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;
    uniform vec3 u_mat_color;
    uniform float u_mat_ambient_strength;
    uniform float u_mat_diffuse_strength;
    uniform float u_mat_specular_strength;
    uniform float u_mat_specular_shine;
    uniform sampler2D u_shadow_map;

    // Percentage Closer Filtering
    const int PCF_RADIUS = 1;
    const int PCF_SAMPLES = (2 * PCF_RADIUS + 1) * (2 * PCF_RADIUS + 1);

    float shadow_factor(vec4 light_space_pos, vec3 normal) {
        // Perspective divide: clip space -> NDC [-1, 1] (no-op for orthographic, w=1)
        vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
        // Remap NDC [-1, 1] -> UV [0, 1] for shadow map sampling
        proj_coords = proj_coords * 0.5 + 0.5;

        // Fragment is beyond the light's far plane, treat as not occluded
        if (proj_coords.z > 1.0) {
            return 0.0;
        }

        // Size of one texel in UV space, used to offset PCF samples
        vec2 texel_size = 1.0 / textureSize(u_shadow_map, 0);
        // Small offset applied to receiver depth to avoid self-shadowing (shadow acne)
        float bias = 0.0001;
        float shadow = 0.0;

        // Sample shadow map in a grid, accumulate how many samples are in shadow
        for (int x = -PCF_RADIUS; x <= PCF_RADIUS; x++) {
            for (int y = -PCF_RADIUS; y <= PCF_RADIUS; y++) {
                // Depth of the nearest occluder at this sample offset
                float closest_depth = texture(u_shadow_map, proj_coords.xy + vec2(x, y) * texel_size).r;
                // Accumulate shadow, 1.0 = in shadow, 0.0 = lit
                shadow += proj_coords.z - bias > closest_depth ? 1.0 : 0.0;
            }
        }

        // Average shadow out by sample count
        return shadow / float(PCF_SAMPLES);
    }

    void main() {
        vec3 normal = normalize(v_normal);
        vec3 view_dir = normalize(u_view_pos - v_world_pos);
        vec3 half_dir = normalize(u_light_dir + view_dir);

        vec3 ambient = u_mat_color * u_light_color * u_mat_ambient_strength;
        vec3 diffuse = u_mat_color * u_light_color * max(dot(normal, u_light_dir), 0.0) * u_mat_diffuse_strength;
        vec3 specular = u_light_color * pow(max(dot(normal, half_dir), 0.0), u_mat_specular_shine) * u_mat_specular_strength;

        float shadow = shadow_factor(v_light_space_pos, normal);
        vec3 result = ambient + (1.0 - shadow) * (diffuse + specular);

        o_frag_color = vec4(pow(result, vec3(1.0 / 2.2)), 1.0);
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
        vec4 clip = u_projection * mat4(mat3(u_view)) * vec4(position, 1.0);

        gl_Position = clip.xyww;
        v_tex_coord = position;
    }
`

SKYBOX_FS :: GLSL_VERSION + `
    in vec3 v_tex_coord;

    out vec4 o_frag_color;

    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;
    uniform vec3 u_skybox_top;
    uniform vec3 u_skybox_horizon;
    uniform vec3 u_skybox_bottom;
    uniform float u_sun_disc_threshold;
    uniform vec4 u_sun_glow; // xy = inner (power, strength), zw = outer (power, strength)

    void main() {
        vec3 dir = normalize(v_tex_coord);

        vec3 current_color = dir.y >= 0.0
            ? mix(u_skybox_horizon, u_skybox_top, dir.y)
            : mix(u_skybox_horizon, u_skybox_bottom, -dir.y);

        float sun_dot = dot(dir, u_light_dir);
        float sun_disc = smoothstep(u_sun_disc_threshold, 1.0, sun_dot);
        float sun_inner = pow(max(sun_dot, 0.0), u_sun_glow.x) * u_sun_glow.y;
        float sun_outer = pow(max(sun_dot, 0.0), u_sun_glow.z) * u_sun_glow.w;

        vec3 color = current_color + u_light_color * (sun_disc + sun_inner + sun_outer);

        o_frag_color = vec4(pow(color, vec3(1.0 / 2.2)), 1.0);
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

    if !main_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    skybox_pg, skybox_ok := gl.load_shaders_source(SKYBOX_VS, SKYBOX_FS); defer gl.DeleteProgram(skybox_pg)
    skybox_uf := gl.get_uniforms_from_program(skybox_pg); defer gl.destroy_uniforms(skybox_uf);

    if !skybox_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    depth_pg, depth_ok := gl.load_shaders_source(DEPTH_VS, DEPTH_FS); defer gl.DeleteProgram(depth_pg)
    depth_uf := gl.get_uniforms_from_program(depth_pg); defer gl.destroy_uniforms(depth_uf)

    if !depth_ok {
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

    main_ibo: u32; gl.GenBuffers(1, &main_ibo); defer gl.DeleteBuffers(1, &main_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, mesh_index_count * size_of(mesh_indices[0]), &mesh_indices[0], gl.STATIC_DRAW)

    skybox_vao: u32; gl.GenVertexArrays(1, &skybox_vao); defer gl.DeleteVertexArrays(1, &skybox_vao)
    gl.BindVertexArray(skybox_vao)

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

        light.dir = glm.normalize(glm.vec3{glm.cos(time_seconds * 0.2), glm.sin(time_seconds * 0.2), glm.sin(time_seconds * 0.1)})

        // Depth pass
        light_up := abs(light.dir.y) > 0.99 ? glm.vec3{0, 0, 1} : glm.vec3{0, 1, 0}
        light_view := glm.mat4LookAt(light.dir * SHADOW_LIGHT_DIST, SHADOW_CENTER, light_up)

        // Shadow stabilization: snap the projection to texel boundaries
        // Prevents shadow edges from shimmering as the light direction changes
        origin_ls := light_view * glm.vec4{0, 0, 0, 1} // World origin in light space (reference point)
        texel_size := (SHADOW_ORTHO_SIZE * 2) / f32(SHADOW_MAP_SIZE) // World space size of one shadow texel
        offset_x := origin_ls.x - glm.floor(origin_ls.x / texel_size) * texel_size // Sub-texel remainder in X
        offset_y := origin_ls.y - glm.floor(origin_ls.y / texel_size) * texel_size // Sub-texel remainder in Y

        // Shift the frustum bounds by the remainder so the projection always aligns to the texel grid
        light_proj := glm.mat4Ortho3d(
            -SHADOW_ORTHO_SIZE - offset_x, SHADOW_ORTHO_SIZE - offset_x,
            -SHADOW_ORTHO_SIZE - offset_y, SHADOW_ORTHO_SIZE - offset_y,
            SHADOW_NEAR, SHADOW_FAR,
        )

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
        gl.ClearColor(0.5, 0.5, 0.5, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.BindVertexArray(main_vao)

        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(main_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3fv(main_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.Uniform3fv(main_uf["u_light_dir"].location, 1, &light.dir[0])
        gl.Uniform3fv(main_uf["u_light_color"].location, 1, &light.color[0])
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

        // Draw skybox
        gl.DepthFunc(gl.LEQUAL)
        gl.Disable(gl.CULL_FACE)

        gl.UseProgram(skybox_pg)
        gl.UniformMatrix4fv(skybox_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(skybox_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3fv(skybox_uf["u_light_dir"].location, 1, &light.dir[0])
        gl.Uniform3fv(skybox_uf["u_light_color"].location, 1, &light.color[0])
        gl.Uniform3fv(skybox_uf["u_skybox_top"].location, 1, &skybox.top[0])
        gl.Uniform3fv(skybox_uf["u_skybox_horizon"].location, 1, &skybox.horizon[0])
        gl.Uniform3fv(skybox_uf["u_skybox_bottom"].location, 1, &skybox.bottom[0])
        gl.Uniform1f(skybox_uf["u_sun_disc_threshold"].location, skybox.sun_disc_threshold)
        gl.Uniform4f(skybox_uf["u_sun_glow"].location, skybox.sun_inner_power, skybox.sun_inner_strength, skybox.sun_outer_power, skybox.sun_outer_strength)
        gl.BindVertexArray(skybox_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 14)

        gl.DepthFunc(gl.LESS)
        gl.Enable(gl.CULL_FACE)

        sdl.GL_SwapWindow(window)
    }
}
