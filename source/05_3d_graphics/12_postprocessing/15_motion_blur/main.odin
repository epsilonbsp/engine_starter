package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Motion Blur"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

MOTION_BLUR_VS :: b.LIGHTING_VS

// Pass 1: reconstruct velocity from depth + prev/curr VP, sample along it
MOTION_BLUR_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform sampler2D u_depth;
    uniform mat4 u_curr_vp_inv;
    uniform mat4 u_prev_vp;
    uniform float u_blur_scale;
    uniform int u_num_samples;
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
            // Reconstruct world position from depth
            float depth = texture(u_depth, v_tex_coord).r * 2.0 - 1.0;
            vec4 clip_pos = vec4(v_tex_coord * 2.0 - 1.0, depth, 1.0);
            vec4 world_pos = u_curr_vp_inv * clip_pos;
            world_pos /= world_pos.w;

            // Project with previous VP to get previous screen position
            vec4 prev_clip = u_prev_vp * world_pos;
            prev_clip /= prev_clip.w;
            vec2 prev_uv = prev_clip.xy * 0.5 + 0.5;

            // Screen-space velocity
            vec2 velocity = (v_tex_coord - prev_uv) * u_blur_scale;

            // Sample along velocity
            color = vec3(0.0);

            for (int i = 0; i < u_num_samples; i++) {
                float t = float(i) / float(u_num_samples - 1) - 0.5;
                color += texture(u_scene_color, v_tex_coord + velocity * t).rgb;
            }

            color /= float(u_num_samples);
        }

        // Tone mapping
        color = vec3(1.0) - exp(-color * u_exposure);

        // Gamma correction
        color = pow(max(color, 0.0), vec3(1.0 / 2.2));

        o_frag_color = vec4(color, 1.0);
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

    base: b.Base

    if !b.init_base(&base, viewport_x, viewport_y) {

        return
    }

    defer b.destroy_base(&base)

    mb_pg, mb_ok := gl.load_shaders_source(MOTION_BLUR_VS, MOTION_BLUR_FS); defer gl.DeleteProgram(mb_pg)
    mb_uf := gl.get_uniforms_from_program(mb_pg); defer gl.destroy_uniforms(mb_uf)

    if !mb_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    enable_pp := true
    num_samples := i32(16)
    blur_scale := f32(5.0)

    prev_vp: glm.mat4

    camera: b.Camera
    b.init_camera(&camera, position = {6, 6, 6})
    b.point_camera_at(&camera, {})

    camera_movement := b.Camera_Movement{move_speed = 100, yaw_speed = 0.002, pitch_speed = 0.002}

    CAM_DRAG :: f32(8.0)
    cam_velocity: glm.vec3

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
                    blur_scale += 0.5
                    fmt.printf("Blur scale: %.1f\n", blur_scale)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    blur_scale = max(0.5, blur_scale - 0.5)
                    fmt.printf("Blur scale: %.1f\n", blur_scale)
                }
            case .MOUSE_MOTION:
                if sdl.GetWindowRelativeMouseMode(window) {
                    b.rotate_camera(&camera, event.motion.xrel * camera_movement.yaw_speed, event.motion.yrel * camera_movement.pitch_speed, 0)
                }
            }
        }

        if sdl.GetWindowRelativeMouseMode(window) {
            input := glm.vec3{
                f32(i32(key_state[sdl.Scancode.D]) - i32(key_state[sdl.Scancode.A])),
                0,
                f32(i32(key_state[sdl.Scancode.W]) - i32(key_state[sdl.Scancode.S])),
            }

            cam_velocity += input * camera_movement.move_speed * time_delta
            cam_velocity *= glm.exp(-CAM_DRAG * time_delta)

            b.move_camera(&camera, cam_velocity * time_delta)
        }

        b.compute_camera_projection(&camera, f32(viewport_x) / f32(viewport_y))
        b.compute_camera_view(&camera)

        curr_vp := camera.projection * camera.view
        curr_vp_inv := glm.inverse(curr_vp)

        // Base
        b.base_render_scene(&base, &camera, viewport_x, viewport_y)

        // Motion blur: scene + depth -> screen
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)
        gl.BindVertexArray(base.quad_vao)

        gl.UseProgram(mb_pg)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(mb_uf["u_scene_color"].location, 0)

        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.depth_tex)
        gl.Uniform1i(mb_uf["u_depth"].location, 1)

        gl.UniformMatrix4fv(mb_uf["u_curr_vp_inv"].location, 1, false, &curr_vp_inv[0][0])
        gl.UniformMatrix4fv(mb_uf["u_prev_vp"].location, 1, false, &prev_vp[0][0])
        gl.Uniform1f(mb_uf["u_blur_scale"].location, blur_scale)
        gl.Uniform1i(mb_uf["u_num_samples"].location, num_samples)
        gl.Uniform1f(mb_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(mb_uf["u_debug_buffer"].location, base.debug_buffer)
        gl.Uniform1i(mb_uf["u_enable_pp"].location, i32(enable_pp))

        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        prev_vp = curr_vp

        sdl.GL_SwapWindow(window)
    }
}
