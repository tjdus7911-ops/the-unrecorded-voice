// 소음 실루엣 괴물의 테이프 리본 (요구사항 16 EVENT 09): 뿌리(UV.y=0)는 고정, 끝으로 갈수록 느리게 흔들리고 가늘게 풀린다.
// 검은 자기 테이프: 거의 검정, 비스듬한 각도에서만 갈색 광택.
shader_type spatial;
render_mode cull_disabled;
uniform float t = 0.0;
uniform float sway = 0.05;
varying float tip;
void vertex() {
	tip = UV.y;
	float k = tip * tip;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = w.x * 3.1 + w.y * 1.7 + w.z * 2.3;
	VERTEX.x += sin(t * 1.3 + ph) * sway * k;
	VERTEX.z += cos(t * 0.9 + ph * 1.3) * sway * k;
	VERTEX.y += sin(t * 2.1 + ph * 0.7) * sway * 0.4 * k;
}
void fragment() {
	ALBEDO = mix(vec3(0.018, 0.014, 0.012), vec3(0.05, 0.035, 0.022), tip);
	ROUGHNESS = 0.35;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
