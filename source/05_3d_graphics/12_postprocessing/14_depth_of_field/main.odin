package example

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

import b "../_base"

WINDOW_TITLE :: "Depth of Field"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

DOF_VS :: b.LIGHTING_VS

GAUSSIAN_WEIGHTS :: `
    const float weights[5] = float[](0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162);
`

// Pass 1: horizontal blur, HDR scene -> ping-pong
BLUR_H_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_tex;

` + GAUSSIAN_WEIGHTS + `

    void main() {
        float step_x = 1.0 / float(textureSize(u_tex, 0).x);

        vec3 color = texture(u_tex, v_tex_coord).rgb * weights[0];

        for (int i = 1; i < 5; i++) {
            color += texture(u_tex, v_tex_coord + vec2(float(i) * step_x, 0.0)).rgb * weights[i];
            color += texture(u_tex, v_tex_coord - vec2(float(i) * step_x, 0.0)).rgb * weights[i];
        }

        o_frag_color = vec4(color, 1.0);
    }
`

// Pass 2: vertical blur, ping-pong -> blurred buffer
BLUR_V_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_tex;

` + GAUSSIAN_WEIGHTS + `

    void main() {
        float step_y = 1.0 / float(textureSize(u_tex, 0).y);

        vec3 color = texture(u_tex, v_tex_coord).rgb * weights[0];

        for (int i = 1; i < 5; i++) {
            color += texture(u_tex, v_tex_coord + vec2(0.0, float(i) * step_y)).rgb * weights[i];
            color += texture(u_tex, v_tex_coord - vec2(0.0, float(i) * step_y)).rgb * weights[i];
        }

        o_frag_color = vec4(color, 1.0);
    }
`

// Pass 3: composite sharp + blurred by CoC, tone map, gamma
DOF_FS :: b.GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform sampler2D u_blurred;
    uniform sampler2D u_depth;
    uniform float u_near;
    uniform float u_far;
    uniform float u_focus_dist;
    uniform float u_focus_range;
    uniform float u_exposure;
    uniform int u_debug_buffer;

    float linear_depth(float d) {
        float z = d * 2.0 - 1.0;

        return (2.0 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));
    }

    void main() {
        vec3 sharp = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(sharp, 1.0);

            return;
        }

        vec3 blurred = texture(u_blurred, v_tex_coord).rgb;

        float depth = linear_depth(texture(u_depth, v_tex_coord).r);
        float coc = clamp(abs(depth - u_focus_dist) / u_focus_range, 0.0, 1.0); // Circle of confusion

        vec3 color = mix(sharp, blurred, coc);

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

    blur_h_pg, blur_h_ok := gl.load_shaders_source(DOF_VS, BLUR_H_FS); defer gl.DeleteProgram(blur_h_pg)
    blur_h_uf := gl.get_uniforms_from_program(blur_h_pg); defer gl.destroy_uniforms(blur_h_uf)

    if !blur_h_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    blur_v_pg, blur_v_ok := gl.load_shaders_source(DOF_VS, BLUR_V_FS); defer gl.DeleteProgram(blur_v_pg)
    blur_v_uf := gl.get_uniforms_from_program(blur_v_pg); defer gl.destroy_uniforms(blur_v_uf)

    if !blur_v_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    dof_pg, dof_ok := gl.load_shaders_source(DOF_VS, DOF_FS); defer gl.DeleteProgram(dof_pg)
    dof_uf := gl.get_uniforms_from_program(dof_pg); defer gl.destroy_uniforms(dof_uf)

    if !dof_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    pp: RenderTarget
    init_render_target(&pp, viewport_x, viewport_y); defer destroy_render_target(&pp)

    blurred: RenderTarget
    init_render_target(&blurred, viewport_x, viewport_y); defer destroy_render_target(&blurred)

    enable_pp := true
    focus_dist := f32(2.0)
    focus_range := f32(4.0)

    fmt.printf("Focus dist: %.1f  Focus range: %.1f\n", focus_dist, focus_range)

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
                resize_render_target(&blurred, viewport_x, viewport_y)
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
                    focus_dist += 0.5
    
                    fmt.printf("Focus dist: %.1f  Focus range: %.1f\n", focus_dist, focus_range)
                }

                if event.key.scancode == sdl.Scancode.DOWN {
                    focus_dist = max(1.0, focus_dist - 0.5)

                    fmt.printf("Focus dist: %.1f  Focus range: %.1f\n", focus_dist, focus_range)
                }

                if event.key.scancode == sdl.Scancode.RIGHT {
                    focus_range += 0.5
    
                    fmt.printf("Focus dist: %.1f  Focus range: %.1f\n", focus_dist, focus_range)
                }

                if event.key.scancode == sdl.Scancode.LEFT {
                    focus_range = max(0.5, focus_range - 0.5)

                    fmt.printf("Focus dist: %.1f  Focus range: %.1f\n", focus_dist, focus_range)
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

        // Horizontal blur: HDR scene -> pp
        gl.BindFramebuffer(gl.FRAMEBUFFER, pp.fbo)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.UseProgram(blur_h_pg)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(blur_h_uf["u_tex"].location, 0)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        // Vertical blur: pp -> blurred
        gl.BindFramebuffer(gl.FRAMEBUFFER, blurred.fbo)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.UseProgram(blur_v_pg)
        gl.BindTexture(gl.TEXTURE_2D, pp.tex)
        gl.Uniform1i(blur_v_uf["u_tex"].location, 0)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        // DOF composite: sharp + blurred + depth -> screen
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.UseProgram(dof_pg)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, base.scene_buffer.color_tex)
        gl.Uniform1i(dof_uf["u_scene_color"].location, 0)
    
        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, blurred.tex)
        gl.Uniform1i(dof_uf["u_blurred"].location, 1)
    
        gl.ActiveTexture(gl.TEXTURE2)
        gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.depth_tex)
        gl.Uniform1i(dof_uf["u_depth"].location, 2)
    
        gl.Uniform1f(dof_uf["u_near"].location, camera.near)
        gl.Uniform1f(dof_uf["u_far"].location, camera.far)
        gl.Uniform1f(dof_uf["u_focus_dist"].location, enable_pp ? focus_dist : 0.0)
        gl.Uniform1f(dof_uf["u_focus_range"].location, enable_pp ? focus_range : 1e9)
        gl.Uniform1f(dof_uf["u_exposure"].location, base.exposure)
        gl.Uniform1i(dof_uf["u_debug_buffer"].location, base.debug_buffer)

        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        gl.Enable(gl.DEPTH_TEST)

        sdl.GL_SwapWindow(window)
    }
}
