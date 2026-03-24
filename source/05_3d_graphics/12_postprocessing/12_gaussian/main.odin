package example

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Gaussian"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

GAUSSIAN_VS :: b.LIGHTING_VS

GAUSSIAN_WEIGHTS :: `
    const float weights[5] = float[](0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162);
`

// Pass 1: horizontal blur, HDR scene -> ping-pong
BLUR_H_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_tex;
    uniform float u_blur_radius;
    uniform int u_debug_buffer;

` + GAUSSIAN_WEIGHTS + `

    void main() {
        if (u_debug_buffer != 0) {
            o_frag_color = vec4(texture(u_tex, v_tex_coord).rgb, 1.0);

            return;
        }

        float step_x = u_blur_radius / float(textureSize(u_tex, 0).x);

        vec3 color = texture(u_tex, v_tex_coord).rgb * weights[0];

        for (int i = 1; i < 5; i++) {
            color += texture(u_tex, v_tex_coord + vec2(float(i) * step_x, 0.0)).rgb * weights[i];
            color += texture(u_tex, v_tex_coord - vec2(float(i) * step_x, 0.0)).rgb * weights[i];
        }

        o_frag_color = vec4(color, 1.0);
    }
`

// Pass 2: vertical blur, ping-pong -> scene buffer (overwrites with blurred HDR)
BLUR_V_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_tex;
    uniform float u_blur_radius;
    uniform int u_debug_buffer;

` + GAUSSIAN_WEIGHTS + `

    void main() {
        if (u_debug_buffer != 0) {
            o_frag_color = vec4(texture(u_tex, v_tex_coord).rgb, 1.0);

            return;
        }

        float step_y = u_blur_radius / float(textureSize(u_tex, 0).y);

        vec3 color = texture(u_tex, v_tex_coord).rgb * weights[0];

        for (int i = 1; i < 5; i++) {
            color += texture(u_tex, v_tex_coord + vec2(0.0, float(i) * step_y)).rgb * weights[i];
            color += texture(u_tex, v_tex_coord - vec2(0.0, float(i) * step_y)).rgb * weights[i];
        }

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

    if !b.init_base(&base, viewport_x, viewport_y) {

        return
    }

    defer b.destroy_base(&base)

    blur_h_pg, blur_h_ok := gl.load_shaders_source(GAUSSIAN_VS, BLUR_H_FS); defer gl.DeleteProgram(blur_h_pg)
    blur_h_uf := gl.get_uniforms_from_program(blur_h_pg); defer gl.destroy_uniforms(blur_h_uf)

    if !blur_h_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    blur_v_pg, blur_v_ok := gl.load_shaders_source(GAUSSIAN_VS, BLUR_V_FS); defer gl.DeleteProgram(blur_v_pg)
    blur_v_uf := gl.get_uniforms_from_program(blur_v_pg); defer gl.destroy_uniforms(blur_v_uf)

    if !blur_v_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    pp: RenderTarget
    init_render_target(&pp, viewport_x, viewport_y); defer destroy_render_target(&pp)

    enable_pp := true
    blur_radius := f32(1.0)

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
                resize_render_target(&pp, viewport_x, viewport_y)
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
                    blur_radius += 0.5

                    fmt.printf("Blur radius: %.1f\n", blur_radius)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    blur_radius = max(0.5, blur_radius - 0.5)

                    fmt.printf("Blur radius: %.1f\n", blur_radius)
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

        if enable_pp {
            gl.BindVertexArray(base.quad_vao)
            gl.Disable(gl.DEPTH_TEST)
            gl.ActiveTexture(gl.TEXTURE0)

            // Horizontal blur: HDR scene -> ping-pong
            gl.BindFramebuffer(gl.FRAMEBUFFER, pp.fbo)
            gl.Clear(gl.COLOR_BUFFER_BIT)
            gl.UseProgram(blur_h_pg)
            gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
            gl.Uniform1i(blur_h_uf["u_tex"].location, 0)
            gl.Uniform1f(blur_h_uf["u_blur_radius"].location, blur_radius)
            gl.Uniform1i(blur_h_uf["u_debug_buffer"].location, base.debug_buffer)
            gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

            // Vertical blur: ping-pong -> scene buffer (overwrites with blurred HDR)
            gl.BindFramebuffer(gl.FRAMEBUFFER, base.scene_buffer.fbo)
            gl.Clear(gl.COLOR_BUFFER_BIT)
            gl.UseProgram(blur_v_pg)
            gl.BindTexture(gl.TEXTURE_2D, pp.tex)
            gl.Uniform1i(blur_v_uf["u_tex"].location, 0)
            gl.Uniform1f(blur_v_uf["u_blur_radius"].location, blur_radius)
            gl.Uniform1i(blur_v_uf["u_debug_buffer"].location, base.debug_buffer)
            gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

            gl.Enable(gl.DEPTH_TEST)
        }

        // Tone map: scene buffer (blurred or original) -> screen
        b.base_tonemap(&base, base.scene_buffer.color_tex)

        sdl.GL_SwapWindow(window)
    }
}
