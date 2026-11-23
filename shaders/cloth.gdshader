shader_type spatial;
render_mode cull_disabled;  // clothes are open shells: show their inside at the cuffs and collars
// detail: R = shading/seams (x main colour), G = secondary mask (x accent colour)

uniform sampler2D detail : filter_linear_mipmap, hint_default_white;
uniform vec3 main_color : source_color = vec3(0.5);
uniform vec3 accent_color : source_color = vec3(0.08);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	vec4 d = texture(detail, UV);
	vec3 c = mix(main_color, accent_color, d.g) * d.r;
	ALBEDO = FRONT_FACING ? c : c * 0.45;
	ROUGHNESS = roughness;
}
