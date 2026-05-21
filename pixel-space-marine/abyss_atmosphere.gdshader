shader_type canvas_item;

uniform vec2 map_size = vec2(1024.0, 1024.0);
uniform vec4 top_tint : source_color = vec4(0.03, 0.05, 0.09, 0.15);
uniform vec4 bottom_tint : source_color = vec4(0.00, 0.00, 0.00, 0.55);
uniform float dust_alpha = 0.22;
uniform float dust_tiling = 8.0;
uniform float dust_speed = 0.06;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amp;
		p = p * 2.03 + vec2(23.1, 91.7);
		amp *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float depth = clamp(uv.y, 0.0, 1.0);
	vec4 grad = mix(top_tint, bottom_tint, depth);

	vec2 world_uv = (VERTEX.xy / max(map_size, vec2(1.0))) * dust_tiling;
	world_uv += vec2(TIME * dust_speed, -TIME * dust_speed * 0.45);
	float dust = smoothstep(0.48, 0.82, fbm(world_uv));
	float dust_mask = mix(0.6, 1.15, depth);
	float a = clamp(grad.a + dust * dust_alpha * dust_mask, 0.0, 1.0);

	vec3 tint = grad.rgb + vec3(dust * 0.08, dust * 0.1, dust * 0.15);
	COLOR = vec4(tint, a);
}
