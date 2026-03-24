package example

import "core:fmt"
import "core:image"
import _ "core:image/jpeg"
import _ "core:image/png"
import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import gltf "vendor:cgltf"

Vertex :: struct {
    position: glm.vec3,
    normal: glm.vec3,
    uv: glm.vec2,
}

Primitive_GPU :: struct {
    vao, vbo, ibo: u32,
    texture_id: u32,
    index_count: i32,
}

Mesh_GPU :: struct {
    primitives: [dynamic]Primitive_GPU,
}

Model :: struct {
    mesh: int,
    transform: glm.mat4,
}

load_texture :: proc(img: ^gltf.image) -> u32 {
    if img == nil || img.buffer_view == nil {
        return 0
    }

    bv := img.buffer_view
    src := ([^]u8)(bv.buffer.data)[bv.offset : bv.offset + bv.size]

    loaded, err := image.load_from_bytes(src, {.alpha_add_if_missing})

    if err != nil {
        return 0
    }

    defer image.destroy(loaded)

    tex: u32
    gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(loaded.width), i32(loaded.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, &loaded.pixels.buf[0])
    gl.GenerateMipmap(gl.TEXTURE_2D)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    return tex
}

upload_mesh :: proc(mesh: ^gltf.mesh, texture_cache: ^map[rawptr]u32, white_tex: u32) -> Mesh_GPU {
    gpu_mesh: Mesh_GPU

    for &prim in mesh.primitives {
        if prim.type != .triangles || prim.indices == nil {
            continue
        }

        pos_acc, norm_acc, uv_acc: ^gltf.accessor

        for &attr in prim.attributes {
            #partial switch attr.type {
            case .position:
                pos_acc = attr.data
            case .normal:
                norm_acc = attr.data
            case .texcoord:
                if attr.index == 0 {
                    uv_acc = attr.data
                }
            }
        }

        if pos_acc == nil || norm_acc == nil {
            continue
        }

        vertex_count := pos_acc.count

        pos_floats := make([]f32, vertex_count * 3)
        defer delete(pos_floats)
        _ = gltf.accessor_unpack_floats(pos_acc, raw_data(pos_floats), vertex_count * 3)

        norm_floats := make([]f32, vertex_count * 3)
        defer delete(norm_floats)
        _ = gltf.accessor_unpack_floats(norm_acc, raw_data(norm_floats), vertex_count * 3)

        uv_floats := make([]f32, vertex_count * 2)
        defer delete(uv_floats)

        if uv_acc != nil {
            _ = gltf.accessor_unpack_floats(uv_acc, raw_data(uv_floats), vertex_count * 2)
        }

        vertices := make([]Vertex, vertex_count)
        defer delete(vertices)

        for i in 0 ..< int(vertex_count) {
            vertices[i].position = {pos_floats[i * 3], pos_floats[i * 3 + 1], pos_floats[i * 3 + 2]}
            vertices[i].normal = {norm_floats[i * 3], norm_floats[i * 3 + 1], norm_floats[i * 3 + 2]}
            vertices[i].uv = {uv_floats[i * 2], uv_floats[i * 2 + 1]}
        }

        index_count := prim.indices.count
        indices := make([]u32, index_count)
        defer delete(indices)
        _ = gltf.accessor_unpack_indices(prim.indices, raw_data(indices), size_of(u32), index_count)

        texture_id := white_tex

        if prim.material != nil {
            tex_view := prim.material.pbr_metallic_roughness.base_color_texture

            if tex_view.texture != nil && tex_view.texture.image_ != nil {
                key := rawptr(tex_view.texture.image_)

                if cached, found := texture_cache[key]; found {
                    texture_id = cached
                } else {
                    texture_id = load_texture(tex_view.texture.image_)

                    if texture_id == 0 {
                        texture_id = white_tex
                    }

                    texture_cache[key] = texture_id
                }
            }
        }

        gpu: Primitive_GPU
        gpu.index_count = i32(index_count)
        gpu.texture_id = texture_id

        gl.GenVertexArrays(1, &gpu.vao)
        gl.BindVertexArray(gpu.vao)

        gl.GenBuffers(1, &gpu.vbo)
        gl.BindBuffer(gl.ARRAY_BUFFER, gpu.vbo)
        gl.BufferData(gl.ARRAY_BUFFER, int(vertex_count) * size_of(Vertex), raw_data(vertices), gl.STATIC_DRAW)

        stride := i32(size_of(Vertex))
        gl.EnableVertexAttribArray(0)
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, offset_of(Vertex, position))
        gl.EnableVertexAttribArray(1)
        gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, stride, offset_of(Vertex, normal))
        gl.EnableVertexAttribArray(2)
        gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, stride, offset_of(Vertex, uv))

        gl.GenBuffers(1, &gpu.ibo)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gpu.ibo)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, int(index_count) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)

        append(&gpu_mesh.primitives, gpu)
    }

    return gpu_mesh
}

upload_node :: proc(node: ^gltf.node, models: ^[dynamic]Model, meshes: ^[dynamic]Mesh_GPU, mesh_cache: ^map[rawptr]int, texture_cache: ^map[rawptr]u32, white_tex: u32) {
    if node.mesh != nil {
        world: [16]f32
        gltf.node_transform_world(node, &world[0])

        mesh_index, found := mesh_cache[rawptr(node.mesh)]

        if !found {
            mesh_index = len(meshes)
            append(meshes, upload_mesh(node.mesh, texture_cache, white_tex))
            mesh_cache[rawptr(node.mesh)] = mesh_index
        }

        append(models, Model{
            mesh = mesh_index,
            transform = transmute(glm.mat4)world,
        })
    }

    for child in node.children {
        upload_node(child, models, meshes, mesh_cache, texture_cache, white_tex)
    }
}

load_model :: proc() -> (models: [dynamic]Model, meshes: [dynamic]Mesh_GPU, textures: [dynamic]u32, ok: bool) {
    options: gltf.options
    gltf_data, res := gltf.parse(options, raw_data(GLB_DATA), uint(len(GLB_DATA)))

    if res != .success {
        fmt.printf("GLTF parse error: %v\n", res)

        return
    }

    defer gltf.free(gltf_data)

    if gltf.load_buffers(options, gltf_data, nil) != .success {
        fmt.printf("GLTF load_buffers error\n")

        return
    }

    // White fallback texture (1x1 white pixel)
    white_pixel: [4]u8 = {255, 255, 255, 255}
    white_tex: u32
    gl.GenTextures(1, &white_tex)
    gl.BindTexture(gl.TEXTURE_2D, white_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &white_pixel)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    append(&textures, white_tex)

    mesh_cache: map[rawptr]int
    defer delete(mesh_cache)

    texture_cache: map[rawptr]u32
    defer delete(texture_cache)

    scene := gltf_data.scene

    if scene == nil && len(gltf_data.scenes) > 0 {
        scene = &gltf_data.scenes[0]
    }

    if scene != nil {
        for node in scene.nodes {
            upload_node(node, &models, &meshes, &mesh_cache, &texture_cache, white_tex)
        }
    }

    for _, tex_id in texture_cache {
        if tex_id != white_tex {
            append(&textures, tex_id)
        }
    }

    ok = len(models) > 0

    return
}
