shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.32, 0.34, 0.36, 1.0);
uniform vec4 line_color : source_color = vec4(0.55, 0.58, 0.62, 1.0);
uniform vec4 major_line_color : source_color = vec4(0.78, 0.80, 0.84, 1.0);
uniform float grid_step = 1.0;
uniform float line_width = 0.03;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 coord = world_pos / max(grid_step, 0.001);
	vec2 plane_uv = abs(world_normal.y) > 0.5 ? coord.xz : (abs(world_normal.x) > 0.5 ? coord.zy : coord.xy);
	vec2 grid_dist = abs(fract(plane_uv - 0.5) - 0.5);
	float minor_line = 1.0 - smoothstep(line_width * 0.5, line_width, min(grid_dist.x, grid_dist.y));

	vec2 major_uv = plane_uv * 0.1;
	vec2 major_dist = abs(fract(major_uv - 0.5) - 0.5);
	float major_line = 1.0 - smoothstep(line_width * 0.15, line_width * 0.3, min(major_dist.x, major_dist.y));

	vec3 color = mix(base_color.rgb, line_color.rgb, minor_line);
	color = mix(color, major_line_color.rgb, major_line);
	ALBEDO = color;
	ROUGHNESS = 0.85;
}
