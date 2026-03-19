package example

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"

WINDOW_TITLE :: "Input"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

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

    loop: for {
        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
            case .KEY_DOWN:
                fmt.printf(
                    "KEY_DOWN: key=%s, repeat=%t\n",
                    sdl.GetScancodeName(event.key.scancode), event.key.repeat
                )
            case .KEY_UP:
                fmt.printf(
                    "KEY_UP: key=%s, repeat=%t\n",
                    sdl.GetScancodeName(event.key.scancode), event.key.repeat
                )
            case .MOUSE_MOTION:
                fmt.printf(
                    "MOUSE_MOTION: x=%f, y=%f, xrel=%f, yrel=%f\n",
                    event.motion.x, event.motion.y, event.motion.xrel, event.motion.yrel
                )
            case .MOUSE_BUTTON_DOWN:
                fmt.printf(
                    "MOUSE_BUTTON_DOWN: button=%d, clicks=%d, x=%f, y=%f\n",
                    event.button.button, event.button.clicks, event.button.x, event.button.y
                )
            case .MOUSE_BUTTON_UP:
                fmt.printf(
                    "MOUSE_BUTTON_UP: button=%d, clicks=%d, x=%f, y=%f\n",
                    event.button.button, event.button.clicks, event.button.x, event.button.y
                )
            case .MOUSE_WHEEL:
                fmt.printf(
                    "MOUSE_WHEEL: x=%f, y=%f\n",
                    event.wheel.x, event.wheel.y
                )
            }
        }

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.5, 0.5, 0.5, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        sdl.GL_SwapWindow(window)
    }
}
