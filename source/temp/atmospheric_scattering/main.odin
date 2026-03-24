package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Atmospheric Scattering"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

Light :: struct {
    dir: glm.vec3,
    color: glm.vec3,
}

Atmosphere :: struct {
    sun_intensity: f32,
    sun_disc_angle: f32,
    planet_radius: f32,
    atmo_radius: f32,
    h_rayleigh: f32,
    h_mie: f32,
    beta_rayleigh: glm.vec3,
    beta_ozone: glm.vec3,
    beta_mie: f32,
    g: f32,
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

light := Light{
    glm.normalize(glm.vec3{32, 1, 32}),
    {1, 0.8, 0.6}
}

atmosphere := Atmosphere{
    sun_intensity = 22.0,
    sun_disc_angle = 0.04,
    planet_radius = 6_371_000.0,
    atmo_radius = 6_471_000.0,
    h_rayleigh = 8_000.0,
    h_mie = 1_200.0,
    beta_rayleigh = {5.5e-6, 13.0e-6, 22.4e-6},
    beta_ozone = {0.65e-6, 1.881e-6, 0.085e-6},
    beta_mie = 21e-6,
    g = 0.758,
}

meshes := []Mesh {
    {{-4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.8, 0.5, 0.3}, 0.02, 1.0, 0.0, 1.0  }},
    {{ 0, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.2, 0.4, 0.8}, 0.02, 0.9, 0.5, 32.0 }},
    {{ 4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.7, 0.7, 0.7}, 0.02, 0.6, 1.0, 256.0}},
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
    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;
    uniform vec3 u_mat_color;
    uniform float u_mat_ambient_strength;
    uniform float u_mat_diffuse_strength;
    uniform float u_mat_specular_strength;
    uniform float u_mat_specular_shine;

    void main() {
        vec3 normal = normalize(v_normal);
        vec3 view_dir = normalize(u_view_pos - v_world_pos);
        vec3 half_dir = normalize(u_light_dir + view_dir);

        vec3 ambient = u_mat_color * u_light_color * u_mat_ambient_strength;
        vec3 diffuse = u_mat_color * u_light_color * max(dot(normal, u_light_dir), 0.0) * u_mat_diffuse_strength;
        vec3 specular = u_light_color * pow(max(dot(normal, half_dir), 0.0), u_mat_specular_shine) * u_mat_specular_strength;

        vec3 result = ambient + diffuse + specular;

        o_frag_color = vec4(result, 1.0);
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

    uniform vec3 u_sun_dir;
    uniform float u_sun_intensity;
    uniform float u_sun_disc_angle; // angular radius in radians
    uniform float u_planet_radius;
    uniform float u_atmo_radius;
    uniform float u_h_rayleigh;
    uniform float u_h_mie;
    uniform vec3 u_beta_rayleigh;
    uniform vec3 u_beta_ozone;
    uniform float u_beta_mie;
    uniform float u_g;

    const float PI = 3.141592653589793;
    const int PRIMARY_STEPS = 16;
    const int LIGHT_STEPS = 8;

    // Returns the two ray-sphere intersection distances (negative if no hit).
    vec2 ray_sphere(vec3 origin, vec3 dir, float radius) {
        float b = dot(origin, dir);
        float c = dot(origin, origin) - radius * radius;
        float d = b * b - c;

        if (d < 0.0) {
            return vec2(-1.0);
        }

        float sq = sqrt(d);

        return vec2(-b - sq, -b + sq);
    }

    // Ozone density peaks at ~25 km, tapers off over ±15 km.
    float ozone_density(float alt) {
        return max(0.0, 1.0 - abs(alt - 25000.0) / 15000.0);
    }

    // Transmittance from the surface toward the sun — determines the sun disc color.
    vec3 sun_transmittance() {
        vec3 origin = vec3(0.0, u_planet_radius + 1.0, 0.0);
        vec2 hit = ray_sphere(origin, u_sun_dir, u_atmo_radius);

        if (hit.y < 0.0) {
            return vec3(0.0);
        }

        float step_size = hit.y / float(LIGHT_STEPS);
        float od_r = 0.0, od_m = 0.0, od_o = 0.0;

        for (int i = 0; i < LIGHT_STEPS; i++) {
            vec3 p  = origin + u_sun_dir * ((float(i) + 0.5) * step_size);
            float alt = length(p) - u_planet_radius;
    
            od_r += exp(-alt / u_h_rayleigh) * step_size;
            od_m += exp(-alt / u_h_mie) * step_size;
            od_o += ozone_density(alt) * step_size;
        }

        return exp(-(u_beta_rayleigh * od_r + u_beta_mie * 1.1 * od_m + u_beta_ozone * od_o));
    }

    vec3 scatter(vec3 ray_dir) {
        // Place viewer just above the planet surface.
        vec3 ray_origin = vec3(0.0, u_planet_radius + 1.0, 0.0);

        vec2 atmo_hit = ray_sphere(ray_origin, ray_dir, u_atmo_radius);

        if (atmo_hit.y < 0.0) {
            return vec3(0.0);
        }

        float t_start = max(atmo_hit.x, 0.0);
        float t_end = atmo_hit.y;

        // Clip against planet surface.
        vec2 ground_hit = ray_sphere(ray_origin, ray_dir, u_planet_radius);

        if (ground_hit.x > 0.0) {
            t_end = min(t_end, ground_hit.x);
        }

        float step_size = (t_end - t_start) / float(PRIMARY_STEPS);

        vec3 rayleigh_sum = vec3(0.0);
        vec3 mie_sum = vec3(0.0);
        float od_r = 0.0; // Accumulated optical depth (Rayleigh)
        float od_m = 0.0; // Accumulated optical depth (Mie)
        float od_o = 0.0; // Accumulated optical depth (Ozone)

        for (int i = 0; i < PRIMARY_STEPS; i++) {
            vec3 pos = ray_origin + ray_dir * (t_start + (float(i) + 0.5) * step_size);
            float alt = length(pos) - u_planet_radius;

            float density_r = exp(-alt / u_h_rayleigh) * step_size;
            float density_m = exp(-alt / u_h_mie) * step_size;
            float density_o = ozone_density(alt) * step_size;
    
            od_r += density_r;
            od_m += density_m;
            od_o += density_o;

            // March toward the sun to compute transmittance.
            vec2 light_hit = ray_sphere(pos, u_sun_dir, u_atmo_radius);
            float light_step = light_hit.y / float(LIGHT_STEPS);
            float light_od_r = 0.0;
            float light_od_m = 0.0;
            float light_od_o = 0.0;

            for (int j = 0; j < LIGHT_STEPS; j++) {
                vec3 lp = pos + u_sun_dir * ((float(j) + 0.5) * light_step);
                float alt2 = length(lp) - u_planet_radius;
    
                light_od_r += exp(-alt2 / u_h_rayleigh) * light_step;
                light_od_m += exp(-alt2 / u_h_mie) * light_step;
                light_od_o += ozone_density(alt2) * light_step;
            }

            vec3 transmittance = exp(
                -(u_beta_rayleigh * (od_r + light_od_r) +
                  u_beta_mie * 1.1 * (od_m + light_od_m) +
                  u_beta_ozone * (od_o + light_od_o))
            );

            rayleigh_sum += density_r * transmittance;
            mie_sum += density_m * transmittance;
        }

        float cos_theta = dot(ray_dir, u_sun_dir);
        float phase_r = (3.0 / (16.0 * PI)) * (1.0 + cos_theta * cos_theta);
        float g2 = u_g * u_g;
        float phase_m = (3.0 / (8.0  * PI))
            * ((1.0 - g2) * (1.0 + cos_theta * cos_theta))
            / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * u_g * cos_theta, 1.5));

        return u_sun_intensity * (
            phase_r * u_beta_rayleigh * rayleigh_sum +
            phase_m * u_beta_mie * vec3(mie_sum)
        );
    }

    void main() {
        vec3 dir = normalize(v_tex_coord);
        vec3 color = scatter(dir);

        // Sun disc: limb darkening + atmospheric color + horizon clip.
        float sun_cos = dot(dir, u_sun_dir);
        float cos_disc = cos(u_sun_disc_angle);
        float disc_mask = smoothstep(cos_disc, cos_disc + 0.0001, sun_cos);
        float above_horizon = smoothstep(-0.001, 0.001, dir.y);

        // Limb darkening: I = 1 - u * (1 - sqrt(1 - r^2)), r=0 at center, r = 1 at edge.
        float r = sqrt((1.0 - sun_cos) / max(1.0 - cos_disc, 1e-6));
        float ld = 1.0 - 0.6 * (1.0 - sqrt(max(0.0, 1.0 - r * r)));

        // Transmittance colors the disc: white at noon, orange/red at sunset.
        color += disc_mask * above_horizon * ld * u_sun_intensity * sun_transmittance();

        o_frag_color = vec4(color, 1.0);
    }
