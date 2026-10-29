shader_type sky;
// The painted cube map, turned with the camera's heading so the painted path always lines up with the road behind.
uniform samplerCube sky_cube : source_color, filter_linear;
uniform float yaw = 0.0;

void sky() {
	vec3 d = EYEDIR;
	float c = cos(yaw), s = sin(yaw);
	d = vec3(d.x * c + d.z * s, d.y, -d.x * s + d.z * c);
	d.x = -d.x;   // the painted faces use the other handedness: without this the forest is mirrored
	COLOR = texture(sky_cube, d).rgb;
}
