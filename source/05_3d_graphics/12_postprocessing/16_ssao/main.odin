package example

import "core:fmt"
import "core:math/rand"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "SSAO"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

NUM_SAMPLES :: 32

SSAO_VS :: b.LIGHTING_VS

// Pass 1: compute occlusion from world pos + normals -> SSAO buffer
SSAO_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_position;
    uniform sampler2D u_normal;
    uniform sampler2D u_noise;
    uniform vec3 u_samples[32];
    uniform mat4 u_view;
    uniform mat4 u_projection;
    uniform float u_radius;
    uniform float u_bias;

    void main() {
        vec3 frag_pos = (u_view * vec4(texture(u_position, v_tex_coord).xyz, 1.0)).xyz;
        vec3 normal = normalize(mat3(u_view) * texture(u_normal, v_tex_coord).xyz);

        // Tile the 4x4 noise texture across the screen
        vec2 noise_scale = vec2(textureSize(u_position, 0)) / 4.0;
        vec3 rand_vec = normalize(texture(u_noise, v_tex_coord * noise_scale).xyz);

        // Build TBN to orient hemisphere along normal
        vec3 tangent = normalize(rand_vec - normal * dot(rand_vec, normal));
        vec3 bitangent = cross(normal, tangent);
        mat3 tbn = mat3(tangent, bitangent, normal);

        float occlusion = 0.0;

        for (int i = 0; i < 32; i++) {
            vec3 sample_pos = frag_pos + tbn * u_samples[i] * u_radius;

            // Project sample to get its screen UV
            vec4 offset = u_projection * vec4(sample_pos, 1.0);
            offset.xyz /= offset.w;
            vec2 sample_uv = offset.xy * 0.5 + 0.5;

            // Get view-space depth at sample UV
            float sample_depth = (u_view * vec4(texture(u_position, sample_uv).xyz, 1.0)).z;

            // Fade contribution for samples outside the radius
            float range_check = smoothstep(0.0, 1.0, u_radius / abs(frag_pos.z - sample_depth));
            occlusion += (sample_depth >= sample_pos.z + u_bias ? 1.0 : 0.0) * range_check;
        }

        occlusion = 1.0 - occlusion / 32.0;

        o_frag_color = vec4(vec3(occlusion), 1.0);
    }
`

// Pass 2: blur SSAO + apply to scene + tone map + gamma
COMPOSITE_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform sampler2D u_ssao;
    uniform float u_ssao_strength;
    uniform float u_exposure;
    uniform int u_debug_buffer;
    uniform bool u_enable_pp;

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(color, 1.0);

            return;
        }

        if (u_enable_pp) {
            // 3x3 box blur on SSAO to reduce noise
            vec2 texel = 1.0 / vec2(textureSize(u_ssao, 0));
            float occlusion = 0.0;

            for (int x = -1; x <= 1; x++) {
                for (int y = -1; y <= 1; y++) {
                    occlusion += texture(u_ssao, v_tex_coord + vec2(x, y) * texel).r;
                }
            }

            occlusion /= 9.0;

            color *= mix(1.0, occlusion, u_ssao_strength);
        }

        // Tone mapping
        color = vec3(1.0) - exp(-color * u_exposure);

        // Gamma correction
        color = pow(max(color, 0.0), vec3(1.0 / 2.2));

        o_frag_color = vec4(color, 1.0);
    }
`

RenderTarget :: struct {
    fbo: u32,
    tex: u32,
}

