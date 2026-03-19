package example

import "core:fmt"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import rand "core:math/rand"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Scissor Test"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

RECTS_CAP :: 64

Rect :: struct {
    position: glm.vec2,
    size: glm.vec2,
    color: glm.vec3,
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

    viewport_x, viewport_y: i32; sdl.GetWindowSize(window, &viewport_x, &viewport_y)

    rects: [RECTS_CAP]Rect
    rects_len := 0

    drag_start: glm.vec2
    drag_curr: glm.vec2
    dragging: bool

    loop: for {
        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
            case .KEY_DOWN:
                if event.key.scancode == sdl.Scancode.R {
                    rects_len = 0
                }
            case .MOUSE_BUTTON_DOWN:
                drag_start = {event.button.x, event.button.y}
                drag_curr = drag_start
                dragging = true
            case .MOUSE_MOTION:
                if dragging {
                    drag_curr = {event.motion.x, event.motion.y}
                }
            case .MOUSE_BUTTON_UP:
                if dragging {
                    x := min(drag_start.x, drag_curr.x)
                    y := min(drag_start.y, drag_curr.y)
                    w := abs(drag_curr.x - drag_start.x)
                    h := abs(drag_curr.y - drag_start.y)

                    if w > 2 && h > 2 {
                        rects[rects_len % RECTS_CAP] = {
                            {x, y},
                            {w, h},
                            {rand.float32(), rand.float32(), rand.float32()}
                        }

                        rects_len += 1
                    }
                }

                dragging = false
            }
        }

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.5, 0.5, 0.5, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.Enable(gl.SCISSOR_TEST)

        for i in 0 ..< min(rects_len, RECTS_CAP) {
            r := rects[i]
            gl_y := i32(f32(viewport_y) - r.position.y - r.size.y)

            gl.Scissor(i32(r.position.x), gl_y, i32(r.size.x), i32(r.size.y))
            gl.ClearColor(r.color.r, r.color.g, r.color.b, 1)
            gl.Clear(gl.COLOR_BUFFER_BIT)
        }

        if dragging {
            x := min(drag_start.x, drag_curr.x)
            y := min(drag_start.y, drag_curr.y)
            w := abs(drag_curr.x - drag_start.x)
            h := abs(drag_curr.y - drag_start.y)
            gl_y := i32(f32(viewport_y) - y - h)

            gl.Scissor(i32(x), gl_y, i32(w), i32(h))
            gl.ClearColor(1, 1, 1, 1)
            gl.Clear(gl.COLOR_BUFFER_BIT)
        }

        gl.Disable(gl.SCISSOR_TEST)

        sdl.GL_SwapWindow(window)
    }
}
