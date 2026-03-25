package example

import "core:fmt"
import c "core:c"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import stbi "vendor:stb/image"

EQUIRECT_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;

    out vec3 v_direction;

    uniform mat4 u_projection;
    uniform mat4 u_view;

    void main() {
        v_direction = i_position;
        gl_Position = u_projection * u_view * vec4(i_position, 1.0);
    }
`

EQUIRECT_FS :: GLSL_VERSION + `
    in vec3 v_direction;

    out vec4 o_frag_color;

    uniform sampler2D u_equirect;

    const vec2 INV_ATAN = vec2(0.1591549, 0.3183099);

    void main() {
        vec3 dir = normalize(v_direction);
        vec2 uv = vec2(atan(dir.z, dir.x), asin(dir.y));
        uv *= INV_ATAN;
        uv += 0.5;

        o_frag_color = vec4(texture(u_equirect, uv).rgb, 1.0);
    }
`

IRRADIANCE_FS :: GLSL_VERSION + `
    in vec3 v_direction;

    out vec4 o_frag_color;

    uniform samplerCube u_environment;

    const float PI = 3.14159265359;

    void main() {
        vec3 normal = normalize(v_direction);
        vec3 up = vec3(0.0, 1.0, 0.0);
        vec3 right = normalize(cross(up, normal));
        up = normalize(cross(normal, right));

        vec3 irradiance = vec3(0.0);
        float sample_delta = 0.025;
        float num_samples = 0.0;

        for (float phi = 0.0; phi < 2.0 * PI; phi += sample_delta) {
            for (float theta = 0.0; theta < 0.5 * PI; theta += sample_delta) {
                vec3 tangent_sample = vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
                vec3 sample_vec = tangent_sample.x * right + tangent_sample.y * up + tangent_sample.z * normal;

                irradiance += texture(u_environment, sample_vec).rgb * cos(theta) * sin(theta);
                num_samples++;
            }
        }

        o_frag_color = vec4(PI * irradiance / num_samples, 1.0);
    }
`

capture_views := [6]glm.mat4{
    glm.mat4LookAt({0, 0, 0}, { 1,  0,  0}, {0, -1,  0}),
    glm.mat4LookAt({0, 0, 0}, {-1,  0,  0}, {0, -1,  0}),
    glm.mat4LookAt({0, 0, 0}, { 0,  1,  0}, {0,  0,  1}),
    glm.mat4LookAt({0, 0, 0}, { 0, -1,  0}, {0,  0, -1}),
    glm.mat4LookAt({0, 0, 0}, { 0,  0,  1}, {0, -1,  0}),
    glm.mat4LookAt({0, 0, 0}, { 0,  0, -1}, {0, -1,  0}),
}

capture_projection := glm.mat4Perspective(glm.radians(f32(90)), 1.0, 0.1, 10.0)

render_cubemap_faces :: proc(pg: u32, uf: gl.Uniforms, cubemap: u32, vao: u32, index_count: int, size: i32, mip: i32 = 0) {
    fbo: u32
    gl.GenFramebuffers(1, &fbo); defer gl.DeleteFramebuffers(1, &fbo)

    rbo: u32
    gl.GenRenderbuffers(1, &rbo); defer gl.DeleteRenderbuffers(1, &rbo)

    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.BindRenderbuffer(gl.RENDERBUFFER, rbo)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, size, size)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rbo)

    gl.Enable(gl.DEPTH_TEST)
    gl.UseProgram(pg)
    gl.UniformMatrix4fv(uf["u_projection"].location, 1, false, &capture_projection[0][0])
    gl.Viewport(0, 0, size, size)
    gl.BindVertexArray(vao)

    for i in 0 ..< 6 {
        target := u32(gl.TEXTURE_CUBE_MAP_POSITIVE_X) + u32(i)

        gl.UniformMatrix4fv(uf["u_view"].location, 1, false, &capture_views[i][0][0])
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, target, cubemap, mip)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        gl.DrawElements(gl.TRIANGLES, i32(index_count), gl.UNSIGNED_INT, nil)
    }

    gl.Disable(gl.DEPTH_TEST)
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

load_hdr_cubemap :: proc(hdr_bytes: []byte, vao: u32, index_count: int) -> u32 {
    CUBE_SIZE :: 512

    stbi.set_flip_vertically_on_load(1)

    w, h, ch: c.int
    pixels := stbi.loadf_from_memory(raw_data(hdr_bytes), i32(len(hdr_bytes)), &w, &h, &ch, 3)

    assert(pixels != nil, "ERROR: Failed to load HDR")

    defer stbi.image_free(rawptr(pixels))

    equirect_tex: u32
    gl.GenTextures(1, &equirect_tex); defer gl.DeleteTextures(1, &equirect_tex)
    gl.BindTexture(gl.TEXTURE_2D, equirect_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB32F, w, h, 0, gl.RGB, gl.FLOAT, pixels)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    cubemap: u32
    gl.GenTextures(1, &cubemap)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, cubemap)

    for i in 0 ..< 6 {
        target := u32(gl.TEXTURE_CUBE_MAP_POSITIVE_X) + u32(i)

        gl.TexImage2D(target, 0, gl.RGB32F, CUBE_SIZE, CUBE_SIZE, 0, gl.RGB, gl.FLOAT, nil)
    }

    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)

    equirect_pg, equirect_ok := gl.load_shaders_source(EQUIRECT_VS, EQUIRECT_FS); defer gl.DeleteProgram(equirect_pg)
    equirect_uf := gl.get_uniforms_from_program(equirect_pg); defer gl.destroy_uniforms(equirect_uf)
    assert(equirect_ok, "ERROR: Failed to compile program")

    gl.UseProgram(equirect_pg)
    gl.Uniform1i(equirect_uf["u_equirect"].location, 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, equirect_tex)

    render_cubemap_faces(equirect_pg, equirect_uf, cubemap, vao, index_count, CUBE_SIZE)

    gl.BindTexture(gl.TEXTURE_CUBE_MAP, cubemap)
    gl.GenerateMipmap(gl.TEXTURE_CUBE_MAP)

    return cubemap
}

create_irradiance_map :: proc(hdr_cubemap: u32, vao: u32, index_count: int) -> u32 {
    CUBE_SIZE :: 32

    irradiance_map: u32
    gl.GenTextures(1, &irradiance_map)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, irradiance_map)

    for i in 0 ..< 6 {
        target := u32(gl.TEXTURE_CUBE_MAP_POSITIVE_X) + u32(i)

        gl.TexImage2D(target, 0, gl.RGB32F, CUBE_SIZE, CUBE_SIZE, 0, gl.RGB, gl.FLOAT, nil)
    }

    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)

    irradiance_pg, irradiance_ok := gl.load_shaders_source(EQUIRECT_VS, IRRADIANCE_FS); defer gl.DeleteProgram(irradiance_pg)
    irradiance_uf := gl.get_uniforms_from_program(irradiance_pg); defer gl.destroy_uniforms(irradiance_uf)
    assert(irradiance_ok, "ERROR: Failed to compile program")

    gl.UseProgram(irradiance_pg)
    gl.Uniform1i(irradiance_uf["u_environment"].location, 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, hdr_cubemap)

    render_cubemap_faces(irradiance_pg, irradiance_uf, irradiance_map, vao, index_count, CUBE_SIZE)

    return irradiance_map
}
