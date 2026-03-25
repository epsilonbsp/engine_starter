package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Fake Spheres"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

MESH_CAP :: 2048
MESH_POS_MIN :: f32(-512)
MESH_POS_MAX :: f32(512)
MESH_SCALE_MIN :: f32(4)
MESH_SCALE_MAX :: f32(32)

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
}

Mesh :: struct {
    translation: glm.vec3,
    rotation: glm.vec3,
    scale: glm.vec3,
    material: Material,
}

light := Light{
    glm.normalize(glm.vec3{1, 2, 3}),
    {1, 0.8, 0.6}
}

MAIN_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_translation;
    layout(location = 1) in vec3 i_scale;
    layout(location = 2) in vec3 i_color;
    layout(location = 3) in float i_ambient_strength;
    layout(location = 4) in float i_diffuse_strength;
    layout(location = 5) in float i_specular_strength;
    layout(location = 6) in float i_specular_shine;

    out vec3 v_color;
    out float v_ambient_strength;
    out float v_diffuse_strength;
    out float v_specular_strength;
    out float v_specular_shine;
    out vec3 v_frag_vs;
    flat out vec3 v_center_vs;
    flat out float v_radius;

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
        float radius = i_scale.x * 0.5;
        vec3 position = i_translation + POSITIONS[gl_VertexID] * radius;

        v_center_vs = (u_view * vec4(i_translation, 1.0)).xyz;
        v_frag_vs = (u_view * vec4(position, 1.0)).xyz;
        v_radius = radius;
        v_color = i_color;
        v_ambient_strength = i_ambient_strength;
        v_diffuse_strength = i_diffuse_strength;
        v_specular_strength = i_specular_strength;
        v_specular_shine = i_specular_shine;

        gl_Position = u_projection * vec4(v_frag_vs, 1.0);
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_color;
    in float v_ambient_strength;
    in float v_diffuse_strength;
    in float v_specular_strength;
    in float v_specular_shine;
    in vec3 v_frag_vs;
    flat in vec3 v_center_vs;
    flat in float v_radius;

    out vec4 o_frag_color;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;

    void main() {
        vec3 ray_dir = normalize(v_frag_vs);
        float b = dot(ray_dir, v_center_vs);
        float disc = b * b - dot(v_center_vs, v_center_vs) + v_radius * v_radius;

        if (disc < 0.0) {
            discard;
        }

        float t = b - sqrt(disc);
        vec3 hit_vs = t * ray_dir;
        vec4 clip_pos = u_projection * vec4(hit_vs, 1.0);

        gl_FragDepth = (clip_pos.z / clip_pos.w) * 0.5 + 0.5;

        mat3 cam_to_world = transpose(mat3(u_view));
        vec3 normal = cam_to_world * normalize(hit_vs - v_center_vs);
        vec3 view_dir = cam_to_world * normalize(-hit_vs);
        vec3 half_dir = normalize(u_light_dir + view_dir);

        vec3 ambient = v_color * u_light_color * v_ambient_strength;
        vec3 diffuse = v_color * u_light_color * max(dot(normal, u_light_dir), 0.0) * v_diffuse_strength;
        vec3 specular = u_light_color * pow(max(dot(normal, half_dir), 0.0), v_specular_shine) * v_specular_strength;

        vec3 result = ambient + diffuse + specular;

        o_frag_color = vec4(pow(result, vec3(1.0 / 2.2)), 1.0);
    }
`

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

    meshes: [MESH_CAP]Mesh

    for &mesh in meshes {
        p := rand.float32_range(MESH_POS_MIN, MESH_POS_MAX)
        s := rand.float32_range(MESH_SCALE_MIN, MESH_SCALE_MAX)

        mesh.translation = {rand.float32_range(MESH_POS_MIN, MESH_POS_MAX), rand.float32_range(MESH_POS_MIN, MESH_POS_MAX), p}
        mesh.scale = {s, s, s}
        mesh.material.color = {rand.float32(), rand.float32(), rand.float32()}
        mesh.material.ambient_strength = 0.02
        mesh.material.diffuse_strength = rand.float32()
        mesh.material.specular_strength = rand.float32()
        mesh.material.specular_shine = rand.float32_range(1, 256)
    }

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(meshes), &meshes, gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Mesh), offset_of(Mesh, translation))
    gl.VertexAttribDivisor(0, 1)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Mesh), offset_of(Mesh, scale))
    gl.VertexAttribDivisor(1, 1)

    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, size_of(Mesh), offset_of(Mesh, material) + offset_of(Material, color))
    gl.VertexAttribDivisor(2, 1)

    gl.EnableVertexAttribArray(3)
    gl.VertexAttribPointer(3, 1, gl.FLOAT, gl.FALSE, size_of(Mesh), offset_of(Mesh, material) + offset_of(Material, ambient_strength))
    gl.VertexAttribDivisor(3, 1)

    gl.EnableVertexAttribArray(4)
    gl.VertexAttribPointer(4, 1, gl.FLOAT, gl.FALSE, size_of(Mesh), offset_of(Mesh, material) + offset_of(Material, diffuse_strength))
    gl.VertexAttribDivisor(4, 1)

    gl.EnableVertexAttribArray(5)
    gl.VertexAttribPointer(5, 1, gl.FLOAT, gl.FALSE, size_of(Mesh), offset_of(Mesh, material) + offset_of(Material, specular_strength))
    gl.VertexAttribDivisor(5, 1)

    gl.EnableVertexAttribArray(6)
    gl.VertexAttribPointer(6, 1, gl.FLOAT, gl.FALSE, size_of(Mesh), offset_of(Mesh, material) + offset_of(Material, specular_shine))
    gl.VertexAttribDivisor(6, 1)

    camera: Camera
    init_camera(&camera, position = {2, 2, 2})
    point_camera_at(&camera, {})

    camera_movement := Camera_Movement{move_speed = 40, yaw_speed = 0.002, pitch_speed = 0.002}

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
        gl.Uniform3fv(main_uf["u_light_dir"].location, 1, &light.dir[0])
        gl.Uniform3fv(main_uf["u_light_color"].location, 1, &light.color[0])
        gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 14, MESH_CAP)

        sdl.GL_SwapWindow(window)
    }
}
