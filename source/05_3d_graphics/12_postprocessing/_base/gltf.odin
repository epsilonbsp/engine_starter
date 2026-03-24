package base

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import gltf "vendor:cgltf"

GL_Vertex :: struct {
    position: glm.vec3,
    normal: glm.vec3,
    tex_coord: glm.vec2,
    tangent: glm.vec4,
}

GL_Primitive :: struct {
    vao: u32,
    vbo: u32,
    ibo: u32,
    index_count: i32,
}

load_gltf_from_bytes :: proc(bytes: []u8) -> (data: ^gltf.data, result: gltf.result) {
    return gltf.parse({}, raw_data(bytes), uint(len(bytes)))
}

load_gltf_primitive :: proc(data: ^gltf.data, result: gltf.result) -> (gl_prim: GL_Primitive, ok: bool) {
    if result != .success {
        return {}, false
    }

    defer gltf.free(data)

    if gltf.load_buffers({}, data, nil) != .success {
        return {}, false
    }

    scenes := data.scenes

    if len(scenes) == 0 {
        return {}, false
    }

    scene := scenes[0]
    nodes := scene.nodes

    if len(nodes) == 0 {
        return {}, false
    }

    mesh: ^gltf.mesh

    for node in scene.nodes {
        if node.mesh != nil {
            mesh = node.mesh

            break
        }
    }

    if mesh == nil {
        return {}, false
    }

    primitives := mesh.primitives

    if len(primitives) == 0 {
        return {}, false
    }

    primitive := primitives[0]

    if primitive.type != .triangles || primitive.indices == nil {
        return {}, false
    }

    position_acc : ^gltf.accessor
    normal_acc: ^gltf.accessor
    tex_coord_acc: ^gltf.accessor
    tangent_acc: ^gltf.accessor

    for attribute in primitive.attributes {
        #partial switch attribute.type {
        case .position:
            position_acc = attribute.data
        case .normal:
            normal_acc = attribute.data
        case .texcoord:
            tex_coord_acc = attribute.data
        case .tangent:
            tangent_acc = attribute.data
        }
    }

    if position_acc == nil || normal_acc == nil {
        return {}, false
    }

    vertex_count := position_acc.count
    index_count := primitive.indices.count

    // Load positions
    positions := make([]f32, vertex_count * 3); defer delete(positions)
    _ = gltf.accessor_unpack_floats(position_acc, raw_data(positions), vertex_count * 3)

    // Load normals
    normals := make([]f32, vertex_count * 3); defer delete(normals)
    _ = gltf.accessor_unpack_floats(normal_acc, raw_data(normals), vertex_count * 3)

    // Load texture coordinates if available
    tex_coords := make([]f32, vertex_count * 2); defer delete(tex_coords)

    if tex_coord_acc != nil {
        _ = gltf.accessor_unpack_floats(tex_coord_acc, raw_data(tex_coords), vertex_count * 2)
    }

    // Load tangents if available
    tangents := make([]f32, vertex_count * 4); defer delete(tangents)

    if tangent_acc != nil {
        _ = gltf.accessor_unpack_floats(tangent_acc, raw_data(tangents), vertex_count * 4)
    }

    // Load vertices
    vertices := make([]GL_Vertex, vertex_count); defer delete(vertices)

    for i in 0 ..< int(vertex_count) {
        vertices[i].position = {positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]}
        vertices[i].normal = {normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2]}
        vertices[i].tex_coord = {tex_coords[i * 2], tex_coords[i * 2 + 1]}
        vertices[i].tangent = {tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2], tangents[i * 4 + 3]}
    }

    // Load indices
    indices := make([]u32, index_count); defer delete(indices)
    _ = gltf.accessor_unpack_indices(primitive.indices, raw_data(indices), size_of(u32), index_count)

    // VAO
    gl.GenVertexArrays(1, &gl_prim.vao)
    gl.BindVertexArray(gl_prim.vao)

    // VBO
    gl.GenBuffers(1, &gl_prim.vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, gl_prim.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, int(vertex_count) * size_of(GL_Vertex), raw_data(vertices), gl.STATIC_DRAW)

    // Attributes
    stride := i32(size_of(GL_Vertex))

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, offset_of(GL_Vertex, position))

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, stride, offset_of(GL_Vertex, normal))

    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, stride, offset_of(GL_Vertex, tex_coord))

    gl.EnableVertexAttribArray(3)
    gl.VertexAttribPointer(3, 4, gl.FLOAT, gl.FALSE, stride, offset_of(GL_Vertex, tangent))

    // IBO
    gl.GenBuffers(1, &gl_prim.ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_prim.ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, int(index_count) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)

    gl_prim.index_count = i32(index_count)

    return gl_prim, true
}

destroy_gltf_primitive :: proc(gl_primitive: ^GL_Primitive) {
    gl.DeleteVertexArrays(1, &gl_primitive.vao)
    gl.DeleteBuffers(1, &gl_primitive.vbo)
    gl.DeleteBuffers(1, &gl_primitive.ibo)
}
