package example

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Glare"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

GLARE_VS :: b.LIGHTING_VS

// Pass 1: extract bright areas above threshold -> bright buffer
BRIGHT_PASS_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_tex;
    uniform float u_threshold;

    void main() {
        vec3 color = texture(u_tex, v_tex_coord).rgb;
        float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));

        // Soft knee: smoothly extract highlights above threshold
        color *= max(lum - u_threshold, 0.0) / max(lum, 0.001);

        o_frag_color = vec4(color, 1.0);
    }
`

// Pass 2: streak filter along one direction with exponential falloff
// Run 4 times (0, 45, 90, 135 degrees) and accumulate additively -> 8-pointed star
STREAK_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_tex;
    uniform vec2 u_direction;
    uniform float u_streak_length;

    const int NUM_SAMPLES = 8;

    void main() {
        vec2 step = u_direction * u_streak_length / vec2(textureSize(u_tex, 0));

        vec3 color = vec3(0.0);
        float total_weight = 0.0;

        for (int i = 0; i < NUM_SAMPLES; i++) {
            float weight = exp(-float(i) * 0.4);

            color += texture(u_tex, v_tex_coord + step * float(i)).rgb * weight;
            color += texture(u_tex, v_tex_coord - step * float(i)).rgb * weight;
            total_weight += weight * 2.0;
        }

        o_frag_color = vec4(color / total_weight, 1.0);
    }
`

// Pass 3: additive composite scene + glare, tone map, gamma
GLARE_COMPOSITE_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform sampler2D u_glare;
    uniform float u_glare_strength;
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
            color += texture(u_glare, v_tex_coord).rgb * u_glare_strength;
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
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, width, height, 0, gl.RGB, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
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

// 4 streak directions -> 8-pointed star
STREAK_DIRS := [4][2]f32{
    {1.0, 0.0},
    {0.0, 1.0},
    {0.7071068, 0.7071068},
    {0.7071068, -0.7071068},
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

    bright_pg, bright_ok := gl.load_shaders_source(GLARE_VS, BRIGHT_PASS_FS); defer gl.DeleteProgram(bright_pg)
    bright_uf := gl.get_uniforms_from_program(bright_pg); defer gl.destroy_uniforms(bright_uf)
    assert(bright_ok, "ERROR: Failed to compile program")

    streak_pg, streak_ok := gl.load_shaders_source(GLARE_VS, STREAK_FS); defer gl.DeleteProgram(streak_pg)
    streak_uf := gl.get_uniforms_from_program(streak_pg); defer gl.destroy_uniforms(streak_uf)
    assert(streak_ok, "ERROR: Failed to compile program")

    composite_pg, composite_ok := gl.load_shaders_source(GLARE_VS, GLARE_COMPOSITE_FS); defer gl.DeleteProgram(composite_pg)
    composite_uf := gl.get_uniforms_from_program(composite_pg); defer gl.destroy_uniforms(composite_uf)
    assert(composite_ok, "ERROR: Failed to compile program")

    // bright_rt: bright-pass output (source for streak passes)
    bright_rt: RenderTarget
    init_render_target(&bright_rt, viewport_x, viewport_y); defer destroy_render_target(&bright_rt)

    // glare_rt: accumulated streaks from all directions
    glare_rt: RenderTarget
    init_render_target(&glare_rt, viewport_x, viewport_y); defer destroy_render_target(&glare_rt)

    enable_pp := true
    glare_threshold := f32(0.5)
    glare_strength := f32(1.0)
    streak_length := f32(4.0)

    fmt.printf("Threshold: %.2f; Strength: %.2f; Length: %.1f\n", glare_threshold, glare_strength, streak_length)

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
                resize_render_target(&bright_rt, viewport_x, viewport_y)
                resize_render_target(&glare_rt, viewport_x, viewport_y)
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
                    glare_threshold += 0.1

                    fmt.printf("Threshold: %.2f; Strength: %.2f; Length: %.1f\n", glare_threshold, glare_strength, streak_length)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    glare_threshold = max(0.0, glare_threshold - 0.1)

                    fmt.printf("Threshold: %.2f; Strength: %.2f; Length: %.1f\n", glare_threshold, glare_strength, streak_length)
                }

                if event.key.scancode == sdl.Scancode.RIGHT {
                    streak_length += 1.0

                    fmt.printf("Threshold: %.2f; Strength: %.2f; Length: %.1f\n", glare_threshold, glare_strength, streak_length)
                }

                if event.key.scancode == sdl.Scancode.LEFT {
                    streak_length = max(1.0, streak_length - 1.0)

                    fmt.printf("Threshold: %.2f; Strength: %.2f; Length: %.1f\n", glare_threshold, glare_strength, streak_length)
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
        gl.ActiveTexture(gl.TEXTURE0)

        if enable_pp {
            // Bright pass: scene -> bright_rt
            gl.BindFramebuffer(gl.FRAMEBUFFER, bright_rt.fbo)
            gl.Clear(gl.COLOR_BUFFER_BIT)
            gl.UseProgram(bright_pg)
            gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
            gl.Uniform1i(bright_uf["u_tex"].location, 0)
            gl.Uniform1f(bright_uf["u_threshold"].location, glare_threshold)
            gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

            // Streak passes: bright_rt -> glare_rt (additive, 4 directions)
            gl.BindFramebuffer(gl.FRAMEBUFFER, glare_rt.fbo)
            gl.Clear(gl.COLOR_BUFFER_BIT)
            gl.Enable(gl.BLEND)
            gl.BlendFunc(gl.ONE, gl.ONE)
            gl.UseProgram(streak_pg)
            gl.BindTexture(gl.TEXTURE_2D, bright_rt.tex)
            gl.Uniform1i(streak_uf["u_tex"].location, 0)
            gl.Uniform1f(streak_uf["u_streak_length"].location, streak_length)

            for dir in STREAK_DIRS {
                gl.Uniform2f(streak_uf["u_direction"].location, dir[0], dir[1])
                gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)
            }

            gl.Disable(gl.BLEND)
        }

        // Composite: scene + glare -> screen
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.UseProgram(composite_pg)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(composite_uf["u_scene_color"].location, 0)

        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, glare_rt.tex)
        gl.Uniform1i(composite_uf["u_glare"].location, 1)

        gl.Uniform1f(composite_uf["u_glare_strength"].location, glare_strength)
        gl.Uniform1f(composite_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(composite_uf["u_debug_buffer"].location, base.debug_buffer)
        gl.Uniform1i(composite_uf["u_enable_pp"].location, i32(enable_pp))

        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}
