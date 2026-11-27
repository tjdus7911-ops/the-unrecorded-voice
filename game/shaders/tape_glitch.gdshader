// 테이프 기억 공간의 순간 잡음 (늘어진 테이프·트래킹 노이즈). TAPE 01 소은 소멸 순간에만 0.4초 정도.
shader_type canvas_item;
uniform float amount = 0.0;
uniform float seed = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float band = step(0.82, h(vec2(floor(uv.y * 38.0), floor(TIME * 24.0))));
	uv.x += (h(vec2(uv.y * 91.0, seed)) - 0.5) * 0.035 * amount * (0.3 + band);
	vec3 c = texture(screen_tex, uv).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(g), 0.45 * amount);
	float n = h(uv * vec2(640.0, 360.0) + TIME);
	c = mix(c, vec3(n), (0.12 + 0.4 * band) * amount);
	COLOR = vec4(c, 1.0);
}
