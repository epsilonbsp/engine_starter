package example

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Chromatic Aberration"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

CHROMATIC_ABERRATION_VS :: b.LIGHTING_VS

CHROMATIC_ABERRATION_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform float u_exposure;
    uniform int u_debug_buffer;
    uniform bool u_enable_pp;
    uniform float u_aberration_strength;

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(color, 1.0);

            return;
        }

        // Tone mapping
        color = vec3(1.0) - exp(-color * u_exposure);

        // Chromatic Aberration
        if (u_enable_pp) {
            vec2 dir = (v_tex_coord - 0.5) * u_aberration_strength;
            float r = texture(u_scene_color, v_tex_coord + dir).r;
            float g = texture(u_scene_color, v_tex_coord).g;
            float b = texture(u_scene_color, v_tex_coord - dir).b;

            color = vec3(1.0) - exp(-vec3(r, g, b) * u_exposure);
        }

        // Gamma correction
        color = pow(color, vec3(1.0 / 2.2));

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
    b.init_base(&base, viewport_x, viewport_y)
    defer b.destroy_base(&base)

    chromatic_aberration_pg, chromatic_aberration_ok := gl.load_shaders_source(CHROMATIC_ABERRATION_VS, CHROMATIC_ABERRATION_FS); defer gl.DeleteProgram(chromatic_aberration_pg)
    chromatic_aberration_uf := gl.get_uniforms_from_program(chromatic_aberration_pg); defer gl.destroy_uniforms(chromatic_aberration_uf);
    assert(chromatic_aberration_ok, "ERROR: Failed to compile program")

    enable_pp := true
    aberration_strength: f32 = 0.05

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

                if event.key.scancode == sdl.Scancode.LSHIFT {
                    enable_pp = !enable_pp
                }

                if event.key.scancode == sdl.Scancode.UP {
                    aberration_strength += 0.01

                    fmt.printf("Aberration strength: %.2f\n", aberration_strength)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    aberration_strength = max(0.0, aberration_strength - 0.01)

                    fmt.printf("Aberration strength: %.2f\n", aberration_strength)
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

        // Chromatic Aberration
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)

        gl.UseProgram(chromatic_aberration_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(chromatic_aberration_uf["u_scene_color"].location, 0)
        gl.Uniform1f(chromatic_aberration_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(chromatic_aberration_uf["u_debug_buffer"].location, base.debug_buffer)
        gl.Uniform1i(chromatic_aberration_uf["u_enable_pp"].location, i32(enable_pp))
        gl.Uniform1f(chromatic_aberration_uf["u_aberration_strength"].location, aberration_strength)

        gl.BindVertexArray(base.quad_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}
