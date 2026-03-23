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

PREFILTER_FS :: GLSL_VERSION + `
    in vec3 v_direction;

    out vec4 o_frag_color;

    uniform samplerCube u_environment;
    uniform float u_roughness;

    const float PI = 3.14159265359;
    const uint NUM_SAMPLES = 1024u;

    float radical_inverse_vdc(uint bits) {
        bits = (bits << 16u) | (bits >> 16u);
        bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
        bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
        bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
        bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);

        return float(bits) * 2.3283064365386963e-10;
    }

    vec2 hammersley(uint i, uint n) {
        return vec2(float(i) / float(n), radical_inverse_vdc(i));
    }

    vec3 importance_sample_ggx(vec2 xi, vec3 n, float roughness) {
        float a = roughness * roughness;
        float phi = 2.0 * PI * xi.x;
        float cos_theta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
        float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

        vec3 h = vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);

        vec3 up = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
        vec3 tangent = normalize(cross(up, n));
        vec3 bitangent = cross(n, tangent);

        return normalize(tangent * h.x + bitangent * h.y + n * h.z);
    }

    float distribution_ggx(float n_dot_h, float roughness) {
        float a = roughness * roughness;
        float a2 = a * a;
        float denom = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;

        return a2 / (PI * denom * denom);
    }

    void main() {
        vec3 n = normalize(v_direction);
        vec3 v = n;

        float total_weight = 0.0;
        vec3 prefiltered = vec3(0.0);

        const float ENV_RESOLUTION = 512.0;
        float sa_texel = 4.0 * PI / (6.0 * ENV_RESOLUTION * ENV_RESOLUTION);

        for (uint i = 0u; i < NUM_SAMPLES; i++) {
            vec2 xi = hammersley(i, NUM_SAMPLES);
            vec3 h = importance_sample_ggx(xi, n, u_roughness);
            vec3 l = normalize(2.0 * dot(v, h) * h - v);

            float n_dot_l = max(dot(n, l), 0.0);

            if (n_dot_l > 0.0) {
                float n_dot_h = max(dot(n, h), 0.0);
                float v_dot_h = max(dot(v, h), 0.0);
                float d = distribution_ggx(n_dot_h, u_roughness);
                float pdf = (d * n_dot_h / (4.0 * v_dot_h)) + 0.0001;
                float sa_sample = 1.0 / (float(NUM_SAMPLES) * pdf + 0.0001);
                float mip = u_roughness == 0.0 ? 0.0 : 0.5 * log2(sa_sample / sa_texel);

                prefiltered += textureLod(u_environment, l, mip).rgb * n_dot_l;
                total_weight += n_dot_l;
            }
        }

        o_frag_color = vec4(prefiltered / total_weight, 1.0);
    }
`

BRDF_LUT_VS :: GLSL_VERSION + `
    out vec2 v_uv;

    void main() {
        vec2 positions[3] = vec2[](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
        vec2 uvs[3] = vec2[](vec2(0.0, 0.0), vec2(2.0, 0.0), vec2(0.0, 2.0));

        v_uv = uvs[gl_VertexID];
        gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0);
    }
`

