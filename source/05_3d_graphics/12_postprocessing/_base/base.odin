package base

import "core:image/png"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"

Light :: struct {
    dir: glm.vec3,
    color: glm.vec3,
}

Skybox :: struct {
    top: glm.vec3,
    horizon: glm.vec3,
    bottom: glm.vec3,
    sun_disc_threshold: f32,
    sun_inner_power: f32,
    sun_inner_strength: f32,
    sun_outer_power: f32,
    sun_outer_strength: f32,
}

Material :: struct {
    albedo: glm.vec3,
    metallic: f32,
    roughness: f32,
    ao: f32,
    texture_index: i32,
    tiling_scale: f32,
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

GBuffer :: struct {
    fbo: u32,
    position_tex: u32,
    normal_tex: u32,
    albedo_tex: u32,
    material_tex: u32,
    depth_tex: u32,
}

SceneBuffer :: struct {
    fbo: u32,
    color_tex: u32,
}

Base :: struct {
    // Programs + uniforms
    gbuffer_pg: u32,
    gbuffer_uf: gl.Uniforms,
    lighting_pg: u32,
    lighting_uf: gl.Uniforms,
    skybox_pg: u32,
    skybox_uf: gl.Uniforms,
    depth_pg: u32,
    depth_uf: gl.Uniforms,
    tonemap_pg: u32,
    tonemap_uf: gl.Uniforms,

    // Geometry buffers
    main_vao: u32,
    main_vbo: u32,
    main_ibo: u32,
    quad_vao: u32,
    skybox_vao: u32,

    // Textures
    albedo_arr: u32,
    arm_arr: u32,
    normal_arr: u32,
    depth_tex: u32,

    // Framebuffers
    depth_fbo: u32,
    gbuffer: GBuffer,
    scene_buffer: SceneBuffer,

    // Scene config
    light: Light,
    skybox: Skybox,
    exposure: f32,
    sky_irradiance_strength: f32,
    debug_buffer: i32,
}

GLSL_VERSION :: "#version 460 core"

SHADOW_CENTER :: glm.vec3{}
SHADOW_LIGHT_DIST :: f32(80)
SHADOW_ORTHO_SIZE :: f32(32)
SHADOW_NEAR :: f32(0.1)
SHADOW_FAR :: f32(100)
SHADOW_MAP_SIZE :: 2048
SHADOW_OUTSIDE_COLOR := glm.vec4{1, 1, 1, 1}

meshes := []Mesh{
    {{ 0.0, -1.0,  0.0}, {0, 0, 0}, {32, 2,  32}, {{1, 1, 1}, 1.0, 1.0, 1.0, 0, 0.5}},
    {{ 0.0,  0.5,  0.0}, {0, 0, 0}, {16, 1,  16}, {{1, 1, 1}, 1.0, 0.2, 1.0, 1, 0.5}},
    {{ 0.0,  3.0,  0.0}, {0, 0, 0}, {8,  4,  1 }, {{1, 1, 1}, 1.0, 0.2, 1.0, 2, 0.5}},
    {{-6.0,  7.0,  6.0}, {0, 0, 0}, {1,  12, 1 }, {{1, 1, 1}, 1.0, 0.2, 1.0, 3, 0.5}},
    {{ 6.0,  7.0,  6.0}, {0, 0, 0}, {1,  12, 1 }, {{1, 1, 1}, 1.0, 0.2, 1.0, 3, 0.5}},
    {{ 6.0,  7.0, -6.0}, {0, 0, 0}, {1,  12, 1 }, {{1, 1, 1}, 1.0, 0.2, 1.0, 3, 0.5}},
    {{-6.0,  7.0, -6.0}, {0, 0, 0}, {1,  12, 1 }, {{1, 1, 1}, 1.0, 0.2, 1.0, 3, 0.5}},
    {{ 0.0, 13.5,  0.0}, {0, 0, 0}, {16, 1,  16}, {{1, 1, 1}, 1.0, 0.2, 1.0, 1, 0.5}},
}

mesh_vertices := []Vertex{
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

mesh_indices := []u32{
    0,  1,  2,  0,  2,  3,
    4,  5,  6,  4,  6,  7,
    8,  9,  10, 8,  10, 11,
    12, 13, 14, 12, 14, 15,
    16, 17, 18, 16, 18, 19,
    20, 21, 22, 20, 22, 23,
}

mesh_index_count := len(mesh_indices)

GBUFFER_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;
    layout(location = 2) in vec2 i_tex_coord;
    layout(location = 3) in vec4 i_tangent;

    out vec3 v_world_pos;
    out vec2 v_tex_coord;
    out mat3 v_tbn;

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
        v_world_pos = world_pos.xyz;
        v_tex_coord = i_tex_coord;
        v_tbn = mat3(tangent, bitangent, normal);
    }
`

GBUFFER_FS :: GLSL_VERSION + `
    in vec3 v_world_pos;
    in vec2 v_tex_coord;
    in mat3 v_tbn;

    layout(location = 0) out vec3 o_position;
    layout(location = 1) out vec3 o_normal;
    layout(location = 2) out vec3 o_albedo;
    layout(location = 3) out vec4 o_material;

    uniform vec3 u_mat_albedo;
    uniform float u_mat_metallic;
    uniform float u_mat_roughness;
    uniform float u_mat_ao;
    uniform sampler2DArray u_albedo_tex;
    uniform sampler2DArray u_arm_tex;
    uniform sampler2DArray u_normal_tex;
    uniform int u_texture_index;
    uniform float u_tiling_scale;

    void main() {
        vec3 uvw = vec3(dot(v_world_pos, v_tbn[0]) * u_tiling_scale, dot(v_world_pos, v_tbn[1]) * u_tiling_scale, float(u_texture_index));

        vec3 albedo = texture(u_albedo_tex, uvw).rgb * u_mat_albedo;
        vec3 arm = texture(u_arm_tex, uvw).rgb;
        float ao = arm.r * u_mat_ao;
        float roughness = arm.g * u_mat_roughness;
        float metallic = arm.b * u_mat_metallic;

        vec3 n = texture(u_normal_tex, uvw).rgb * 2.0 - 1.0;
        n = normalize(v_tbn * n);

        o_position = v_world_pos;
        o_normal = n;
        o_albedo = albedo;
        o_material = vec4(metallic, roughness, ao, 0.0);
    }
`

LIGHTING_VS :: GLSL_VERSION + `
    const vec2 POSITIONS[4] = vec2[](
        vec2(-1, -1),
        vec2( 1, -1),
        vec2(-1,  1),
        vec2( 1,  1)
    );

    const vec2 TEXCOORDS[4] = vec2[](
        vec2(0, 0),
        vec2(1, 0),
        vec2(0, 1),
        vec2(1, 1)
    );

    out vec2 v_tex_coord;

    void main() {
        gl_Position = vec4(POSITIONS[gl_VertexID], 0.0, 1.0);
        v_tex_coord = TEXCOORDS[gl_VertexID];
    }
`

LIGHTING_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_g_position;
    uniform sampler2D u_g_normal;
    uniform sampler2D u_g_albedo;
    uniform sampler2D u_g_material;
    uniform sampler2D u_g_depth;
    uniform float u_near;
    uniform float u_far;
    uniform sampler2D u_shadow_map;
    uniform mat4 u_light_space;
    uniform vec3 u_view_pos;
    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;
    uniform int u_debug_buffer;
    uniform vec3 u_skybox_top;
    uniform vec3 u_skybox_horizon;
    uniform vec3 u_skybox_bottom;
    uniform float u_sky_irradiance_intensity;

    const int PCF_RADIUS = 1;
    const int PCF_SAMPLES = (2 * PCF_RADIUS + 1) * (2 * PCF_RADIUS + 1);

    float shadow_factor(vec3 world_pos) {
        vec4 light_space_pos = u_light_space * vec4(world_pos, 1.0);
        vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
        proj_coords = proj_coords * 0.5 + 0.5;

        if (proj_coords.z > 1.0) return 0.0;

        vec2 texel_size = 1.0 / textureSize(u_shadow_map, 0);
        float bias = 0.0001;
        float shadow = 0.0;

        for (int x = -PCF_RADIUS; x <= PCF_RADIUS; x++) {
            for (int y = -PCF_RADIUS; y <= PCF_RADIUS; y++) {
                float closest_depth = texture(u_shadow_map, proj_coords.xy + vec2(x, y) * texel_size).r;
                shadow += proj_coords.z - bias > closest_depth ? 1.0 : 0.0;
            }
        }

        return shadow / float(PCF_SAMPLES);
    }

    const float PI = 3.14159265359;

    float distribution_ggx(vec3 n, vec3 h, float roughness) {
        float a = roughness * roughness;
        float a2 = a * a;
        float n_dot_h = max(dot(n, h), 0.0);
        float denom = (n_dot_h * n_dot_h * (a2 - 1.0) + 1.0);

        return a2 / (PI * denom * denom);
    }

    float geometry_schlick_ggx(float n_dot_v, float roughness) {
        float k = (roughness + 1.0);
        k = (k * k) / 8.0;

        return n_dot_v / (n_dot_v * (1.0 - k) + k);
    }

    float geometry_smith(vec3 n, vec3 v, vec3 l, float roughness) {
        float nv = geometry_schlick_ggx(max(dot(n, v), 0.0), roughness);
        float nl = geometry_schlick_ggx(max(dot(n, l), 0.0), roughness);

        return nv * nl;
    }

    vec3 fresnel_schlick(float cos_theta, vec3 f0) {
        return f0 + (1.0 - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
    }

    // Approximate hemispherical sky irradiance: Lambertian-weighted integral over
    // the visible hemisphere of the gradient sky.
    vec3 sky_irradiance(vec3 n) {
        vec3 top_irr = (u_skybox_horizon + 2.0 * u_skybox_top) / 3.0;
        vec3 bot_irr = (u_skybox_horizon + 2.0 * u_skybox_bottom) / 3.0;
        vec3 mid_irr = (u_skybox_top + u_skybox_horizon + u_skybox_bottom) / 3.0;

        return n.y >= 0.0
            ? mix(mid_irr, top_irr, n.y)
            : mix(mid_irr, bot_irr, -n.y);
    }

    void main() {
        vec3 world_pos = texture(u_g_position, v_tex_coord).rgb;
        vec3 n = texture(u_g_normal, v_tex_coord).rgb;
        vec3 albedo = texture(u_g_albedo, v_tex_coord).rgb;
        vec4 mat = texture(u_g_material, v_tex_coord);

        if (u_debug_buffer == 1) { o_frag_color = vec4(world_pos, 1.0); return; }
        if (u_debug_buffer == 2) { o_frag_color = vec4(n * 0.5 + 0.5, 1.0); return; }
        if (u_debug_buffer == 3) { o_frag_color = vec4(albedo, 1.0); return; }
        if (u_debug_buffer == 4) { o_frag_color = vec4(mat.rgb, 1.0); return; }

        if (u_debug_buffer == 5) {
            float d = texture(u_g_depth, v_tex_coord).r;
            float linear_d = (2.0 * u_near) / (u_far + u_near - d * (u_far - u_near));

            o_frag_color = vec4(vec3(linear_d), 1.0); return;
        }

        float metallic = mat.r;
        float roughness = mat.g;
        float ao = mat.b;

        vec3 v = normalize(u_view_pos - world_pos);
        vec3 l = normalize(u_light_dir);
        vec3 h = normalize(v + l);

        vec3 f0 = mix(vec3(0.04), albedo, metallic);

        float ndf = distribution_ggx(n, h, roughness);
        float g = geometry_smith(n, v, l, roughness);
        vec3 f = fresnel_schlick(clamp(dot(h, v), 0.0, 1.0), f0);

        vec3 kd = (vec3(1.0) - f) * (1.0 - metallic);
        vec3 specular = (ndf * g * f) / (4.0 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0) + 0.0001);

        float n_dot_l = max(dot(n, l), 0.0);
        vec3 lo = (kd * albedo / PI + specular) * u_light_color * n_dot_l;

        float shadow = shadow_factor(world_pos);
        vec3 ambient = sky_irradiance(n) * u_sky_irradiance_intensity * albedo * ao;
        vec3 color = ambient + (1.0 - shadow) * lo;

        o_frag_color = vec4(color, 1.0);
    }
`

SKYBOX_VS :: GLSL_VERSION + `
    out vec3 v_tex_coord;

    uniform mat4 u_projection;
    uniform mat4 u_view;

    const vec3 POSITIONS[14] = vec3[](
        vec3(-1, 1,-1), vec3( 1, 1,-1), vec3(-1,-1,-1), vec3( 1,-1,-1),
        vec3( 1,-1, 1), vec3( 1, 1,-1), vec3( 1, 1, 1),
        vec3(-1, 1,-1), vec3(-1, 1, 1),
        vec3(-1,-1,-1), vec3(-1,-1, 1),
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

    uniform vec3 u_light_dir;
    uniform vec3 u_light_color;
    uniform vec3 u_skybox_top;
    uniform vec3 u_skybox_horizon;
    uniform vec3 u_skybox_bottom;
    uniform float u_sun_disc_threshold;
    uniform vec4 u_sun_glow; // xy = inner (power, strength), zw = outer (power, strength)

    void main() {
        vec3 dir = normalize(v_tex_coord);

        vec3 current_color = dir.y >= 0.0
            ? mix(u_skybox_horizon, u_skybox_top, dir.y)
            : mix(u_skybox_horizon, u_skybox_bottom, -dir.y);

        float sun_dot = dot(dir, u_light_dir);
        float sun_disc = smoothstep(u_sun_disc_threshold, 1.0, sun_dot);
        float sun_inner = pow(max(sun_dot, 0.0), u_sun_glow.x) * u_sun_glow.y;
        float sun_outer = pow(max(sun_dot, 0.0), u_sun_glow.z) * u_sun_glow.w;

        vec3 color = current_color + u_light_color * (sun_disc + sun_inner + sun_outer);
        o_frag_color = vec4(color, 1.0);
    }
`

DEPTH_VS :: GLSL_VERSION + `
    layout(location = 0) in vec3 i_position;

    uniform mat4 u_light_space;
    uniform mat4 u_model;

    void main() {
        gl_Position = u_light_space * u_model * vec4(i_position, 1.0);
    }
`

DEPTH_FS :: GLSL_VERSION + `
    void main() {}
`

TONEMAP_VS :: LIGHTING_VS

TONEMAP_FS :: GLSL_VERSION + `
    in vec2 v_tex_coord;

    out vec4 o_frag_color;

    uniform sampler2D u_scene_color;
    uniform float u_exposure;
    uniform int u_debug_buffer;

    void main() {
        vec3 color = texture(u_scene_color, v_tex_coord).rgb;

        if (u_debug_buffer != 0) {
            o_frag_color = vec4(color, 1.0);

            return;
        }

        color = vec3(1.0) - exp(-color * u_exposure);
        color = pow(color, vec3(1.0 / 2.2));

        o_frag_color = vec4(color, 1.0);
    }
`

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

load_texture_array :: proc(layers: [][]u8, srgb := false) -> u32 {
    tex: u32; gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D_ARRAY, tex)

    layer_count := i32(len(layers))

    for bytes, i in layers {
        image, _ := png.load_from_bytes(bytes, {.alpha_add_if_missing}); defer png.destroy(image)
        w, h := i32(image.width), i32(image.height)

        if i == 0 {
            if image.depth == 16 {
                gl.TexImage3D(gl.TEXTURE_2D_ARRAY, 0, gl.RGBA16, w, h, layer_count, 0, gl.RGBA, gl.UNSIGNED_SHORT, nil)
            } else {
                internal_format := srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8
                gl.TexImage3D(gl.TEXTURE_2D_ARRAY, 0, i32(internal_format), w, h, layer_count, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
            }
        }

        if image.depth == 16 {
            gl.TexSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, i32(i), w, h, 1, gl.RGBA, gl.UNSIGNED_SHORT, &image.pixels.buf[0])
        } else {
            gl.TexSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, i32(i), w, h, 1, gl.RGBA, gl.UNSIGNED_BYTE, &image.pixels.buf[0])
        }
    }

    gl.GenerateMipmap(gl.TEXTURE_2D_ARRAY)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.REPEAT)

    return tex
}

