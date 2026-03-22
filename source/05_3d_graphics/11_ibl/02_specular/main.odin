package example

import "core:fmt"
import "core:image/png"
import c "core:c"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

WINDOW_TITLE :: "Specular"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
GLSL_VERSION :: "#version 460 core"

Material :: struct {
    albedo: glm.vec3,
    metallic: f32,
    roughness: f32,
    ao: f32,
}

Mesh :: struct {
    translation: glm.vec3,
    rotation: glm.vec3,
    scale: glm.vec3,
    material: Material,
}

Vertex :: struct {
    position: glm.vec3,
    normal: glm.vec3,
    tex_coord: glm.vec2,
    tangent: glm.vec4,
}

exposure := f32(1.0)

meshes := []Mesh {
    {{-4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.8, 0.5, 0.3}, 0.0, 0.8, 1.0}},
    {{ 0, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.2, 0.4, 0.8}, 0.0, 0.4, 1.0}},
    {{ 4, 0, 0}, {0, 0, 0}, {2, 2, 2}, {{0.7, 0.7, 0.7}, 1.0, 0.2, 1.0}},
}

mesh_vertices := []Vertex {
    // Left
    {{-0.5, -0.5, -0.5}, {-1, 0, 0}, {0, 1}, {0, 0, 1, -1}},
    {{-0.5, -0.5,  0.5}, {-1, 0, 0}, {1, 1}, {0, 0, 1, -1}},
    {{-0.5,  0.5,  0.5}, {-1, 0, 0}, {1, 0}, {0, 0, 1, -1}},
    {{-0.5,  0.5, -0.5}, {-1, 0, 0}, {0, 0}, {0, 0, 1, -1}},

    // Right
    {{ 0.5, -0.5,  0.5}, {1, 0, 0}, {0, 1}, {0, 0, -1, -1}},
    {{ 0.5, -0.5, -0.5}, {1, 0, 0}, {1, 1}, {0, 0, -1, -1}},
    {{ 0.5,  0.5, -0.5}, {1, 0, 0}, {1, 0}, {0, 0, -1, -1}},
    {{ 0.5,  0.5,  0.5}, {1, 0, 0}, {0, 0}, {0, 0, -1, -1}},

    // Bottom
    {{-0.5, -0.5, -0.5}, {0, -1, 0}, {0, 1}, {1, 0, 0, -1}},
    {{ 0.5, -0.5, -0.5}, {0, -1, 0}, {1, 1}, {1, 0, 0, -1}},
    {{ 0.5, -0.5,  0.5}, {0, -1, 0}, {1, 0}, {1, 0, 0, -1}},
    {{-0.5, -0.5,  0.5}, {0, -1, 0}, {0, 0}, {1, 0, 0, -1}},

    // Top
    {{-0.5,  0.5,  0.5}, {0, 1, 0}, {0, 1}, {1, 0, 0, -1}},
    {{ 0.5,  0.5,  0.5}, {0, 1, 0}, {1, 1}, {1, 0, 0, -1}},
    {{ 0.5,  0.5, -0.5}, {0, 1, 0}, {1, 0}, {1, 0, 0, -1}},
    {{-0.5,  0.5, -0.5}, {0, 1, 0}, {0, 0}, {1, 0, 0, -1}},

    // Back
    {{ 0.5, -0.5, -0.5}, {0, 0, -1}, {0, 1}, {-1, 0, 0, -1}},
    {{-0.5, -0.5, -0.5}, {0, 0, -1}, {1, 1}, {-1, 0, 0, -1}},
    {{-0.5,  0.5, -0.5}, {0, 0, -1}, {1, 0}, {-1, 0, 0, -1}},
    {{ 0.5,  0.5, -0.5}, {0, 0, -1}, {0, 0}, {-1, 0, 0, -1}},

    // Front
    {{-0.5, -0.5,  0.5}, {0, 0, 1}, {0, 1}, {1, 0, 0, -1}},
    {{ 0.5, -0.5,  0.5}, {0, 0, 1}, {1, 1}, {1, 0, 0, -1}},
    {{ 0.5,  0.5,  0.5}, {0, 0, 1}, {1, 0}, {1, 0, 0, -1}},
    {{-0.5,  0.5,  0.5}, {0, 0, 1}, {0, 0}, {1, 0, 0, -1}},
}

mesh_indices := []u32 {
    // Left
    0, 1, 2, 0, 2, 3,

    // Right
    4, 5, 6, 4, 6, 7,

    // Bottom
    8, 9, 10, 8, 10, 11,

    // Top
    12, 13, 14, 12, 14, 15,

    // Back
    16, 17, 18, 16, 18, 19,

    // Front
    20, 21, 22, 20, 22, 23,
}

