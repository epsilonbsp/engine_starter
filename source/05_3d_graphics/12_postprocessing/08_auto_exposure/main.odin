package example

import "core:fmt"
import "core:math"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Auto Exposure"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

ADAPTATION_SPEED :: f32(3.0)
KEY_VALUE :: f32(0.18)
EXPOSURE_MIN :: f32(0.1)
EXPOSURE_MAX :: f32(10.0)

LUMINANCE_VS :: b.LIGHTING_VS

LUMINANCE_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out float o_luminance;

    uniform sampler2D u_scene_color;

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;
        float lum = max(dot(color, vec3(0.2126, 0.7152, 0.0722)), 0.0001);

        o_luminance = log(lum);
    }
`

AUTO_EXPOSURE_VS :: b.LIGHTING_VS

AUTO_EXPOSURE_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform float u_exposure;
    uniform int u_debug_buffer;
    uniform bool u_enable_pp;

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(color, 1.0);

            return;
        }

        // Exposure
        if (u_enable_pp) {
            color = vec3(1.0) - exp(-color * u_exposure);
        }

        // Gamma correction
        color = pow(color, vec3(1.0 / 2.2));

        o_frag_color = vec4(color, 1.0);
    }
`

init_lum_buffer :: proc(lum_tex: ^u32, lum_fbo: ^u32, width: i32, height: i32) {
    gl.GenTextures(1, lum_tex)
    gl.BindTexture(gl.TEXTURE_2D, lum_tex^)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R16F, width, height, 0, gl.RED, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    gl.GenFramebuffers(1, lum_fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, lum_fbo^)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, lum_tex^, 0)
}

destroy_lum_buffer :: proc(lum_tex: ^u32, lum_fbo: ^u32) {
    gl.DeleteTextures(1, lum_tex)
    gl.DeleteFramebuffers(1, lum_fbo)
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

    lum_pg, lum_ok := gl.load_shaders_source(LUMINANCE_VS, LUMINANCE_FS); defer gl.DeleteProgram(lum_pg)
    lum_uf := gl.get_uniforms_from_program(lum_pg); defer gl.destroy_uniforms(lum_uf)

    if !lum_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())
        return
    }

    auto_exposure_pg, auto_exposure_ok := gl.load_shaders_source(AUTO_EXPOSURE_VS, AUTO_EXPOSURE_FS); defer gl.DeleteProgram(auto_exposure_pg)
    auto_exposure_uf := gl.get_uniforms_from_program(auto_exposure_pg); defer gl.destroy_uniforms(auto_exposure_uf)

    if !auto_exposure_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())
        return
    }

    lum_tex, lum_fbo: u32
    init_lum_buffer(&lum_tex, &lum_fbo, viewport_x, viewport_y)
    defer destroy_lum_buffer(&lum_tex, &lum_fbo)

    base.sky_irradiance_strength = 0.03

    enable_pp := true

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
                destroy_lum_buffer(&lum_tex, &lum_fbo)
                init_lum_buffer(&lum_tex, &lum_fbo, viewport_x, viewport_y)
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
            // Luminance pass: render log-luminance of scene into lum_tex
            gl.Viewport(0, 0, viewport_x, viewport_y)
            gl.BindFramebuffer(gl.FRAMEBUFFER, lum_fbo)
            gl.UseProgram(lum_pg)
            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
            gl.Uniform1i(lum_uf["u_scene_color"].location, 0)
            gl.BindVertexArray(base.quad_vao)
            gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

            // Downsample to 1x1 via mipmaps
            gl.BindTexture(gl.TEXTURE_2D, lum_tex)
            gl.GenerateMipmap(gl.TEXTURE_2D)

            // Read average log-luminance from smallest mip
            max_lod := i32(math.log2(f32(max(viewport_x, viewport_y))))
            log_avg_lum: f32
            gl.GetTexImage(gl.TEXTURE_2D, max_lod, gl.RED, gl.FLOAT, &log_avg_lum)

            // Convert log-average back to linear, compute target exposure
            avg_lum := math.exp(log_avg_lum)
            target_exposure := clamp(KEY_VALUE / avg_lum, EXPOSURE_MIN, EXPOSURE_MAX)

            // Smooth adaptation (exponential)
            t := 1.0 - math.exp(-ADAPTATION_SPEED * time_delta)
            base.exposure += (target_exposure - base.exposure) * t
        }

        // Auto Exposure pass
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)

        gl.UseProgram(auto_exposure_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(auto_exposure_uf["u_scene_color"].location, 0)
        gl.Uniform1f(auto_exposure_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(auto_exposure_uf["u_debug_buffer"].location, base.debug_buffer)
        gl.Uniform1i(auto_exposure_uf["u_enable_pp"].location, i32(enable_pp))

        gl.BindVertexArray(base.quad_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}