init_gbuffer :: proc(gbuffer: ^GBuffer, width: i32, height: i32) {
    gl.GenFramebuffers(1, &gbuffer.fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo)

    gl.GenTextures(1, &gbuffer.position_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.position_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB32F, width, height, 0, gl.RGB, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, gbuffer.position_tex, 0)

    gl.GenTextures(1, &gbuffer.normal_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.normal_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, width, height, 0, gl.RGB, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, gbuffer.normal_tex, 0)

    gl.GenTextures(1, &gbuffer.albedo_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.albedo_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, width, height, 0, gl.RGB, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT2, gl.TEXTURE_2D, gbuffer.albedo_tex, 0)

    gl.GenTextures(1, &gbuffer.material_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.material_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, width, height, 0, gl.RGBA, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT3, gl.TEXTURE_2D, gbuffer.material_tex, 0)

    attachments := [4]u32{gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1, gl.COLOR_ATTACHMENT2, gl.COLOR_ATTACHMENT3}
    gl.DrawBuffers(4, &attachments[0])

    gl.GenTextures(1, &gbuffer.depth_tex)
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.depth_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT24, width, height, 0, gl.DEPTH_COMPONENT, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, gbuffer.depth_tex, 0)

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

destroy_gbuffer :: proc(gbuffer: ^GBuffer) {
    gl.DeleteTextures(1, &gbuffer.position_tex)
    gl.DeleteTextures(1, &gbuffer.normal_tex)
    gl.DeleteTextures(1, &gbuffer.albedo_tex)
    gl.DeleteTextures(1, &gbuffer.material_tex)
    gl.DeleteTextures(1, &gbuffer.depth_tex)
    gl.DeleteFramebuffers(1, &gbuffer.fbo)
}

