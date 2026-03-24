package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Color Grading"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

COLOR_GRADING_VS :: b.LIGHTING_VS

COLOR_GRADING_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform float u_exposure;
    uniform int u_debug_buffer;
    uniform bool u_enable_pp;

    uniform float u_saturation;
    uniform float u_contrast;
    uniform vec3  u_lift;
    uniform float u_gamma;
    uniform vec3  u_gain;

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(color, 1.0);
            return;
        }

        // Tone mapping
        color = vec3(1.0) - exp(-color * u_exposure);

        // Color grading
        if (u_enable_pp) {
            // Saturation
            float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
            color = mix(vec3(lum), color, u_saturation);

            // Contrast (pivot at 0.5)
            color = (color - 0.5) * u_contrast + 0.5;

            // Lift / Gamma / Gain
            color = pow(max(color * u_gain + u_lift, 0.0), vec3(1.0 / u_gamma));
        }

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

    color_grading_pg, color_grading_ok := gl.load_shaders_source(COLOR_GRADING_VS, COLOR_GRADING_FS); defer gl.DeleteProgram(color_grading_pg)
    color_grading_uf := gl.get_uniforms_from_program(color_grading_pg); defer gl.destroy_uniforms(color_grading_uf)

    if !color_grading_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())
        return
    }

    enable_pp := true
    saturation := f32(1.2)
    contrast := f32(1.1)
    lift := glm.vec3{0.02, 0.01, 0.05}
    gamma := f32(0.9)
    gain := glm.vec3{1.1, 1.0, 0.9}

    property_index := 0
    property_names := []string{"Exposure", "Saturation", "Contrast", "Lift R", "Lift G", "Lift B", "Gamma", "Gain R", "Gain G", "Gain B"}
    property_ptrs := []^f32{&base.exposure, &saturation, &contrast, &lift.x, &lift.y, &lift.z, &gamma, &gain.x, &gain.y, &gain.z}
    property_steps := []f32{0.1, 0.05, 0.05, 0.01, 0.01, 0.01, 0.05, 0.05, 0.05, 0.05}

    fmt.printf("Property: %s = %.2f\n", property_names[property_index], property_ptrs[property_index]^)

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
            case .KEY_DOWN:
                if event.key.scancode == sdl.Scancode.ESCAPE {
                    _ = sdl.SetWindowRelativeMouseMode(window, !sdl.GetWindowRelativeMouseMode(window))
                }

                if event.key.scancode >= sdl.Scancode._1 && event.key.scancode <= sdl.Scancode._6 {
                    base.debug_buffer = i32(event.key.scancode - sdl.Scancode._1)
                }

                if event.key.scancode == sdl.Scancode.TAB {
                    enable_pp = !enable_pp
                }

                if event.key.scancode == sdl.Scancode.R {
                    base.exposure = 1.0
                    saturation = 1.2
                    contrast = 1.1
                    lift = {0.02, 0.01, 0.05}
                    gamma = 0.9
                    gain = {1.1, 1.0, 0.9}
                    fmt.printf("Reset\n")
                }

                if event.key.scancode == sdl.Scancode.LEFT {
                    property_index = (property_index - 1 + len(property_names)) % len(property_names)

                    fmt.printf("Property: %s = %.2f\n", property_names[property_index], property_ptrs[property_index]^)
                }

                if event.key.scancode == sdl.Scancode.RIGHT {
                    property_index = (property_index + 1) % len(property_names)

                    fmt.printf("Property: %s = %.2f\n", property_names[property_index], property_ptrs[property_index]^)
                }

                if event.key.scancode == sdl.Scancode.UP {
                    property_ptrs[property_index]^ += property_steps[property_index]

                    fmt.printf("Property: %s = %.2f\n", property_names[property_index], property_ptrs[property_index]^)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    property_ptrs[property_index]^ -= property_steps[property_index]

                    fmt.printf("Property: %s = %.2f\n", property_names[property_index], property_ptrs[property_index]^)
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

        // Color Grading
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)

        gl.UseProgram(color_grading_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(color_grading_uf["u_scene_color"].location, 0)
        gl.Uniform1f(color_grading_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(color_grading_uf["u_debug_buffer"].location, base.debug_buffer)
        gl.Uniform1i(color_grading_uf["u_enable_pp"].location, i32(enable_pp))
        gl.Uniform1f(color_grading_uf["u_saturation"].location, saturation)
        gl.Uniform1f(color_grading_uf["u_contrast"].location, contrast)
        gl.Uniform3fv(color_grading_uf["u_lift"].location, 1, &lift[0])
        gl.Uniform1f(color_grading_uf["u_gamma"].location, gamma)
        gl.Uniform3fv(color_grading_uf["u_gain"].location, 1, &gain[0])

        gl.BindVertexArray(base.quad_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}