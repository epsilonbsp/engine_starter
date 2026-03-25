package example

import "core:fmt"
import "core:image/png"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Reflection"
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
    color: glm.vec3,
    ambient_strength: f32,
    diffuse_strength: f32,
    specular_strength: f32,
    specular_shine: f32,
    reflection_strength: f32,
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
}

light := Light{
    glm.normalize(glm.vec3{-0.26395932, 0.5059853, 0.82116038}),
    {0.98, 0.73, 0.56}
}

meshes := []Mesh {
    {{-8, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{1, 1, 1}, 0.02, 1.0, 0.5, 32.0, 0.00}},
    {{-4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{1, 1, 1}, 0.02, 1.0, 0.5, 32.0, 0.25}},
    {{ 0, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{1, 1, 1}, 0.02, 1.0, 0.5, 32.0, 0.50}},
    {{ 4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{1, 1, 1}, 0.02, 1.0, 0.5, 32.0, 0.75}},
    {{ 8, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{1, 1, 1}, 0.02, 1.0, 0.5, 32.0, 1.00}},
}

mesh_vertices := []Vertex {
    // Left
    {{-0.5, -0.5, -0.5}, {-1, 0, 0}, {0, 1}},
    {{-0.5, -0.5,  0.5}, {-1, 0, 0}, {1, 1}},
    {{-0.5,  0.5,  0.5}, {-1, 0, 0}, {1, 0}},
    {{-0.5,  0.5, -0.5}, {-1, 0, 0}, {0, 0}},

    // Right
    {{ 0.5, -0.5,  0.5}, {1, 0, 0}, {0, 1}},
    {{ 0.5, -0.5, -0.5}, {1, 0, 0}, {1, 1}},
    {{ 0.5,  0.5, -0.5}, {1, 0, 0}, {1, 0}},
    {{ 0.5,  0.5,  0.5}, {1, 0, 0}, {0, 0}},

    // Bottom
    {{-0.5, -0.5, -0.5}, {0, -1, 0}, {0, 1}},
    {{ 0.5, -0.5, -0.5}, {0, -1, 0}, {1, 1}},
    {{ 0.5, -0.5,  0.5}, {0, -1, 0}, {1, 0}},
    {{-0.5, -0.5,  0.5}, {0, -1, 0}, {0, 0}},

    // Top
    {{-0.5,  0.5,  0.5}, {0, 1, 0}, {0, 1}},
    {{ 0.5,  0.5,  0.5}, {0, 1, 0}, {1, 1}},
    {{ 0.5,  0.5, -0.5}, {0, 1, 0}, {1, 0}},
    {{-0.5,  0.5, -0.5}, {0, 1, 0}, {0, 0}},

    // Back
    {{ 0.5, -0.5, -0.5}, {0, 0, -1}, {0, 1}},
    {{-0.5, -0.5, -0.5}, {0, 0, -1}, {1, 1}},
    {{-0.5,  0.5, -0.5}, {0, 0, -1}, {1, 0}},
    {{ 0.5,  0.5, -0.5}, {0, 0, -1}, {0, 0}},

    // Front
    {{-0.5, -0.5,  0.5}, {0, 0, 1}, {0, 1}},
    {{ 0.5, -0.5,  0.5}, {0, 0, 1}, {1, 1}},
    {{ 0.5,  0.5,  0.5}, {0, 0, 1}, {1, 0}},
    {{-0.5,  0.5,  0.5}, {0, 0, 1}, {0, 0}},
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

    out vec3 v_normal;
    out vec2 v_tex_coord;
    out vec3 v_world_pos;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;
    uniform mat3 u_normal_matrix;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        gl_Position = u_projection * u_view * world_pos;
        v_normal = u_normal_matrix * i_normal;
        v_tex_coord = i_tex_coord;
        v_world_pos = world_pos.xyz;
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_normal;
    in vec2 v_tex_coord;
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
    uniform float u_mat_reflection_strength;
    uniform samplerCube u_skybox_tex;
    uniform sampler2D u_diffuse_tex;
    uniform sampler2D u_reflection_tex;

    void main() {
        vec3 normal = normalize(v_normal);
        vec3 view_dir = normalize(u_view_pos - v_world_pos);
        vec3 half_dir = normalize(u_light_dir + view_dir);

        vec3 color = u_mat_color * texture(u_diffuse_tex, v_tex_coord).rgb;
        vec3 reflection_strength = u_mat_reflection_strength * texture(u_reflection_tex, v_tex_coord).rgb;

        vec3 ambient = color * u_light_color * u_mat_ambient_strength;
        vec3 diffuse = color * u_light_color * max(dot(normal, u_light_dir), 0.0) * u_mat_diffuse_strength;
        vec3 specular = u_light_color * pow(max(dot(normal, half_dir), 0.0), u_mat_specular_shine) * u_mat_specular_strength;
        vec3 reflection = texture(u_skybox_tex, reflect(-view_dir, normal)).rgb * reflection_strength;

        vec3 result = ambient + diffuse + specular + reflection;

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

    uniform samplerCube u_skybox_tex;

    void main() {
        o_frag_color = texture(u_skybox_tex, v_tex_coord);
    }
`

make_transform :: proc(translation: glm.vec3, rotation: glm.vec3, scale: glm.vec3) -> glm.mat4 {
    qx := glm.quatAxisAngle({1, 0, 0}, rotation.x)
    qy := glm.quatAxisAngle({0, 1, 0}, rotation.y)
    qz := glm.quatAxisAngle({0, 0, 1}, rotation.z)
    q := qz * qy * qx

    return glm.mat4Translate(translation) * glm.mat4FromQuat(q) * glm.mat4Scale(scale)
}

load_texture_from_bytes :: proc(bytes: []u8) -> u32 {
    image, _ := png.load_from_bytes(bytes, {.alpha_add_if_missing}); defer png.destroy(image)

    tex: u32; gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D, tex)

    w, h := i32(image.width), i32(image.height)

    if image.depth == 16 {
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16, w, h, 0, gl.RGBA, gl.UNSIGNED_SHORT, &image.pixels.buf[0])
    } else {
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, &image.pixels.buf[0])
    }

    gl.GenerateMipmap(gl.TEXTURE_2D)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)

    return tex
}

load_cubemap :: proc() -> u32 {
    // Source: https://freestylized.com/skybox/sky_36/
    face_data := [6][]byte {
        #load("cubemap/sky_px.png"),
        #load("cubemap/sky_nx.png"),
        #load("cubemap/sky_py.png"),
        #load("cubemap/sky_ny.png"),
        #load("cubemap/sky_pz.png"),
        #load("cubemap/sky_nz.png"),
    }

    tex: u32
    gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, tex)

    for i in 0 ..< len(face_data) {
        img, _ := png.load_from_bytes(face_data[i], {.alpha_add_if_missing})
        defer png.destroy(img)

        target := u32(gl.TEXTURE_CUBE_MAP_POSITIVE_X) + u32(i)
        gl.TexImage2D(target, 0, gl.RGBA8, i32(img.width), i32(img.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, &img.pixels.buf[0])
    }

    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)

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
    assert(main_ok, "ERROR: Failed to compile program")

    skybox_pg, skybox_ok := gl.load_shaders_source(SKYBOX_VS, SKYBOX_FS); defer gl.DeleteProgram(skybox_pg)
    skybox_uf := gl.get_uniforms_from_program(skybox_pg); defer gl.destroy_uniforms(skybox_uf);
    assert(skybox_ok, "ERROR: Failed to compile program")

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

    main_ibo: u32; gl.GenBuffers(1, &main_ibo); defer gl.DeleteBuffers(1, &main_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, mesh_index_count * size_of(mesh_indices[0]), &mesh_indices[0], gl.STATIC_DRAW)

    skybox_vao: u32; gl.GenVertexArrays(1, &skybox_vao); defer gl.DeleteVertexArrays(1, &skybox_vao)
    gl.BindVertexArray(skybox_vao)

    skybox_tex := load_cubemap(); defer gl.DeleteTextures(1, &skybox_tex)
    diffuse_tex := load_texture_from_bytes(#load("textures/diffuse.png")); defer gl.DeleteTextures(1, &diffuse_tex)
    reflection_tex := load_texture_from_bytes(#load("textures/reflection.png")); defer gl.DeleteTextures(1, &reflection_tex)

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

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, skybox_tex)
        gl.Uniform1i(main_uf["u_skybox_tex"].location, 0)

        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, diffuse_tex)
        gl.Uniform1i(main_uf["u_diffuse_tex"].location, 1)

        gl.ActiveTexture(gl.TEXTURE2)
        gl.BindTexture(gl.TEXTURE_2D, reflection_tex)
        gl.Uniform1i(main_uf["u_reflection_tex"].location, 2)

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
            gl.Uniform1f(main_uf["u_mat_reflection_strength"].location, mesh.material.reflection_strength)

            gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
        }

        // Draw skybox
        gl.DepthFunc(gl.LEQUAL)
        gl.Disable(gl.CULL_FACE)

        gl.UseProgram(skybox_pg)
        gl.UniformMatrix4fv(skybox_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(skybox_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, skybox_tex)
        gl.Uniform1i(skybox_uf["u_skybox_tex"].location, 0)
        gl.BindVertexArray(skybox_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 14)

        gl.DepthFunc(gl.LESS)
        gl.Enable(gl.CULL_FACE)

        sdl.GL_SwapWindow(window)
    }
}