resize_gbuffer :: proc(gbuffer: ^GBuffer, width: i32, height: i32) {
    destroy_gbuffer(gbuffer)
    init_gbuffer(gbuffer, width, height)
}

init_scene_buffer :: proc(scene: ^SceneBuffer, width: i32, height: i32, depth_tex: u32) {
    gl.GenFramebuffers(1, &scene.fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, scene.fbo)

    gl.GenTextures(1, &scene.color_tex)
    gl.BindTexture(gl.TEXTURE_2D, scene.color_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, width, height, 0, gl.RGBA, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, scene.color_tex, 0)

    // Share the gbuffer depth so the skybox can test against geometry depth
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, depth_tex, 0)

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

destroy_scene_buffer :: proc(scene: ^SceneBuffer) {
    gl.DeleteTextures(1, &scene.color_tex)
    gl.DeleteFramebuffers(1, &scene.fbo)
}

resize_scene_buffer :: proc(scene: ^SceneBuffer, width: i32, height: i32, depth_tex: u32) {
    destroy_scene_buffer(scene)
    init_scene_buffer(scene, width, height, depth_tex)
}

init_base :: proc(base: ^Base, width: i32, height: i32) -> bool {
    ok: bool

    base.gbuffer_pg, ok = gl.load_shaders_source(GBUFFER_VS, GBUFFER_FS)
    if !ok do return false
    base.gbuffer_uf = gl.get_uniforms_from_program(base.gbuffer_pg)

    base.lighting_pg, ok = gl.load_shaders_source(LIGHTING_VS, LIGHTING_FS)
    if !ok do return false
    base.lighting_uf = gl.get_uniforms_from_program(base.lighting_pg)

    base.skybox_pg, ok = gl.load_shaders_source(SKYBOX_VS, SKYBOX_FS)
    if !ok do return false
    base.skybox_uf = gl.get_uniforms_from_program(base.skybox_pg)

    base.depth_pg, ok = gl.load_shaders_source(DEPTH_VS, DEPTH_FS)
    if !ok do return false
    base.depth_uf = gl.get_uniforms_from_program(base.depth_pg)

    base.tonemap_pg, ok = gl.load_shaders_source(TONEMAP_VS, TONEMAP_FS)
    if !ok do return false
    base.tonemap_uf = gl.get_uniforms_from_program(base.tonemap_pg)

    gl.GenVertexArrays(1, &base.main_vao)
    gl.BindVertexArray(base.main_vao)

    gl.GenBuffers(1, &base.main_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, base.main_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(mesh_vertices) * size_of(mesh_vertices[0]), &mesh_vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, normal))
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, tex_coord))
    gl.EnableVertexAttribArray(3)
    gl.VertexAttribPointer(3, 4, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, tangent))

    gl.GenBuffers(1, &base.main_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, base.main_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, mesh_index_count * size_of(mesh_indices[0]), &mesh_indices[0], gl.STATIC_DRAW)

    gl.GenVertexArrays(1, &base.quad_vao)
    gl.GenVertexArrays(1, &base.skybox_vao)

    gl.GenTextures(1, &base.depth_tex)
    gl.BindTexture(gl.TEXTURE_2D, base.depth_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, gl.DEPTH_COMPONENT, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
    gl.TexParameterfv(gl.TEXTURE_2D, gl.TEXTURE_BORDER_COLOR, &SHADOW_OUTSIDE_COLOR[0])

    gl.GenFramebuffers(1, &base.depth_fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, base.depth_fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, base.depth_tex, 0)
    gl.DrawBuffer(gl.NONE)
    gl.ReadBuffer(gl.NONE)
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    // A source: https://polyhaven.com/a/rocky_terrain_02
    // B source: https://polyhaven.com/a/floor_tiles_08
    // C source: https://polyhaven.com/a/rebar_reinforced_concrete
    // D source: https://polyhaven.com/a/long_white_tiles

    base.albedo_arr = load_texture_array([][]u8{
        #load("textures/a/albedo.png"),
        #load("textures/b/albedo.png"),
        #load("textures/c/albedo.png"),
        #load("textures/d/albedo.png"),
    }, true)

    base.arm_arr = load_texture_array([][]u8{
        #load("textures/a/arm.png"),
        #load("textures/b/arm.png"),
        #load("textures/c/arm.png"),
        #load("textures/d/arm.png"),
    })

    base.normal_arr = load_texture_array([][]u8{
        #load("textures/a/normal.png"),
        #load("textures/b/normal.png"),
        #load("textures/c/normal.png"),
        #load("textures/d/normal.png"),
    })

    init_gbuffer(&base.gbuffer, width, height)
    init_scene_buffer(&base.scene_buffer, width, height, base.gbuffer.depth_tex)

    base.light = Light{
        dir = glm.normalize(glm.vec3{1, 2, 3}),
        color = {1, 0.8, 0.6},
    }

    base.skybox = Skybox{
        top = {0.1, 0.3, 0.8},
        horizon = {0.5, 0.7, 0.9},
        bottom = {0.1, 0.3, 0.8},
        sun_disc_threshold = 0.9995,
        sun_inner_power = 64.0,
        sun_inner_strength = 0.5,
        sun_outer_power = 64.0,
        sun_outer_strength = 0.3,
    }

    base.exposure = 1.0
    base.sky_irradiance_strength = 0.2

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    return true
}

