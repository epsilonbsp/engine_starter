package example

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Color LUT"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

LUT_SIZE :: 32

COLOR_LUT_VS :: b.LIGHTING_VS

COLOR_LUT_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform sampler3D u_lut;
    uniform float u_lut_size;
    uniform float u_exposure;
    uniform int u_debug_buffer;
    uniform bool u_enable_pp;

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(color, 1.0);

            return;
        }

        // Tone mapping
        color = vec3(1.0) - exp(-color * u_exposure);

        // Color LUT - half-texel correction keeps sampling within valid texel centers
        if (u_enable_pp) {
            float scale = (u_lut_size - 1.0) / u_lut_size;
            float offset = 0.5 / u_lut_size;

            color = texture(u_lut, color * scale + offset).rgb;
        }

        // Gamma correction
        color = pow(color, vec3(1.0 / 2.2));

        o_frag_color = vec4(color, 1.0);
    }
`

// Warm cinematic grade applied to each LUT entry
grade :: proc(r, g, b: f32) -> (f32, f32, f32) {
    // S-curve contrast
    r := r * r * (3.0 - 2.0 * r)
    g := g * g * (3.0 - 2.0 * g)
    b := b * b * (3.0 - 2.0 * b)

    // Warm tint: boost reds, pull blues
    r = r * 1.08
    g = g * 1.02
    b = b * 0.88

    // Teal shadow lift
    r = r + 0.01 * (1.0 - r) * (1.0 - r)
    g = g + 0.03 * (1.0 - g) * (1.0 - g)
    b = b + 0.04 * (1.0 - b) * (1.0 - b)

    return clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1)
}

create_lut :: proc() -> u32 {
    data := make([]u8, LUT_SIZE * LUT_SIZE * LUT_SIZE * 3)
    defer delete(data)

    for bi in 0 ..< LUT_SIZE {
        for gi in 0 ..< LUT_SIZE {
            for ri in 0 ..< LUT_SIZE {
                rf := f32(ri) / f32(LUT_SIZE - 1)
                gf := f32(gi) / f32(LUT_SIZE - 1)
                bf := f32(bi) / f32(LUT_SIZE - 1)

                ro, go, bo := grade(rf, gf, bf)

                idx := (bi * LUT_SIZE * LUT_SIZE + gi * LUT_SIZE + ri) * 3
                data[idx + 0] = u8(ro * 255)
                data[idx + 1] = u8(go * 255)
                data[idx + 2] = u8(bo * 255)
            }
        }
    }

    lut: u32
    gl.GenTextures(1, &lut)
    gl.BindTexture(gl.TEXTURE_3D, lut)
    gl.TexImage3D(gl.TEXTURE_3D, 0, gl.RGB8, LUT_SIZE, LUT_SIZE, LUT_SIZE, 0, gl.RGB, gl.UNSIGNED_BYTE, &data[0])
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)

    return lut
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

    color_lut_pg, color_lut_ok := gl.load_shaders_source(COLOR_LUT_VS, COLOR_LUT_FS); defer gl.DeleteProgram(color_lut_pg)
    color_lut_uf := gl.get_uniforms_from_program(color_lut_pg); defer gl.destroy_uniforms(color_lut_uf)
    assert(color_lut_ok, "ERROR: Failed to compile program")

    lut_tex := create_lut(); defer gl.DeleteTextures(1, &lut_tex)

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

                if event.key.scancode == sdl.Scancode.DOWN {
                    base.exposure -= 0.1

                    fmt.printf("Exposure: %.1f\n", base.exposure)
                }

                if event.key.scancode == sdl.Scancode.UP {
                    base.exposure += 0.1

                    fmt.printf("Exposure: %.1f\n", base.exposure)
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

        // Color LUT
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)

        gl.UseProgram(color_lut_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(color_lut_uf["u_scene_color"].location, 0)
        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_3D, lut_tex)
        gl.Uniform1i(color_lut_uf["u_lut"].location, 1)
        gl.Uniform1f(color_lut_uf["u_lut_size"].location, LUT_SIZE)
        gl.Uniform1f(color_lut_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(color_lut_uf["u_debug_buffer"].location, base.debug_buffer)
        gl.Uniform1i(color_lut_uf["u_enable_pp"].location, i32(enable_pp))

        gl.BindVertexArray(base.quad_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}
