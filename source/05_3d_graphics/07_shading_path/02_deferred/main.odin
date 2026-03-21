package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Deferred"
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

Light_Locs :: struct {
    position: i32,
    color: i32,
    constant: i32,
    linear: i32,
    quadratic: i32,
}

GBuffer :: struct {
    fbo: u32,
    position_tex: u32,
    normal_tex: u32,
    albedo_tex: u32,
    material_tex: u32,
    depth_rbo: u32,
}

LIGHTS_CAP :: 4

lights := [LIGHTS_CAP]Light {
    {color = {1.0, 0.5, 0.3}, constant = 1.0, linear = 0.09, quadratic = 0.032},
    {color = {0.3, 0.6, 1.0}, constant = 1.0, linear = 0.09, quadratic = 0.032},
    {color = {0.3, 1.0, 0.4}, constant = 1.0, linear = 0.09, quadratic = 0.032},
    {color = {1.0, 1.0, 0.3}, constant = 1.0, linear = 0.09, quadratic = 0.032},
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

GBUFFER_VS :: GLSL_VERSION + `
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

GBUFFER_FS :: GLSL_VERSION + `
    in vec3 v_normal;
    in vec3 v_world_pos;

    layout(location = 0) out vec3 o_position;
    layout(location = 1) out vec3 o_normal;
    layout(location = 2) out vec3 o_albedo;
    layout(location = 3) out vec4 o_material;

    uniform vec3 u_mat_color;
    uniform float u_mat_ambient_strength;
    uniform float u_mat_diffuse_strength;
    uniform float u_mat_specular_strength;
    uniform float u_mat_specular_shine;

    void main() {
        o_position = v_world_pos;
        o_normal = normalize(v_normal);
        o_albedo = u_mat_color;
        o_material = vec4(u_mat_ambient_strength, u_mat_diffuse_strength, u_mat_specular_strength, u_mat_specular_shine);
    }
`

LIGHTING_VS :: GLSL_VERSION + `
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

LIGHTING_FS :: GLSL_VERSION + `
    #define LIGHTS_CAP 4

    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    struct Light {
        vec3 position;
        vec3 color;
        float constant;
        float linear;
        float quadratic;
    };

    uniform sampler2D u_g_position;
    uniform sampler2D u_g_normal;
    uniform sampler2D u_g_albedo;
    uniform sampler2D u_g_material;
    uniform vec3 u_view_pos;
    uniform Light u_lights[LIGHTS_CAP];
    uniform int u_debug_buffer;

    void main() {
        vec3 world_pos = texture(u_g_position, v_tex_coord).rgb;
        vec3 normal = texture(u_g_normal, v_tex_coord).rgb;
        vec3 albedo = texture(u_g_albedo, v_tex_coord).rgb;
        vec4 material = texture(u_g_material, v_tex_coord);

        if (u_debug_buffer == 1) { o_frag_color = vec4(world_pos, 1.0); return; }
        if (u_debug_buffer == 2) { o_frag_color = vec4(normal * 0.5 + 0.5, 1.0); return; }
        if (u_debug_buffer == 3) { o_frag_color = vec4(albedo, 1.0); return; }
        if (u_debug_buffer == 4) { o_frag_color = vec4(material.rgb, 1.0); return; }

        float ambient_strength = material.r;
        float diffuse_strength = material.g;
        float specular_strength = material.b;
        float specular_shine = material.a;

        vec3 view_dir = normalize(u_view_pos - world_pos);
        vec3 result = vec3(0.0);

        for (int i = 0; i < LIGHTS_CAP; i++) {
            vec3 light_dir = normalize(u_lights[i].position - world_pos);
            vec3 half_dir = normalize(light_dir + view_dir);

            float distance = length(u_lights[i].position - world_pos);
            float attenuation = 1.0 / (u_lights[i].constant + u_lights[i].linear * distance + u_lights[i].quadratic * distance * distance);

            vec3 ambient = albedo * u_lights[i].color * ambient_strength;
            vec3 diffuse = albedo * u_lights[i].color * max(dot(normal, light_dir), 0.0) * diffuse_strength;
            vec3 specular = u_lights[i].color * pow(max(dot(normal, half_dir), 0.0), specular_shine) * specular_strength;

            result += ambient + (diffuse + specular) * attenuation;
        }

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

make_transform :: proc(translation: glm.vec3, rotation: glm.vec3, scale: glm.vec3) -> glm.mat4 {
    qx := glm.quatAxisAngle({1, 0, 0}, rotation.x)
    qy := glm.quatAxisAngle({0, 1, 0}, rotation.y)
    qz := glm.quatAxisAngle({0, 0, 1}, rotation.z)
    q := qz * qy * qx

    return glm.mat4Translate(translation) * glm.mat4FromQuat(q) * glm.mat4Scale(scale)
}

init_gbuffer :: proc(gbuffer: ^GBuffer, width: i32, height: i32) {
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

resize_gbuffer :: proc(gbuffer: ^GBuffer, width: i32, height: i32) {
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
    time_curr := u64(sdl.GetTicks())
    time_last: u64
    time_delta: f32

    gbuffer_pg, gbuffer_ok := gl.load_shaders_source(GBUFFER_VS, GBUFFER_FS); defer gl.DeleteProgram(gbuffer_pg)
    gbuffer_uf := gl.get_uniforms_from_program(gbuffer_pg); defer gl.destroy_uniforms(gbuffer_uf)

    if !gbuffer_ok {
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

    quad_vao: u32; gl.GenVertexArrays(1, &quad_vao); defer gl.DeleteVertexArrays(1, &quad_vao)

    gbuffer: GBuffer
    init_gbuffer(&gbuffer, viewport_x, viewport_y)
    defer destroy_gbuffer(&gbuffer)

    light_locs: [LIGHTS_CAP]Light_Locs

    for i in 0 ..< LIGHTS_CAP {
        light_locs[i] = {
            position = gl.GetUniformLocation(lighting_pg, fmt.ctprintf("u_lights[%d].position", i)),
            color = gl.GetUniformLocation(lighting_pg, fmt.ctprintf("u_lights[%d].color", i)),
            constant = gl.GetUniformLocation(lighting_pg, fmt.ctprintf("u_lights[%d].constant", i)),
            linear = gl.GetUniformLocation(lighting_pg, fmt.ctprintf("u_lights[%d].linear", i)),
            quadratic = gl.GetUniformLocation(lighting_pg, fmt.ctprintf("u_lights[%d].quadratic", i)),
        }
    }

    camera: Camera;
    init_camera(&camera, position = {6, 6, 6})
    point_camera_at(&camera, {})

    camera_movement := Camera_Movement{move_speed = 5, yaw_speed = 0.002, pitch_speed = 0.002}

    debug_buffer: i32 = 0

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
                resize_gbuffer(&gbuffer, viewport_x, viewport_y)
            case .KEY_DOWN:
                if event.key.scancode == sdl.Scancode.ESCAPE {
                    _ = sdl.SetWindowRelativeMouseMode(window, !sdl.GetWindowRelativeMouseMode(window))
                }

                if event.key.scancode >= sdl.Scancode._1 && event.key.scancode <= sdl.Scancode._5 {
                    debug_buffer = i32(event.key.scancode - sdl.Scancode._1)
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

        for i in 0 ..< LIGHTS_CAP {
            angle := time_seconds * 0.5 + f32(i) * glm.PI * 2.0 / LIGHTS_CAP
            lights[i].position = {glm.cos(angle) * 4, 2, glm.sin(angle) * 4}
        }

        // Geometry pass
        gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo)
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(gbuffer_pg)
        gl.UniformMatrix4fv(gbuffer_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(gbuffer_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.BindVertexArray(main_vao)

        for &mesh in meshes {
            model := make_transform(mesh.translation, mesh.rotation, mesh.scale)
            normal_matrix := glm.transpose(glm.inverse(glm.mat3(model)))

            gl.UniformMatrix4fv(gbuffer_uf["u_model"].location, 1, false, &model[0][0])
            gl.UniformMatrix3fv(gbuffer_uf["u_normal_matrix"].location, 1, false, &normal_matrix[0][0])
            gl.Uniform3fv(gbuffer_uf["u_mat_color"].location, 1, &mesh.material.color[0])
            gl.Uniform1f(gbuffer_uf["u_mat_ambient_strength"].location, mesh.material.ambient_strength)
            gl.Uniform1f(gbuffer_uf["u_mat_diffuse_strength"].location, mesh.material.diffuse_strength)
            gl.Uniform1f(gbuffer_uf["u_mat_specular_strength"].location, mesh.material.specular_strength)
            gl.Uniform1f(gbuffer_uf["u_mat_specular_shine"].location, mesh.material.specular_shine)
            gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
        }

        // Lighting pass
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

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
        gl.Uniform3fv(lighting_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.Uniform1i(lighting_uf["u_debug_buffer"].location, debug_buffer)

        for i in 0 ..< LIGHTS_CAP {
            gl.Uniform3fv(light_locs[i].position, 1, &lights[i].position[0])
            gl.Uniform3fv(light_locs[i].color, 1, &lights[i].color[0])
            gl.Uniform1f(light_locs[i].constant, lights[i].constant)
            gl.Uniform1f(light_locs[i].linear, lights[i].linear)
            gl.Uniform1f(light_locs[i].quadratic, lights[i].quadratic)
        }

        gl.BindVertexArray(quad_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        // Blit depth from gbuffer so light cubes depth-test correctly
        gl.BindFramebuffer(gl.READ_FRAMEBUFFER, gbuffer.fbo)
        gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
        gl.BlitFramebuffer(0, 0, viewport_x, viewport_y, 0, 0, viewport_x, viewport_y, gl.DEPTH_BUFFER_BIT, gl.NEAREST)
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

        // Draw light cubes (forward pass using blitted depth)
        gl.UseProgram(light_pg)
        gl.UniformMatrix4fv(light_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(light_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.BindVertexArray(main_vao)

        for i in 0 ..< LIGHTS_CAP {
            light_model := make_transform(lights[i].position, {}, {0.3, 0.3, 0.3})

            gl.UniformMatrix4fv(light_uf["u_model"].location, 1, false, &light_model[0][0])
            gl.Uniform3fv(light_uf["u_color"].location, 1, &lights[i].color[0])
            gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
        }

        sdl.GL_SwapWindow(window)
    }
}