destroy_base :: proc(base: ^Base) {
    gl.destroy_uniforms(base.gbuffer_uf); gl.DeleteProgram(base.gbuffer_pg)
    gl.destroy_uniforms(base.lighting_uf); gl.DeleteProgram(base.lighting_pg)
    gl.destroy_uniforms(base.skybox_uf); gl.DeleteProgram(base.skybox_pg)
    gl.destroy_uniforms(base.depth_uf); gl.DeleteProgram(base.depth_pg)
    gl.destroy_uniforms(base.tonemap_uf); gl.DeleteProgram(base.tonemap_pg)

    gl.DeleteVertexArrays(1, &base.main_vao)
    gl.DeleteBuffers(1, &base.main_vbo)
    gl.DeleteBuffers(1, &base.main_ibo)
    gl.DeleteVertexArrays(1, &base.quad_vao)
    gl.DeleteVertexArrays(1, &base.skybox_vao)

    gl.DeleteTextures(1, &base.albedo_arr)
    gl.DeleteTextures(1, &base.arm_arr)
    gl.DeleteTextures(1, &base.normal_arr)
    gl.DeleteTextures(1, &base.depth_tex)

    gl.DeleteFramebuffers(1, &base.depth_fbo)

    destroy_gbuffer(&base.gbuffer)
    destroy_scene_buffer(&base.scene_buffer)
}