mesh_index_count := len(mesh_indices)

MAIN_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;
    layout(location = 2) in vec2 i_tex_coord;
    layout(location = 3) in vec4 i_tangent;

    out vec3 v_normal;
    out vec2 v_tex_coord;
    out mat3 v_tbn;
    out vec3 v_world_pos;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;
    uniform mat3 u_normal_matrix;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        vec3 normal = normalize(u_normal_matrix * i_normal);
        vec3 tangent = normalize(u_normal_matrix * i_tangent.xyz);
        tangent = normalize(tangent - dot(tangent, normal) * normal);
        vec3 bitangent = cross(normal, tangent) * i_tangent.w;

        gl_Position = u_projection * u_view * world_pos;
        v_normal = u_normal_matrix * i_normal;
        v_tex_coord = i_tex_coord;
        v_tbn = mat3(tangent, bitangent, normal);
        v_world_pos = world_pos.xyz;
    }
`

MAIN_FS :: GLSL_VERSION + `
    in vec3 v_normal;
    in vec2 v_tex_coord;
    in mat3 v_tbn;
    in vec3 v_world_pos;

    out vec4 o_frag_color;

    uniform vec3 u_view_pos;
    uniform float u_exposure;
    uniform vec3 u_mat_albedo;
    uniform float u_mat_metallic;
    uniform float u_mat_roughness;
    uniform float u_mat_ao;
    uniform sampler2D u_albedo_tex;
    uniform sampler2D u_arm_tex;
    uniform sampler2D u_normal_tex;
    uniform samplerCube u_irradiance_map;
    uniform samplerCube u_prefilter_map;
    uniform sampler2D u_brdf_lut;

    const float MAX_REFLECTION_LOD = 4.0;

    vec3 fresnel_schlick(float cos_theta, vec3 f0) {
        return f0 + (1.0 - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
    }

    vec3 fresnel_schlick_roughness(float cos_theta, vec3 f0, float roughness) {
        return f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
    }

    void main() {
        vec3 albedo = texture(u_albedo_tex, v_tex_coord).rgb * u_mat_albedo;
        vec3 arm = texture(u_arm_tex, v_tex_coord).rgb;
        float ao = arm.r * u_mat_ao;
        float roughness = arm.g * u_mat_roughness;
        float metallic = arm.b * u_mat_metallic;

        vec3 n = texture(u_normal_tex, v_tex_coord).rgb * 2.0 - 1.0;
        n = normalize(v_tbn * n);
        vec3 v = normalize(u_view_pos - v_world_pos);
        vec3 r = reflect(-v, n);
        float n_dot_v = max(dot(n, v), 0.0);

        vec3 f0 = mix(vec3(0.04), albedo, metallic);
        vec3 ks = fresnel_schlick_roughness(n_dot_v, f0, roughness);
        vec3 kd = (vec3(1.0) - ks) * (1.0 - metallic);

        // Diffuse IBL
        vec3 irradiance = texture(u_irradiance_map, n).rgb;
        vec3 diffuse = kd * irradiance * albedo;

        // Specular IBL (split-sum approximation)
        vec3 prefiltered = textureLod(u_prefilter_map, r, roughness * MAX_REFLECTION_LOD).rgb;
        vec2 brdf = texture(u_brdf_lut, vec2(n_dot_v, roughness)).rg;
        vec3 specular = prefiltered * (ks * brdf.x + brdf.y);

        vec3 color = (diffuse + specular) * ao;

        // Exposure tone mapping
        color = vec3(1.0) - exp(-color * u_exposure);

        // Gamma correction
        color = pow(color, vec3(1.0 / 2.2));

        o_frag_color = vec4(color, 1.0);
    }
`

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

SKYBOX_VS :: GLSL_VERSION + `
    out vec3 v_tex_coord;

    uniform mat4 u_projection;
    uniform mat4 u_view;

    const vec3 POSITIONS[14] = vec3[](
        // Back (-Z)
        vec3(-1, 1,-1), vec3( 1, 1,-1), vec3(-1,-1,-1), vec3( 1,-1,-1),

        // Right (+X)
        vec3( 1,-1, 1), vec3( 1, 1,-1), vec3( 1, 1, 1),

        // Top (+Y)
        vec3(-1, 1,-1), vec3(-1, 1, 1),

        // Left (-X)
        vec3(-1,-1,-1), vec3(-1,-1, 1),

        // Bottom (-Y) + front (+Z)
        vec3( 1,-1, 1), vec3(-1, 1, 1), vec3( 1, 1, 1)
    );

    void main() {
        vec3 position = POSITIONS[gl_VertexID];
        vec4 clip = u_projection * mat4(mat3(u_view)) * vec4(position, 1.0);

        gl_Position = clip.xyww;
        v_tex_coord = position;
    }
`

SKYBOX_FS :: GLSL_VERSION + `
    in vec3 v_tex_coord;

    out vec4 o_frag_color;

    uniform samplerCube u_skybox;
    uniform float u_exposure;

    void main() {
        vec3 color = texture(u_skybox, v_tex_coord).rgb;
        color = vec3(1.0) - exp(-color * u_exposure);

        o_frag_color = vec4(pow(color, vec3(1.0 / 2.2)), 1.0);
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

make_transform :: proc(translation: glm.vec3, rotation: glm.vec3, scale: glm.vec3) -> glm.mat4 {
    qx := glm.quatAxisAngle({1, 0, 0}, rotation.x)
    qy := glm.quatAxisAngle({0, 1, 0}, rotation.y)
    qz := glm.quatAxisAngle({0, 0, 1}, rotation.z)
    q := qz * qy * qx

    return glm.mat4Translate(translation) * glm.mat4FromQuat(q) * glm.mat4Scale(scale)
}

load_texture_from_bytes :: proc(bytes: []u8, srgb := false) -> u32 {
    image, _ := png.load_from_bytes(bytes, {.alpha_add_if_missing}); defer png.destroy(image)

    tex: u32; gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D, tex)

    w, h := i32(image.width), i32(image.height)

    if image.depth == 16 {
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16, w, h, 0, gl.RGBA, gl.UNSIGNED_SHORT, &image.pixels.buf[0])
    } else {
        internal_format := srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8
        gl.TexImage2D(gl.TEXTURE_2D, 0, i32(internal_format), w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, &image.pixels.buf[0])
    }

    gl.GenerateMipmap(gl.TEXTURE_2D)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)

    return tex
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

    main_pg, main_ok := gl.load_shaders_source(MAIN_VS, MAIN_FS); defer gl.DeleteProgram(main_pg)
    main_uf := gl.get_uniforms_from_program(main_pg); defer gl.destroy_uniforms(main_uf);

    if !main_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    skybox_pg, skybox_ok := gl.load_shaders_source(SKYBOX_VS, SKYBOX_FS); defer gl.DeleteProgram(skybox_pg)
    skybox_uf := gl.get_uniforms_from_program(skybox_pg); defer gl.destroy_uniforms(skybox_uf);

    if !skybox_ok {
        fmt.printf("PROGRAM ERROR: %s\n", gl.get_last_error_message())

        return
    }

    main_vao: u32; gl.GenVertexArrays(1, &main_vao); defer gl.DeleteVertexArrays(1, &main_vao)
    gl.BindVertexArray(main_vao)

    main_vbo: u32; gl.GenBuffers(1, &main_vbo); defer gl.DeleteBuffers(1, &main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(mesh_vertices) * size_of(mesh_vertices[0]), &mesh_vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, normal))

    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, tex_coord))

    gl.EnableVertexAttribArray(3)
    gl.VertexAttribPointer(3, 4, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, tangent))

    main_ibo: u32; gl.GenBuffers(1, &main_ibo); defer gl.DeleteBuffers(1, &main_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, main_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, mesh_index_count * size_of(mesh_indices[0]), &mesh_indices[0], gl.STATIC_DRAW)

    skybox_vao: u32; gl.GenVertexArrays(1, &skybox_vao); defer gl.DeleteVertexArrays(1, &skybox_vao)

    // Source: https://polyhaven.com/a/damaged_plaster
    albedo_tex := load_texture_from_bytes(#load("textures/albedo.png"), true); defer gl.DeleteTextures(1, &albedo_tex)
    arm_tex := load_texture_from_bytes(#load("textures/arm.png")); defer gl.DeleteTextures(1, &arm_tex)
    normal_tex := load_texture_from_bytes(#load("textures/normal.png")); defer gl.DeleteTextures(1, &normal_tex)

    // Source: https://polyhaven.com/a/kloppenheim_06_puresky
    hdr_cubemap := load_hdr_cubemap(#load("cubemap/radiance.hdr"), main_vao, mesh_index_count)
    defer gl.DeleteTextures(1, &hdr_cubemap)

    irradiance_map := create_irradiance_map(hdr_cubemap, main_vao, mesh_index_count)
    defer gl.DeleteTextures(1, &irradiance_map)

    prefilter_map := create_prefilter_map(hdr_cubemap, main_vao, mesh_index_count)
    defer gl.DeleteTextures(1, &prefilter_map)

    brdf_lut := create_brdf_lut()
    defer gl.DeleteTextures(1, &brdf_lut)

    camera: Camera
    init_camera(&camera, position = {6, 6, 6})
    point_camera_at(&camera, {})

    camera_movement := Camera_Movement{move_speed = 5, yaw_speed = 0.002, pitch_speed = 0.002}

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

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
            case .KEY_DOWN:
                if event.key.scancode == sdl.Scancode.ESCAPE {
                    _ = sdl.SetWindowRelativeMouseMode(window, !sdl.GetWindowRelativeMouseMode(window))
                }
            case .MOUSE_MOTION:
                if sdl.GetWindowRelativeMouseMode(window) {
                    rotate_camera(&camera, event.motion.xrel * camera_movement.yaw_speed, event.motion.yrel * camera_movement.pitch_speed, 0)
                }
            }
        }

        if (sdl.GetWindowRelativeMouseMode(window)) {
            input_fly_camera(
                &camera,
                {key_state[sdl.Scancode.A], key_state[sdl.Scancode.D], key_state[sdl.Scancode.S], key_state[sdl.Scancode.W]},
                time_delta * camera_movement.move_speed
            )
        }

        compute_camera_projection(&camera, f32(viewport_x) / f32(viewport_y))
        compute_camera_view(&camera)

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.1, 0.1, 0.1, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        // Draw meshes
        gl.UseProgram(main_pg)
        gl.UniformMatrix4fv(main_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(main_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3fv(main_uf["u_view_pos"].location, 1, &camera.position[0])
        gl.Uniform1f(main_uf["u_exposure"].location, exposure)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, albedo_tex)
        gl.Uniform1i(main_uf["u_albedo_tex"].location, 0)

        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_2D, arm_tex)
        gl.Uniform1i(main_uf["u_arm_tex"].location, 1)

        gl.ActiveTexture(gl.TEXTURE2)
        gl.BindTexture(gl.TEXTURE_2D, normal_tex)
        gl.Uniform1i(main_uf["u_normal_tex"].location, 2)

        gl.ActiveTexture(gl.TEXTURE3)
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, irradiance_map)
        gl.Uniform1i(main_uf["u_irradiance_map"].location, 3)

        gl.ActiveTexture(gl.TEXTURE4)
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, prefilter_map)
        gl.Uniform1i(main_uf["u_prefilter_map"].location, 4)

        gl.ActiveTexture(gl.TEXTURE5)
        gl.BindTexture(gl.TEXTURE_2D, brdf_lut)
        gl.Uniform1i(main_uf["u_brdf_lut"].location, 5)

        gl.BindVertexArray(main_vao)

        for &mesh in meshes {
            model := make_transform(mesh.translation, mesh.rotation, mesh.scale)
            normal_matrix := glm.transpose(glm.inverse(glm.mat3(model)))

            gl.UniformMatrix4fv(main_uf["u_model"].location, 1, false, &model[0][0])
            gl.UniformMatrix3fv(main_uf["u_normal_matrix"].location, 1, false, &normal_matrix[0][0])
            gl.Uniform3fv(main_uf["u_mat_albedo"].location, 1, &mesh.material.albedo[0])
            gl.Uniform1f(main_uf["u_mat_metallic"].location, mesh.material.metallic)
            gl.Uniform1f(main_uf["u_mat_roughness"].location, mesh.material.roughness)
            gl.Uniform1f(main_uf["u_mat_ao"].location, mesh.material.ao)

            gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
        }

        // Draw skybox
        gl.DepthFunc(gl.LEQUAL)
        gl.Disable(gl.CULL_FACE)

        gl.UseProgram(skybox_pg)
        gl.UniformMatrix4fv(skybox_uf["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(skybox_uf["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform1f(skybox_uf["u_exposure"].location, exposure)
        gl.Uniform1i(skybox_uf["u_skybox"].location, 6)
        gl.ActiveTexture(gl.TEXTURE6)
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, hdr_cubemap)
        gl.BindVertexArray(skybox_vao)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 14)

        gl.DepthFunc(gl.LESS)
        gl.Enable(gl.CULL_FACE)

        sdl.GL_SwapWindow(window)
    }
}
