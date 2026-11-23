shader_type spatial;
// Base body: one set of mask textures, tinted per character.
// masks_a: R skin shading, G brows, B scalp hair, A beard
// masks_b: R underwear, G eye whites, B irises, A lips

uniform sampler2D masks_a : filter_linear_mipmap, hint_default_white;
uniform sampler2D masks_b : filter_linear_mipmap, hint_default_black;
uniform vec3 skin_tone : source_color = vec3(0.78, 0.56, 0.42);
uniform vec3 hair_color : source_color = vec3(0.22, 0.14, 0.08);
uniform vec3 eye_color : source_color = vec3(0.25, 0.35, 0.5);
uniform vec3 underwear_color : source_color = vec3(0.3, 0.32, 0.35);
uniform float scalp_hair : hint_range(0.0, 1.0) = 1.0;
uniform float beard : hint_range(0.0, 1.0) = 0.0;
uniform float brows : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 a = texture(masks_a, UV);
	vec4 b = texture(masks_b, UV);
	float shade = a.r;
	vec3 c = skin_tone * shade;
	c = mix(c, c * vec3(1.15, 0.72, 0.72), b.a * 0.7);                    // lips
	vec3 hair = hair_color * (0.7 + 0.3 * shade);
	c = mix(c, hair, clamp(a.g * brows, 0.0, 1.0));
	c = mix(c, hair, clamp(a.b * scalp_hair, 0.0, 1.0));
	c = mix(c, hair, clamp(a.a * beard, 0.0, 1.0));
	c = mix(c, underwear_color * shade, b.r);
	c = mix(c, vec3(0.9, 0.9, 0.86), b.g);
	c = mix(c, eye_color * 0.8, b.b);
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