resize_base :: proc(base: ^Base, width: i32, height: i32) {
    resize_gbuffer(&base.gbuffer, width, height)
    resize_scene_buffer(&base.scene_buffer, width, height, base.gbuffer.depth_tex)
}

base_render_scene :: proc(base: ^Base, camera: ^Camera, viewport_x: i32, viewport_y: i32) {
    // Shadow stabilization
    light_up := abs(base.light.dir.y) > 0.99 ? glm.vec3{0, 0, 1} : glm.vec3{0, 1, 0}
    light_view := glm.mat4LookAt(base.light.dir * SHADOW_LIGHT_DIST, SHADOW_CENTER, light_up)

    origin_ls := light_view * glm.vec4{0, 0, 0, 1}
    texel_size := (SHADOW_ORTHO_SIZE * 2) / f32(SHADOW_MAP_SIZE)
    offset_x := origin_ls.x - glm.floor(origin_ls.x / texel_size) * texel_size
    offset_y := origin_ls.y - glm.floor(origin_ls.y / texel_size) * texel_size

    light_proj := glm.mat4Ortho3d(
        -SHADOW_ORTHO_SIZE - offset_x, SHADOW_ORTHO_SIZE - offset_x,
        -SHADOW_ORTHO_SIZE - offset_y, SHADOW_ORTHO_SIZE - offset_y,
        SHADOW_NEAR, SHADOW_FAR,
    )

    light_space := light_proj * light_view

    // Depth pass
    gl.Enable(gl.POLYGON_OFFSET_FILL)
    gl.PolygonOffset(2, 4)
    gl.Viewport(0, 0, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE)
    gl.BindFramebuffer(gl.FRAMEBUFFER, base.depth_fbo)
    gl.Clear(gl.DEPTH_BUFFER_BIT)

    gl.UseProgram(base.depth_pg)
    gl.UniformMatrix4fv(base.depth_uf["u_light_space"].location, 1, false, &light_space[0][0])
    gl.BindVertexArray(base.main_vao)

    for &mesh in meshes {
        model := make_transform(mesh.translation, mesh.rotation, mesh.scale)

        gl.UniformMatrix4fv(base.depth_uf["u_model"].location, 1, false, &model[0][0])
        gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
    }

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.Disable(gl.POLYGON_OFFSET_FILL)

    // Geometry pass
    gl.BindFramebuffer(gl.FRAMEBUFFER, base.gbuffer.fbo)
    gl.Viewport(0, 0, viewport_x, viewport_y)
    gl.ClearColor(0, 0, 0, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

    gl.UseProgram(base.gbuffer_pg)
    gl.UniformMatrix4fv(base.gbuffer_uf["u_projection"].location, 1, false, &camera.projection[0][0])
    gl.UniformMatrix4fv(base.gbuffer_uf["u_view"].location, 1, false, &camera.view[0][0])

    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D_ARRAY, base.albedo_arr)
    gl.Uniform1i(base.gbuffer_uf["u_albedo_tex"].location, 0)

    gl.ActiveTexture(gl.TEXTURE1)
    gl.BindTexture(gl.TEXTURE_2D_ARRAY, base.arm_arr)
    gl.Uniform1i(base.gbuffer_uf["u_arm_tex"].location, 1)

    gl.ActiveTexture(gl.TEXTURE2)
    gl.BindTexture(gl.TEXTURE_2D_ARRAY, base.normal_arr)
    gl.Uniform1i(base.gbuffer_uf["u_normal_tex"].location, 2)

    gl.BindVertexArray(base.main_vao)

    for &mesh in meshes {
        model := make_transform(mesh.translation, mesh.rotation, mesh.scale)
        normal_matrix := glm.transpose(glm.inverse(glm.mat3(model)))

        gl.UniformMatrix4fv(base.gbuffer_uf["u_model"].location, 1, false, &model[0][0])
        gl.UniformMatrix3fv(base.gbuffer_uf["u_normal_matrix"].location, 1, false, &normal_matrix[0][0])
        gl.Uniform3fv(base.gbuffer_uf["u_mat_albedo"].location, 1, &mesh.material.albedo[0])
        gl.Uniform1f(base.gbuffer_uf["u_mat_metallic"].location, mesh.material.metallic)
        gl.Uniform1f(base.gbuffer_uf["u_mat_roughness"].location, mesh.material.roughness)
        gl.Uniform1f(base.gbuffer_uf["u_mat_ao"].location, mesh.material.ao)
        gl.Uniform1i(base.gbuffer_uf["u_texture_index"].location, mesh.material.texture_index)
        gl.Uniform1f(base.gbuffer_uf["u_tiling_scale"].location, mesh.material.tiling_scale)

        gl.DrawElements(gl.TRIANGLES, i32(mesh_index_count), gl.UNSIGNED_INT, nil)
    }

    // Lighting pass
    gl.BindFramebuffer(gl.FRAMEBUFFER, base.scene_buffer.fbo)
    gl.Clear(gl.COLOR_BUFFER_BIT)
    gl.Disable(gl.DEPTH_TEST)

    gl.UseProgram(base.lighting_pg)

    gl.ActiveTexture(gl.TEXTURE0); gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.position_tex)
    gl.ActiveTexture(gl.TEXTURE1); gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.normal_tex)
    gl.ActiveTexture(gl.TEXTURE2); gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.albedo_tex)
    gl.ActiveTexture(gl.TEXTURE3); gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.material_tex)
    gl.ActiveTexture(gl.TEXTURE4); gl.BindTexture(gl.TEXTURE_2D, base.depth_tex)
    gl.ActiveTexture(gl.TEXTURE5); gl.BindTexture(gl.TEXTURE_2D, base.gbuffer.depth_tex)

    gl.Uniform1i(base.lighting_uf["u_g_position"].location, 0)
    gl.Uniform1i(base.lighting_uf["u_g_normal"].location, 1)
    gl.Uniform1i(base.lighting_uf["u_g_albedo"].location, 2)
    gl.Uniform1i(base.lighting_uf["u_g_material"].location, 3)
    gl.Uniform1i(base.lighting_uf["u_shadow_map"].location, 4)
    gl.Uniform1i(base.lighting_uf["u_g_depth"].location, 5)
    gl.Uniform1f(base.lighting_uf["u_near"].location, camera.near)
    gl.Uniform1f(base.lighting_uf["u_far"].location, camera.far)

    gl.UniformMatrix4fv(base.lighting_uf["u_light_space"].location, 1, false, &light_space[0][0])
    gl.Uniform3fv(base.lighting_uf["u_view_pos"].location, 1, &camera.position[0])
    gl.Uniform3fv(base.lighting_uf["u_light_dir"].location, 1, &base.light.dir[0])
    gl.Uniform3fv(base.lighting_uf["u_light_color"].location, 1, &base.light.color[0])
    gl.Uniform1i(base.lighting_uf["u_debug_buffer"].location, base.debug_buffer)
    gl.Uniform3fv(base.lighting_uf["u_skybox_top"].location, 1, &base.skybox.top[0])
    gl.Uniform3fv(base.lighting_uf["u_skybox_horizon"].location, 1, &base.skybox.horizon[0])
    gl.Uniform3fv(base.lighting_uf["u_skybox_bottom"].location, 1, &base.skybox.bottom[0])
    gl.Uniform1f(base.lighting_uf["u_sky_irradiance_intensity"].location, base.sky_irradiance_strength)

    gl.BindVertexArray(base.quad_vao)
    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

    gl.Enable(gl.DEPTH_TEST)

    // Draw skybox
    gl.DepthFunc(gl.LEQUAL)
    gl.Disable(gl.CULL_FACE)

    gl.UseProgram(base.skybox_pg)
    gl.UniformMatrix4fv(base.skybox_uf["u_projection"].location, 1, false, &camera.projection[0][0])
    gl.UniformMatrix4fv(base.skybox_uf["u_view"].location, 1, false, &camera.view[0][0])
    gl.Uniform3fv(base.skybox_uf["u_light_dir"].location, 1, &base.light.dir[0])
    gl.Uniform3fv(base.skybox_uf["u_light_color"].location, 1, &base.light.color[0])
    gl.Uniform3fv(base.skybox_uf["u_skybox_top"].location, 1, &base.skybox.top[0])
    gl.Uniform3fv(base.skybox_uf["u_skybox_horizon"].location, 1, &base.skybox.horizon[0])
    gl.Uniform3fv(base.skybox_uf["u_skybox_bottom"].location, 1, &base.skybox.bottom[0])
    gl.Uniform1f(base.skybox_uf["u_sun_disc_threshold"].location, base.skybox.sun_disc_threshold)
    gl.Uniform4f(base.skybox_uf["u_sun_glow"].location, base.skybox.sun_inner_power, base.skybox.sun_inner_strength, base.skybox.sun_outer_power, base.skybox.sun_outer_strength)

    gl.BindVertexArray(base.skybox_vao)
    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 14)

    gl.DepthFunc(gl.LESS)
    gl.Enable(gl.CULL_FACE)
}

// Tonemaps the given HDR scene texture to the default framebuffer.
base_tonemap :: proc(base: ^Base, scene_tex: u32) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.Clear(gl.COLOR_BUFFER_BIT)
    gl.Disable(gl.DEPTH_TEST)

    gl.UseProgram(base.tonemap_pg)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, scene_tex)
    gl.Uniform1i(base.tonemap_uf["u_scene_color"].location, 0)
    gl.Uniform1f(base.tonemap_uf["u_exposure"].location, base.exposure)
    gl.Uniform1i(base.tonemap_uf["u_debug_buffer"].location, base.debug_buffer)

    gl.BindVertexArray(base.quad_vao)
    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

    gl.Enable(gl.DEPTH_TEST)
}
