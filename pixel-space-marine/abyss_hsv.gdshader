shader_type canvas_item;

uniform float hue_shift : hint_range(-1.0, 1.0) = 0.0;
uniform float saturation_mult : hint_range(0.0, 2.0) = 1.0;
uniform float value_mult : hint_range(0.0, 2.0) = 1.0;

vec3 rgb_to_hsv(vec3 c) {
	float c_max = max(c.r, max(c.g, c.b));
	float c_min = min(c.r, min(c.g, c.b));
	float delta = c_max - c_min;
	float h = 0.0;
	if (delta > 0.00001) {
		if (c_max == c.r) {
			h = mod((c.g - c.b) / delta, 6.0);
		} else if (c_max == c.g) {
			h = ((c.b - c.r) / delta) + 2.0;
		} else {
			h = ((c.r - c.g) / delta) + 4.0;
		}
		h /= 6.0;
		if (h < 0.0) {
			h += 1.0;
		}
	}
	float s = 0.0;
	if (c_max > 0.00001) {
		s = delta / c_max;
	}
	float v = c_max;
	return vec3(h, s, v);
}

vec3 hsv_to_rgb(vec3 c) {
	float h = c.x;
	float s = c.y;
	float v = c.z;
	float i = floor(h * 6.0);
	float f = h * 6.0 - i;
	float p = v * (1.0 - s);
	float q = v * (1.0 - f * s);
	float t = v * (1.0 - (1.0 - f) * s);
	float m = mod(i, 6.0);
	if (m < 1.0) return vec3(v, t, p);
	if (m < 2.0) return vec3(q, v, p);
	if (m < 3.0) return vec3(p, v, t);
	if (m < 4.0) return vec3(p, q, v);
	if (m < 5.0) return vec3(t, p, v);
	return vec3(v, p, q);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 hsv = rgb_to_hsv(src.rgb);
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * saturation_mult, 0.0, 1.0);
	hsv.z = clamp(hsv.z * value_mult, 0.0, 1.0);
	COLOR = vec4(hsv_to_rgb(hsv), src.a);
}
