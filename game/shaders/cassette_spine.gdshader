// 선반 카세트 등 라벨 — MultiMesh 인스턴스 커스텀 데이터(r)로 8칸 아틀라스 중 하나를 고른다 (드로우콜 1회)
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float cells = 8.0;
varying float cell;

void vertex() {
	cell = floor(INSTANCE_CUSTOM.r * cells + 0.5);
}

void fragment() {
	vec2 uv = vec2(UV.x, fract(UV.y) + cell / cells);
	ALBEDO = texture(atlas, uv).rgb;
	ROUGHNESS = 0.6;
}