BRDF_LUT_FS :: GLSL_VERSION + `
    in vec2 v_uv;

    out vec2 o_frag_color;

    const float PI = 3.14159265359;
    const uint NUM_SAMPLES = 1024u;

    float radical_inverse_vdc(uint bits) {
        bits = (bits << 16u) | (bits >> 16u);
        bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
        bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
        bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
        bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);

        return float(bits) * 2.3283064365386963e-10;
    }

    vec2 hammersley(uint i, uint n) {
        return vec2(float(i) / float(n), radical_inverse_vdc(i));
    }

    vec3 importance_sample_ggx(vec2 xi, vec3 n, float roughness) {
        float a = roughness * roughness;
        float phi = 2.0 * PI * xi.x;
        float cos_theta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
        float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

        vec3 h = vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);

        vec3 up = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
        vec3 tangent = normalize(cross(up, n));
        vec3 bitangent = cross(n, tangent);

        return normalize(tangent * h.x + bitangent * h.y + n * h.z);
    }

    float geometry_schlick_ggx(float n_dot_v, float roughness) {
        float k = (roughness * roughness) / 2.0;

        return n_dot_v / (n_dot_v * (1.0 - k) + k);
    }

    float geometry_smith(float n_dot_v, float n_dot_l, float roughness) {
        return geometry_schlick_ggx(n_dot_v, roughness) * geometry_schlick_ggx(n_dot_l, roughness);
    }

    void main() {
        float n_dot_v = v_uv.x;
        float roughness = v_uv.y;

        vec3 v = vec3(sqrt(1.0 - n_dot_v * n_dot_v), 0.0, n_dot_v);
        vec3 n = vec3(0.0, 0.0, 1.0);

        float scale = 0.0;
        float bias = 0.0;

        for (uint i = 0u; i < NUM_SAMPLES; i++) {
            vec2 xi = hammersley(i, NUM_SAMPLES);
            vec3 h = importance_sample_ggx(xi, n, roughness);
            vec3 l = normalize(2.0 * dot(v, h) * h - v);

            float n_dot_l = max(l.z, 0.0);
            float n_dot_h = max(h.z, 0.0);
            float v_dot_h = max(dot(v, h), 0.0);

            if (n_dot_l > 0.0) {
                float g = geometry_smith(n_dot_v, n_dot_l, roughness);
                float g_vis = (g * v_dot_h) / (n_dot_h * n_dot_v);
                float fc = pow(1.0 - v_dot_h, 5.0);
                scale += (1.0 - fc) * g_vis;
                bias += fc * g_vis;
            }
        }

        o_frag_color = vec2(scale, bias) / float(NUM_SAMPLES);
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

    if pixels == nil {
        fmt.println("ERROR: Failed to load HDR")

        return 0
    }

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

    equirect_pg, _ := gl.load_shaders_source(EQUIRECT_VS, EQUIRECT_FS); defer gl.DeleteProgram(equirect_pg)
    equirect_uf := gl.get_uniforms_from_program(equirect_pg); defer gl.destroy_uniforms(equirect_uf)

    gl.UseProgram(equirect_pg)
    gl.Uniform1i(equirect_uf["u_equirect"].location, 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, equirect_tex)

    render_cubemap_faces(equirect_pg, equirect_uf, cubemap, vao, index_count, CUBE_SIZE)

    gl.BindTexture(gl.TEXTURE_CUBE_MAP, cubemap)
    gl.GenerateMipmap(gl.TEXTURE_CUBE_MAP)

    return cubemap
}

create_prefilter_map :: proc(hdr_cubemap: u32, vao: u32, index_count: int) -> u32 {
    BASE_SIZE :: 512
    NUM_MIPS :: 5

    prefilter_map: u32
    gl.GenTextures(1, &prefilter_map)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, prefilter_map)

    for i in 0 ..< 6 {
        target := u32(gl.TEXTURE_CUBE_MAP_POSITIVE_X) + u32(i)

        gl.TexImage2D(target, 0, gl.RGB32F, BASE_SIZE, BASE_SIZE, 0, gl.RGB, gl.FLOAT, nil)
    }

    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
    gl.GenerateMipmap(gl.TEXTURE_CUBE_MAP)

    prefilter_pg, _ := gl.load_shaders_source(EQUIRECT_VS, PREFILTER_FS); defer gl.DeleteProgram(prefilter_pg)
    prefilter_uf := gl.get_uniforms_from_program(prefilter_pg); defer gl.destroy_uniforms(prefilter_uf)

    gl.UseProgram(prefilter_pg)
    gl.Uniform1i(prefilter_uf["u_environment"].location, 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, hdr_cubemap)

    for mip in 0 ..< NUM_MIPS {
        mip_size := i32(BASE_SIZE) >> u32(mip)
        roughness := f32(mip) / f32(NUM_MIPS - 1)

        gl.Uniform1f(prefilter_uf["u_roughness"].location, roughness)
        render_cubemap_faces(prefilter_pg, prefilter_uf, prefilter_map, vao, index_count, mip_size, i32(mip))
    }

    return prefilter_map
}

create_brdf_lut :: proc() -> u32 {
    LUT_SIZE :: 512

    lut: u32
    gl.GenTextures(1, &lut)
    gl.BindTexture(gl.TEXTURE_2D, lut)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RG16F, LUT_SIZE, LUT_SIZE, 0, gl.RG, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    brdf_pg, _ := gl.load_shaders_source(BRDF_LUT_VS, BRDF_LUT_FS); defer gl.DeleteProgram(brdf_pg)

    fbo: u32; gl.GenFramebuffers(1, &fbo); defer gl.DeleteFramebuffers(1, &fbo)
    rbo: u32; gl.GenRenderbuffers(1, &rbo); defer gl.DeleteRenderbuffers(1, &rbo)

    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.BindRenderbuffer(gl.RENDERBUFFER, rbo)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, LUT_SIZE, LUT_SIZE)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, lut, 0)

    blank_vao: u32; gl.GenVertexArrays(1, &blank_vao); defer gl.DeleteVertexArrays(1, &blank_vao)

    gl.Viewport(0, 0, LUT_SIZE, LUT_SIZE)
    gl.Enable(gl.DEPTH_TEST)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    gl.UseProgram(brdf_pg)
    gl.BindVertexArray(blank_vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 3)
    gl.Disable(gl.DEPTH_TEST)

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    return lut
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

    irradiance_pg, _ := gl.load_shaders_source(EQUIRECT_VS, IRRADIANCE_FS); defer gl.DeleteProgram(irradiance_pg)
    irradiance_uf := gl.get_uniforms_from_program(irradiance_pg); defer gl.destroy_uniforms(irradiance_uf)

    gl.UseProgram(irradiance_pg)
    gl.Uniform1i(irradiance_uf["u_environment"].location, 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, hdr_cubemap)

    render_cubemap_faces(irradiance_pg, irradiance_uf, irradiance_map, vao, index_count, CUBE_SIZE)

    return irradiance_map
}
