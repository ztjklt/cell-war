shader_type canvas_item;
render_mode unshaded;

uniform sampler2D ground_pattern : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D edge_brush : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 region_origin;
uniform vec2 region_size;
uniform float tile_world_size = 3.5;
uniform float amount : hint_range(0.0, 1.0) = 0.42;
uniform float layout_seed = 0.0;
uniform float detail_midpoint = 0.4;
uniform float detail_strength = 0.75;

float random_value(float n) {
	return fract(sin(n * 17.31 + layout_seed) * 43758.5453);
}

vec2 brush(vec2 uv, vec2 center, float extent, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	vec2 local = mat2(vec2(c, -s), vec2(s, c)) * (uv - center) / extent + vec2(0.5);
	if (local.x < 0.0 || local.y < 0.0 || local.x > 1.0 || local.y > 1.0) {
		return vec2(0.0, detail_midpoint);
	}
	vec4 sample_color = texture(edge_brush, local);
	return vec2(sample_color.a, dot(sample_color.rgb, vec3(0.299, 0.587, 0.114)));
}

void fragment() {
	// The generated color tile keeps a constant world scale. Mirroring makes
	// the repeat boundary continuous even if the source's opposite edges vary.
	vec2 world_uv = (region_origin + UV * region_size) / tile_world_size;
	vec2 repeat_uv = vec2(1.0) - abs(mod(world_uv, vec2(2.0)) - vec2(1.0));
	vec3 color = texture(ground_pattern, repeat_uv).rgb;
	vec2 merged = brush(UV, vec2(0.5), 0.73, random_value(0.0) * 6.283185);
	for (int i = 1; i < 8; i++) {
		float n = float(i);
		float angle = n * 2.399963 + random_value(n) * 0.45;
		vec2 center = vec2(0.5) + vec2(cos(angle), sin(angle)) * (0.18 + random_value(n + 10.0) * 0.045);
		vec2 stamp = brush(UV, center, 0.44 + random_value(n + 20.0) * 0.05, random_value(n + 30.0) * 6.283185);
		// Merge coverage rather than stacking opacity at every overlap.
		if (stamp.x > merged.x) { merged = stamp; }
	}
	// A small albedo variation from GPT's fine tissue marks, without relief,
	// normals, directional lighting or a change to the approved color tile.
	color *= clamp(1.0 + (merged.y - detail_midpoint) * detail_strength, 0.92, 1.08);
	COLOR = vec4(color, merged.x * amount * COLOR.a);
}