`

HDR_VS :: GLSL_VERSION + `
    out vec2 v_uv;

    void main() {
        // Single large triangle that covers the entire screen — no VBO needed.
        vec2 pos[3] = vec2[](vec2(-1, -1), vec2(3, -1), vec2(-1, 3));
        vec2 uvs[3] = vec2[](vec2( 0,  0), vec2(2,  0), vec2( 0, 2));

        gl_Position = vec4(pos[gl_VertexID], 0.0, 1.0);
        v_uv = uvs[gl_VertexID];
    }
`

HDR_FS :: GLSL_VERSION + `
    in vec2 v_uv;

    out vec4 o_frag_color;

    uniform sampler2D u_hdr_buffer;
    uniform float u_exposure;

    // ACES filmic tone mapping (Krzysztof Narkowicz approximation).
    vec3 aces(vec3 x) {
        return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
    }

    void main() {
        vec3 hdr = texture(u_hdr_buffer, v_uv).rgb * u_exposure;
        o_frag_color = vec4(pow(aces(hdr), vec3(1.0 / 2.2)), 1.0);
    }
`

exposure: f32 = 1.0

setup_hdr_fbo :: proc(fbo, color_tex, depth_rbo: ^u32, width, height: i32) {
    if fbo^ != 0 {
        gl.DeleteFramebuffers(1, fbo)
        gl.DeleteTextures(1, color_tex)
        gl.DeleteRenderbuffers(1, depth_rbo)
    }

    gl.GenFramebuffers(1, fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo^)

    gl.GenTextures(1, color_tex)
    gl.BindTexture(gl.TEXTURE_2D, color_tex^)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, width, height, 0, gl.RGB, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, color_tex^, 0)

    gl.GenRenderbuffers(1, depth_rbo)
    gl.BindRenderbuffer(gl.RENDERBUFFER, depth_rbo^)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, width, height)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth_rbo^)

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

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

    hdr_pg, hdr_ok := gl.load_shaders_source(HDR_VS, HDR_FS); defer gl.DeleteProgram(hdr_pg)
    hdr_uf := gl.get_uniforms_from_program(hdr_pg); defer gl.destroy_uniforms(hdr_uf)

    if !hdr_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    hdr_vao: u32; gl.GenVertexArrays(1, &hdr_vao); defer gl.DeleteVertexArrays(1, &hdr_vao)

    hdr_fbo, hdr_color_tex, hdr_depth_rbo: u32
    setup_hdr_fbo(&hdr_fbo, &hdr_color_tex, &hdr_depth_rbo, viewport_x, viewport_y)
    defer {
        gl.DeleteFramebuffers(1, &hdr_fbo)
        gl.DeleteTextures(1, &hdr_color_tex)
        gl.DeleteRenderbuffers(1, &hdr_depth_rbo)
    }

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
                setup_hdr_fbo(&hdr_fbo, &hdr_color_tex, &hdr_depth_rbo, viewport_x, viewport_y)
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

        gl.BindFramebuffer(gl.FRAMEBUFFER, hdr_fbo)
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        // Draw meshes
        gl.BindVertexArray(main_vao)
        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(main_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3fv(main_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.Uniform3fv(main_uf["u_light_dir"].location, 1, &light.dir[0])
        gl.Uniform3fv(main_uf["u_light_color"].location, 1, &light.color[0])

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
        gl.Uniform3fv(skybox_uf["u_sun_dir"].location, 1, &light.dir[0])
        gl.Uniform1f(skybox_uf["u_sun_intensity"].location, atmosphere.sun_intensity)
        gl.Uniform1f(skybox_uf["u_sun_disc_angle"].location, atmosphere.sun_disc_angle)
        gl.Uniform1f(skybox_uf["u_planet_radius"].location, atmosphere.planet_radius)
        gl.Uniform1f(skybox_uf["u_atmo_radius"].location, atmosphere.atmo_radius)
        gl.Uniform1f(skybox_uf["u_h_rayleigh"].location, atmosphere.h_rayleigh)
        gl.Uniform1f(skybox_uf["u_h_mie"].location, atmosphere.h_mie)
        gl.Uniform3fv(skybox_uf["u_beta_rayleigh"].location, 1, &atmosphere.beta_rayleigh[0])
        gl.Uniform3fv(skybox_uf["u_beta_ozone"].location, 1, &atmosphere.beta_ozone[0])
        gl.Uniform1f(skybox_uf["u_beta_mie"].location, atmosphere.beta_mie)
        gl.Uniform1f(skybox_uf["u_g"].location, atmosphere.g)
        gl.BindVertexArray(skybox_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 14)

        gl.DepthFunc(gl.LESS)
        gl.Enable(gl.CULL_FACE)

        // HDR tone mapping pass
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)
        gl.UseProgram(hdr_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, hdr_color_tex)
        gl.Uniform1i(hdr_uf["u_hdr_buffer"].location, 0)
        gl.Uniform1f(hdr_uf["u_exposure"].location, exposure)
        gl.BindVertexArray(hdr_vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 3)
        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}
