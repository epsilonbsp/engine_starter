package example

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Tone Mapping"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

TONE_MAPPING_VS :: b.LIGHTING_VS

TONE_MAPPING_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform float u_exposure;
    uniform int u_operator;
    uniform int u_debug_buffer;

    vec3 aces(vec3 x) {
        const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;

        return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
    }

    vec3 filmic(vec3 x) {
        vec3 x_clamped = max(vec3(0.0), x - 0.004);
        vec3 result = (x_clamped * (6.2 * x_clamped + 0.5)) / (x_clamped * (6.2 * x_clamped + 1.7) + 0.06);

        return pow(result, vec3(2.2));
    }

    vec3 lottes(vec3 x) {
        const vec3 a = vec3(1.6), d = vec3(0.977), hdr_max = vec3(8.0), mid_in = vec3(0.18), mid_out = vec3(0.267);
        const vec3 b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out) / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
        const vec3 c = (pow(hdr_max, a * d) * pow(mid_in, a) - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out) / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);

        return pow(x, a) / (pow(x, a * d) * b + c);
    }

    vec3 reinhard(vec3 x) {
        return x / (1.0 + x);
    }

    vec3 reinhard2(vec3 x) {
        const float l_white = 4.0;

        return (x * (1.0 + x / (l_white * l_white))) / (1.0 + x);
    }

    vec3 uchimura(vec3 x) {
        const float p = 1.0, a = 1.0, m = 0.22, l = 0.4, c = 1.33, b = 0.0;
        float l0 = ((p - m) * l) / a;
        float s0 = m + l0, s1 = m + a * l0;
        float c2 = (a * p) / (p - s1), cp = -c2 / p;
        vec3 w0 = vec3(1.0 - smoothstep(0.0, m, x));
        vec3 w2 = vec3(step(m + l0, x));
        vec3 w1 = vec3(1.0 - w0 - w2);
        vec3 seg_t = m * pow(x / m, vec3(c)) + b;
        vec3 seg_s = p - (p - s1) * exp(cp * (x - s0));
        vec3 seg_l = m + a * (x - m);

        return seg_t * w0 + seg_l * w1 + seg_s * w2;
    }

    vec3 uncharted2_partial(vec3 x) {
        float a = 0.15, b = 0.50, c = 0.10, d = 0.20, e = 0.02, f = 0.30;

        return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f;
    }

    vec3 uncharted2(vec3 x) {
        const float w = 11.2;
        vec3 curr = uncharted2_partial(2.0 * x);
        vec3 white_scale = 1.0 / uncharted2_partial(vec3(w));

        return curr * white_scale;
    }

    vec3 unreal(vec3 x) {
        return x / (x + 0.155) * 1.019;
    }

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(color, 1.0);

            return;
        }

        color *= u_exposure;

        if (u_operator == 0) { color = aces(color); }
        else if (u_operator == 1) { color = filmic(color); }
        else if (u_operator == 2) { color = lottes(color); }
        else if (u_operator == 3) { color = reinhard(color); }
        else if (u_operator == 4) { color = reinhard2(color); }
        else if (u_operator == 5) { color = uchimura(color); }
        else if (u_operator == 6) { color = uncharted2(color); }
        else if (u_operator == 7) { color = unreal(color); }

        // filmic already bakes in gamma
        if (u_operator != 1) { color = pow(color, vec3(1.0 / 2.2)); }

        o_frag_color = vec4(color, 1.0);
    }
`

OPERATOR_NAMES := [8]string{
    "ACES",
    "Filmic",
    "Lottes",
    "Reinhard",
    "Reinhard 2",
    "Uchimura",
    "Uncharted 2",
    "Unreal"
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

    tone_mapping_pg, tone_mapping_ok := gl.load_shaders_source(TONE_MAPPING_VS, TONE_MAPPING_FS); defer gl.DeleteProgram(tone_mapping_pg)
    tone_mapping_uf := gl.get_uniforms_from_program(tone_mapping_pg); defer gl.destroy_uniforms(tone_mapping_uf)

    if !tone_mapping_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())
        return
    }

    tone_operator := 0

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

                if event.key.scancode == sdl.Scancode.LEFT {
                    tone_operator = (tone_operator - 1 + len(OPERATOR_NAMES)) % len(OPERATOR_NAMES)
                    fmt.printf("Operator: %s\n", OPERATOR_NAMES[tone_operator])
                }

                if event.key.scancode == sdl.Scancode.RIGHT {
                    tone_operator = (tone_operator + 1) % len(OPERATOR_NAMES)
                    fmt.printf("Operator: %s\n", OPERATOR_NAMES[tone_operator])
                }

                if event.key.scancode == sdl.Scancode.UP {
                    base.exposure += 0.1
                    fmt.printf("Exposure: %.1f\n", base.exposure)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    base.exposure -= 0.1
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

        // Tone Mapping
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)

        gl.UseProgram(tone_mapping_pg)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(tone_mapping_uf["u_scene_color"].location, 0)
        gl.Uniform1f(tone_mapping_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(tone_mapping_uf["u_operator"].location, i32(tone_operator))
        gl.Uniform1i(tone_mapping_uf["u_debug_buffer"].location, base.debug_buffer)

        gl.BindVertexArray(base.quad_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}