init_render_target :: proc(rt: ^RenderTarget, width: i32, height: i32) {
    gl.GenTextures(1, &rt.tex)
    gl.BindTexture(gl.TEXTURE_2D, rt.tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R16F, width, height, 0, gl.RED, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    gl.GenFramebuffers(1, &rt.fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, rt.fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, rt.tex, 0)
}

destroy_render_target :: proc(rt: ^RenderTarget) {
    gl.DeleteTextures(1, &rt.tex)
    gl.DeleteFramebuffers(1, &rt.fbo)
}

resize_render_target :: proc(rt: ^RenderTarget, width: i32, height: i32) {
    destroy_render_target(rt)
    init_render_target(rt, width, height)
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

    base: b.Base
    b.init_base(&base, viewport_x, viewport_y)
    defer b.destroy_base(&base)

    ssao_pg, ssao_ok := gl.load_shaders_source(SSAO_VS, SSAO_FS); defer gl.DeleteProgram(ssao_pg)
    ssao_uf := gl.get_uniforms_from_program(ssao_pg); defer gl.destroy_uniforms(ssao_uf)
    assert(ssao_ok, "ERROR: Failed to compile program")

    composite_pg, composite_ok := gl.load_shaders_source(SSAO_VS, COMPOSITE_FS); defer gl.DeleteProgram(composite_pg)
    composite_uf := gl.get_uniforms_from_program(composite_pg); defer gl.destroy_uniforms(composite_uf)
    assert(composite_ok, "ERROR: Failed to compile program")

    // Generate hemisphere kernel
    kernel: [NUM_SAMPLES]glm.vec3

    for i in 0 ..< NUM_SAMPLES {
        sample := glm.normalize(glm.vec3{
            rand.float32_range(-1, 1),
            rand.float32_range(-1, 1),
            rand.float32_range(0, 1),
        })
        sample *= rand.float32_range(0, 1)

        // Accelerate towards origin so more samples cluster near the fragment
        scale := f32(i) / f32(NUM_SAMPLES)
        scale = 0.1 + (1.0 - 0.1) * scale * scale
        kernel[i] = sample * scale
    }

    // Upload kernel samples once (they don't change per frame)
    gl.UseProgram(ssao_pg)

    for i in 0 ..< NUM_SAMPLES {
        loc := gl.GetUniformLocation(ssao_pg, fmt.ctprintf("u_samples[%d]", i))
        gl.Uniform3f(loc, kernel[i].x, kernel[i].y, kernel[i].z)
    }

    // Generate 4x4 noise texture for hemisphere rotation
    noise_data: [16]glm.vec3

    for i in 0 ..< 16 {
        noise_data[i] = glm.vec3{
            rand.float32_range(-1, 1),
            rand.float32_range(-1, 1),
            0,
        }
    }

    noise_tex: u32
    gl.GenTextures(1, &noise_tex)
    gl.BindTexture(gl.TEXTURE_2D, noise_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, 4, 4, 0, gl.RGB, gl.FLOAT, raw_data(noise_data[:]))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
    defer gl.DeleteTextures(1, &noise_tex)

    ssao_rt: RenderTarget
    init_render_target(&ssao_rt, viewport_x, viewport_y); defer destroy_render_target(&ssao_rt)

    enable_pp := true
    ssao_radius := f32(0.5)
    ssao_bias := f32(0.025)
    ssao_strength := f32(1.0)

    fmt.printf("Radius: %.2f; Strength: %.2f\n", ssao_radius, ssao_strength)

    camera: b.Camera
    b.init_camera(&camera, position = {6, 6, 6})
    b.point_camera_at(&camera, {})

    camera_movement := b.Camera_Movement{move_speed = 5, yaw_speed = 0.002, pitch_speed = 0.002}

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
                b.resize_base(&base, viewport_x, viewport_y)
                resize_render_target(&ssao_rt, viewport_x, viewport_y)
            case .KEY_DOWN:
                if event.key.scancode == sdl.Scancode.ESCAPE {
                    _ = sdl.SetWindowRelativeMouseMode(window, !sdl.GetWindowRelativeMouseMode(window))
                }

                if event.key.scancode >= sdl.Scancode._1 && event.key.scancode <= sdl.Scancode._6 {
                    base.debug_buffer = i32(event.key.scancode - sdl.Scancode._1)
                }

                if event.key.scancode == sdl.Scancode.LSHIFT {
                    enable_pp = !enable_pp
                }

                if event.key.scancode == sdl.Scancode.UP {
                    ssao_radius += 0.05
                    fmt.printf("Radius: %.2f; Strength: %.2f\n", ssao_radius, ssao_strength)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    ssao_radius = max(0.05, ssao_radius - 0.05)
                    fmt.printf("Radius: %.2f; Strength: %.2f\n", ssao_radius, ssao_strength)
                }

                if event.key.scancode == sdl.Scancode.RIGHT {
                    ssao_strength += 0.1
                    fmt.printf("Radius: %.2f; Strength: %.2f\n", ssao_radius, ssao_strength)
                }

                if event.key.scancode == sdl.Scancode.LEFT {
                    ssao_strength = max(0.0, ssao_strength - 0.1)
                    fmt.printf("Radius: %.2f; Strength: %.2f\n", ssao_radius, ssao_strength)
                }
            case .MOUSE_MOTION:
                if sdl.GetWindowRelativeMouseMode(window) {
                    b.rotate_camera(&camera, event.motion.xrel * camera_movement.yaw_speed, event.motion.yrel * camera_movement.pitch_speed, 0)
                }
            }
        }

        if sdl.GetWindowRelativeMouseMode(window) {
            b.input_fly_camera(
                &camera,
                {key_state[sdl.Scancode.A], key_state[sdl.Scancode.D], key_state[sdl.Scancode.S], key_state[sdl.Scancode.W]},
                time_delta * camera_movement.move_speed,
            )
        }

        b.compute_camera_projection(&camera, f32(viewport_x) / f32(viewport_y))
        b.compute_camera_view(&camera)

        // Base
        b.base_render_scene(&base, &camera, viewport_x, viewport_y)

        gl.BindVertexArray(base.quad_vao)
        gl.Disable(gl.DEPTH_TEST)

        // SSAO pass: position + normal + noise -> ssao_rt
        gl.BindFramebuffer(gl.FRAMEBUFFER, ssao_rt.fbo)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.UseProgram(ssao_pg)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.position_tex)
        gl.Uniform1i(ssao_uf["u_position"].location, 0)

        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.normal_tex)
        gl.Uniform1i(ssao_uf["u_normal"].location, 1)

        gl.ActiveTexture(gl.TEXTURE2)
        gl.BindTexture(gl.TEXTURE_2D, noise_tex)
        gl.Uniform1i(ssao_uf["u_noise"].location, 2)

        gl.UniformMatrix4fv(ssao_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.UniformMatrix4fv(ssao_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.Uniform1f(ssao_uf["u_radius"].location, ssao_radius)
        gl.Uniform1f(ssao_uf["u_bias"].location, ssao_bias)

        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        // Composite: scene + ssao -> screen
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.UseProgram(composite_pg)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(composite_uf["u_scene_color"].location, 0)

        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, ssao_rt.tex)
        gl.Uniform1i(composite_uf["u_ssao"].location, 1)

        gl.Uniform1f(composite_uf["u_ssao_strength"].location, ssao_strength)
        gl.Uniform1f(composite_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(composite_uf["u_debug_buffer"].location, base.debug_buffer)
        gl.Uniform1i(composite_uf["u_enable_pp"].location, i32(enable_pp))

        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}
