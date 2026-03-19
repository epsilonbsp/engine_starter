package example

import glm "core:math/linalg/glsl"

Camera :: struct {
    position: glm.vec2,
    angle: f32,
    near: f32,
    far: f32,
    ortho_scale: f32,
    projection: glm.mat4,
    view: glm.mat4,
}

init_camera :: proc(
    camera: ^Camera,
    position := glm.vec2{},
    angle := f32(0),
    near := f32(-1),
    far := f32(1),
    ortho_scale := f32(2)
) {
    camera.position = position
    camera.angle = angle
    camera.near = near
    camera.far = far
    camera.ortho_scale = ortho_scale
}

move_camera :: proc(camera: ^Camera, direction: glm.vec2) {
    camera.position -= direction
}

zoom_camera :: proc(camera: ^Camera, direction: f32, min: f32 = 1e-2, max: f32 = 1e2) {
    camera.ortho_scale = glm.clamp(camera.ortho_scale + direction, min, max)
}

compute_camera_projection :: proc(camera: ^Camera, viewport_x: f32, viewport_y: f32) {
    camera.projection = glm.mat4Ortho3d(
        -f32(viewport_x) / camera.ortho_scale,
        f32(viewport_x) / camera.ortho_scale,
        -f32(viewport_y) / camera.ortho_scale,
        f32(viewport_y) / camera.ortho_scale,
        camera.near,
        camera.far
    )
}

compute_camera_view :: proc(camera: ^Camera) {
    camera.view = glm.mat4Translate({camera.position.x, camera.position.y, 0}) * glm.mat4Rotate({0, 0, -1}, camera.angle)
}

Camera_Movement :: struct {
    move_speed: f32,
    zoom_speed: f32,
    angle_speed: f32,
}

Camera_Input :: struct {
    left: bool,
    right: bool,
    down: bool,
    up: bool,
}

input_fly_camera :: proc(camera: ^Camera, input: Camera_Input, speed: f32) {
    if input.left {
        move_camera(camera, {-speed, 0})
    }

    if input.right {
        move_camera(camera, {speed, 0})
    }

    if input.down {
        move_camera(camera, {0, -speed})
    }

    if input.up {
        move_camera(camera, {0, speed})
    }
}

input_zoom_camera :: proc(camera: ^Camera, input_out: bool, input_in: bool, speed: f32, min: f32 = 1e-2, max: f32 = 1e2) {
    if input_out {
        zoom_camera(camera, -speed, min, max)
    }

    if input_in {
        zoom_camera(camera, speed, min, max)
    }
}
