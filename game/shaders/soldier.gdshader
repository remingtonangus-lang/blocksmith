// GPU-animated soldiers (one MultiMesh per body type). INSTANCE_CUSTOM: x = gait phase (cycles), y = state
// (0 idle, 1 walk, 2 run, 3 aim, 4 crouch-aim, 5 dead, 6 fire recoil pulse adds .x fraction), z = palette index,
// w = aim pitch (radians). UV2.x = bone, COLOR.r = material slot. Poses are procedural: walk/run cycles with
// opposed arm swing, a shouldered aim with pitch, crouching, and a limp pose for the dead.
shader_type spatial;
render_mode cull_back;

uniform vec3 palette[64];        // 8 palettes x 8 slots
uniform float far_fade = 1800.0;
global uniform float weather_wetness;

varying float v_slot;
varying float v_pal;

const vec3 PIV[11] = vec3[](vec3(0.0, 0.95, 0.0), vec3(0.0, 1.48, 0.0), vec3(-0.21, 1.42, 0.0), vec3(-0.21, 1.14, 0.0),
	vec3(0.21, 1.42, 0.0), vec3(0.21, 1.14, 0.0), vec3(-0.1, 0.93, 0.0), vec3(-0.1, 0.5, 0.0),
	vec3(0.1, 0.93, 0.0), vec3(0.1, 0.5, 0.0), vec3(0.18, 1.2, -0.1));

vec3 rot_x(vec3 p, vec3 piv, float a) {
	vec3 d = p - piv;
	float c = cos(a);
	float s = sin(a);
	return piv + vec3(d.x, d.y * c - d.z * s, d.y * s + d.z * c);
}

vec3 rot_z(vec3 p, vec3 piv, float a) {
	vec3 d = p - piv;
	float c = cos(a);
	float s = sin(a);
	return piv + vec3(d.x * c - d.y * s, d.x * s + d.y * c, d.z);
}

vec3 rot_y(vec3 p, vec3 piv, float a) {
	vec3 d = p - piv;
	float c = cos(a);
	float s = sin(a);
	return piv + vec3(d.x * c + d.z * s, d.y, -d.x * s + d.z * c);
}

void vertex() {
	int bone = int(UV2.x);
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	int state = int(INSTANCE_CUSTOM.y + 0.01);
	float aim = INSTANCE_CUSTOM.w;
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	// Per-state pose parameters (angles in radians; positive x-rotation tips -Z forward parts down).
	float gait = state == 1 ? 0.45 : (state == 2 ? 0.75 : 0.0);
	float thigh_l = sin(phase) * gait;
	float thigh_r = -sin(phase) * gait;
	float knee_l = max(0.0, -cos(phase)) * gait * 1.4 + 0.05;
	float knee_r = max(0.0, cos(phase)) * gait * 1.4 + 0.05;
	float bob = abs(sin(phase)) * 0.04 * gait;
	float lean = state == 2 ? 0.18 : 0.04 * gait;
	float arm_l = -sin(phase) * gait * 0.7;
	float arm_r = sin(phase) * gait * 0.7;
	float fore_l = 0.35 + gait * 0.3;
	float fore_r = 0.35 + gait * 0.3;
	float root_drop = 0.0;
	bool aiming = state == 3 || state == 4;
	if (state == 4) {
		root_drop = 0.38;
		thigh_l = -1.35; knee_l = 2.3;
		thigh_r = -0.1; knee_r = 1.9;
		lean = 0.15;
	}
	if (state == 0) {
		arm_l = 0.05; arm_r = 0.05;
	}
	// Torso and head.
	vec3 root = PIV[0];
	if (bone <= 5 || bone == 10) {
		p = rot_x(p, root, -lean);
		n = rot_x(n, vec3(0.0), -lean);
	}
	if (bone == 1) {
		float look = aiming ? aim * 0.8 : sin(INSTANCE_CUSTOM.x * 1.3) * 0.1;
		p = rot_x(p, PIV[1], look);
	}
	// Arms. When aiming both upper arms swing forward (shoulder the weapon), else they swing with the gait.
	if (bone == 2 || bone == 3) {
		float up = aiming ? 1.3 + aim : arm_l;
		float fo = aiming ? 0.5 : fore_l;
		if (bone == 3) { p = rot_x(p, PIV[3], fo); n = rot_x(n, vec3(0.0), fo); }
		p = rot_x(p, PIV[2], up);
		n = rot_x(n, vec3(0.0), up);
		if (aiming) { p = rot_y(p, PIV[2], -0.45); }
		p = rot_x(p, root, -lean);
	}
	if (bone == 4 || bone == 5) {
		float up = aiming ? 1.05 + aim : arm_r;
		float fo = aiming ? 1.3 : fore_r;
		if (bone == 5) { p = rot_x(p, PIV[5], fo); n = rot_x(n, vec3(0.0), fo); }
		p = rot_x(p, PIV[4], up);
		n = rot_x(n, vec3(0.0), up);
		if (aiming) { p = rot_y(p, PIV[4], 0.25); }
		p = rot_x(p, root, -lean);
	}
	// Weapon: shouldered along the aim line, or carried at low ready across the body.
	if (bone == 10) {
		vec3 w = p;
		if (aiming) {
			w = rot_x(w, vec3(0.0), -aim);
			w += vec3(0.16, 1.42, -0.32);
		} else {
			w = rot_y(w, vec3(0.0), 0.55);
			w = rot_x(w, vec3(0.0), 0.45);
			w += vec3(0.05, 1.12 - bob * 0.5, -0.24);
		}
		p = rot_x(w, root, -lean);
	}
	// Legs.
	if (bone == 6 || bone == 7) {
		if (bone == 7) { p = rot_x(p, PIV[7], -knee_l); n = rot_x(n, vec3(0.0), -knee_l); }
		p = rot_x(p, PIV[6], -thigh_l);
		n = rot_x(n, vec3(0.0), -thigh_l);
	}
	if (bone == 8 || bone == 9) {
		if (bone == 9) { p = rot_x(p, PIV[9], -knee_r); n = rot_x(n, vec3(0.0), -knee_r); }
		p = rot_x(p, PIV[8], -thigh_r);
		n = rot_x(n, vec3(0.0), -thigh_r);
	}
	if (bone != 6 && bone != 7 && bone != 8 && bone != 9) {
		p.y -= root_drop;
	} else if (state == 4) {
		p.y -= root_drop * 0.15;
	}
	p.y += bob;
	// Dead: limp limbs (the instance transform lays the body down).
	if (state == 5) {
		p = VERTEX;
		n = NORMAL;
		if (bone == 2 || bone == 3) p = rot_z(p, PIV[2], 1.2);
		if (bone == 4 || bone == 5) p = rot_z(p, PIV[4], -0.9);
		if (bone == 10) p += vec3(0.5, -0.9, 0.3);
	}
	VERTEX = p;
	NORMAL = normalize(n);
	v_slot = COLOR.r * 8.0;
	v_pal = INSTANCE_CUSTOM.z;
}

void fragment() {
	int slot = int(v_slot);
	int pal = int(v_pal + 0.5);
	vec3 c = palette[clamp(pal * 8 + slot, 0, 63)];
	float rough = slot == 0 ? 0.15 : (slot == 4 ? 0.35 : (slot == 3 ? 0.6 : 0.5));
	float metal = slot == 4 ? 0.6 : 0.0;
	ALBEDO = c * mix(1.0, 0.8, weather_wetness);
	ROUGHNESS = mix(rough, rough * 0.5, weather_wetness);
	METALLIC = metal;
	SPECULAR = slot == 0 ? 0.9 : 0.5;
}
