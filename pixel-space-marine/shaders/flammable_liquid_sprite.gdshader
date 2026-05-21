shader_type canvas_item;

uniform float texture_alpha_gain : hint_range(0.0, 4.0, 0.01) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	tex.a = clamp(tex.a * texture_alpha_gain, 0.0, 1.0);
	COLOR = tex * COLOR;
}
