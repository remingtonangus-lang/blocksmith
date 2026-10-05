// Cumulus deck density shared by the sky (what you see) and the cloud-shadow map (what the ground receives), so the
// shadows sweeping the plains belong to the clouds overhead. p = world-anchored deck coordinates (metres * 0.00028).
float cloud_density(vec2 p, float cover) {
	vec2 w = vec2(fbm2(p * 0.6 + 3.1), fbm2(p * 0.6 + 7.7)) * 0.6;
	float base = fbm2(p + w) * 0.5 + 0.5;
	float detail = fbm2(p * 4.3 - w * 2.0) * 0.5 + 0.5;
	float d = base * 0.75 + detail * 0.25;
	float thr = mix(0.78, 0.25, cover);
	return smoothstep(thr, thr + 0.22, d);
}
