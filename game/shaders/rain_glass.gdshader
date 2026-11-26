// 창문 유리: 맺힌 물방울 + 흘러내리는 빗물 줄기 + 그 뒤 풍경의 굴절 (Forward+ 화면 텍스처)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float rain_amount : hint_range(0.0, 1.0) = 0.6;
uniform float refraction = 0.018;
uniform float blur_lod : hint_range(0.0, 6.0) = 1.6;   // 흐린 유리 (빗물 막)
uniform vec4 tint : source_color = vec4(0.82, 0.88, 0.95, 1.0);
uniform float time_scale = 1.0;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 정지된 물방울 (셀마다 하나, 반짝임) → 높이값
float static_drops(vec2 uv, float scale) {
	vec2 p = uv * scale;
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash12(id);
	vec2 o = vec2(hash12(id + 7.1), hash12(id + 3.7)) - 0.5;
	float r = mix(0.06, 0.22, h * h);
	float d = length((f - o * 0.6) * vec2(1.0, 0.85));
	float drop = smoothstep(r, r * 0.3, d);
	return drop * step(0.35, h);
}

// 흘러내리는 줄기: 열마다 속도가 다른 물방울 + 꼬리
float running(vec2 uv, float t) {
	vec2 p = uv * vec2(18.0, 2.0);
	float col = floor(p.x);
	float h = hash12(vec2(col, 2.3));
	float speed = mix(0.08, 0.35, h);
	float y = fract(p.y * 0.5 + t * speed + h * 7.0);
	float x = fract(p.x) - 0.5 + sin(uv.y * 40.0 + h * 6.28) * 0.08;
	float head = smoothstep(0.18, 0.02, length(vec2(x, (y - 0.85) * 3.0)));
	float trail = smoothstep(0.06, 0.0, abs(x)) * smoothstep(0.85, 0.2, y) * 0.35 * step(0.55, h);
	return (head + trail) * step(0.25, h);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2(wpos.x + wpos.z, wpos.y) * 0.9;
	float t = TIME * time_scale;
	float h = static_drops(uv, 22.0) * 0.6 + static_drops(uv + 3.1, 41.0) * 0.35;
	h += running(uv, t) * 1.2;
	h *= rain_amount;
	// 높이 → 노멀
	float e = 0.002;
	float hx = static_drops(uv + vec2(e, 0.0), 22.0) * 0.8 + running(uv + vec2(e, 0.0), t) * 1.2;
	float hy = static_drops(uv + vec2(0.0, e), 22.0) * 0.8 + running(uv + vec2(0.0, e), t) * 1.2;
	vec2 grad = vec2(hx - h, hy - h) * rain_amount;
	vec2 suv = SCREEN_UV + grad * refraction * 6.0 + vec2(0.0, h * refraction);
	float lod = blur_lod * (1.0 - clamp(h, 0.0, 1.0));     // 물방울 안은 선명, 막은 흐림
	vec3 behind = textureLod(screen_tex, suv, lod).rgb;
	// 유리 너머 풍경은 조명과 무관하게 그대로 보여야 하므로 EMISSION으로, 유리 자체는 반사(스펙큘러)만
	ALBEDO = vec3(0.0);
	EMISSION = behind * tint.rgb;
	ROUGHNESS = mix(0.08, 0.02, clamp(h, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.3;
	NORMAL_MAP = normalize(vec3(-grad * 40.0 + 0.5, 1.0)) * 0.5 + 0.5;
	ALPHA = 0.97;
}
