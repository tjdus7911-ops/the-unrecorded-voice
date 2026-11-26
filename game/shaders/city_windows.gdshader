// 원경 빌딩: 창 격자 일부만 켜짐 (차가운 백색 위주, 일부 따뜻한 색 — 보라·네온 금지). 빗속 원경이라 살짝 뿌옇게.
shader_type spatial;
render_mode unshaded;

uniform vec4 wall_color : source_color = vec4(0.03, 0.033, 0.04, 1.0);
uniform vec4 cool : source_color = vec4(0.74, 0.84, 1.0, 1.0);
uniform vec4 warm : source_color = vec4(1.0, 0.72, 0.45, 1.0);
uniform float lit_ratio = 0.28;
uniform float energy = 1.6;
uniform vec4 fog_color : source_color = vec4(0.05, 0.06, 0.08, 1.0);

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wpos.x - wpos.z, wpos.y) / vec2(1.6, 3.2);
	vec2 id = floor(p);
	vec2 f = fract(p);
	float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.22, f.y) * step(f.y, 0.78);
	float lit = step(1.0 - lit_ratio, hash12(id)) * win;
	vec3 c = mix(cool.rgb, warm.rgb, step(0.82, hash12(id * 1.37)));
	c *= mix(0.5, 1.0, hash12(id + 9.0));
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fogk = clamp(dist / 140.0, 0.0, 0.85);
	vec3 col = mix(wall_color.rgb, c * energy, lit);
	ALBEDO = mix(col, fog_color.rgb, fogk);
}
