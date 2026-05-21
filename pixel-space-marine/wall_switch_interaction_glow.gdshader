shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 inner_color : source_color = vec4(0.25, 0.92, 1.0, 0.55);
uniform vec4 outer_color : source_color = vec4(0.06, 0.38, 0.58, 0.0);
uniform float quant_steps : hint_range(6.0, 48.0, 1.0) = 18.0;
uniform float inner_radius : hint_range(0.0, 0.55) = 0.14;
uniform float mid_radius : hint_range(0.0, 0.75) = 0.34;
uniform float outer_radius : hint_range(0.0, 1.0) = 0.5;
uniform float inner_alpha_mul : hint_range(0.0, 2.0) = 1.05;
uniform float outer_alpha_mul : hint_range(0.0, 2.0) = 0.88;
uniform float flicker_speed : hint_range(0.0, 40.0) = 11.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.24;

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float d = length(q);
	if (d > 1.001) {
		COLOR = vec4(0.0);
	} else {
		float dq = floor(d * quant_steps) / quant_steps;
		float n = fract(sin(dot(floor(UV * vec2(48.0, 48.0)), vec2(12.9898, 78.233))) * 43758.5453);
		float flick = 1.0 - flicker_amount * 0.5 + flicker_amount * 0.5 * sin(TIME * flicker_speed + n * 6.2831853 + dq * 22.0);

		float inner_mask = 1.0 - step(inner_radius, dq);
		vec3 c_in = inner_color.rgb;
		float a_in = inner_mask * inner_color.a * inner_alpha_mul;

		float ring = step(inner_radius, dq) * (1.0 - step(outer_radius, dq));
		float t = clamp((dq - inner_radius) / max(0.0001, (outer_radius - inner_radius)), 0.0, 1.0);
		float mid_w = smoothstep(mid_radius - 0.04, mid_radius + 0.04, dq) * (1.0 - smoothstep(outer_radius - 0.06, outer_radius, dq));
		vec3 c_ring = mix(inner_color.rgb, outer_color.rgb, t);
		float a_ring = ring * mix(inner_color.a, outer_color.a, t) * outer_alpha_mul * (0.65 + 0.35 * mid_w);

		float a = clamp((a_in + a_ring * (1.0 - a_in)) * flick, 0.0, 1.0);
		vec3 rgb = mix(c_in, c_ring, step(inner_radius, dq));
		COLOR = vec4(rgb, a);
	}
}
