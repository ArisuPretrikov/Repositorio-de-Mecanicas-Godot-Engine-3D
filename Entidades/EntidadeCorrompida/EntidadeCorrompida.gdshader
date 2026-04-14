shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// --- Parâmetros expostos no Inspetor ---
uniform float speed : hint_range(0.05, 5.0, 0.05) = 0.8;
uniform float noise_scale : hint_range(1.0, 20.0, 0.1) = 6.0;
uniform float core_radius : hint_range(0.0, 0.49, 0.01) = 0.12;
uniform float edge_softness : hint_range(0.01, 0.5, 0.01) = 0.28;

// -------------------------------------------------------
//  Funções de ruído
// -------------------------------------------------------

vec2 _hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123) * 2.0 - 1.0;
}

// Gradient noise (base Perlin)
float _gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f); // curva suave Hermite

	float a = dot(_hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(_hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(_hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(_hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// FBM (Fractal Brownian Motion) — 5 oitavas para forma orgânica e caótica
float fbm(vec2 p) {
	float val       = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	mat2  rot       = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)); // rotação entre oitavas

	for (int i = 0; i < 5; i++) {
		val       += amplitude * _gradient_noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
		p          = rot * p; // girar evita artefatos de alinhamento
	}
	return val * 0.5 + 0.5; // remapeia [-1,1] → [0,1]
}

// -------------------------------------------------------
//  Fragment
// -------------------------------------------------------
void fragment() {
	vec2 uv   = UV - vec2(0.5);       // centraliza: (0,0) no meio
	float dist = length(uv);

	// --- Fluxo radial ---
	// Desloca as coordenadas de amostragem PARA FORA ao longo do tempo.
	// O ponto de origem (centro) permanece sempre o mais denso porque
	// dist ≈ 0 recebe deslocamento mínimo.
	vec2 dir          = dist > 0.001 ? normalize(uv) : vec2(0.0, 1.0);
	float radial_shift = dist - TIME * speed * 0.12;          // expansão
	vec2 animated_uv  = uv + dir * radial_shift;               // coordenada deslizada

	// Adiciona deriva caótica suave perpendicular à direção radial
	vec2 perp       = vec2(-dir.y, dir.x);
	animated_uv    += perp * sin(TIME * speed * 0.4 + dist * 8.0) * 0.04;

	// Amostra o FBM na posição animada
	float n = fbm(animated_uv * noise_scale);

	// "Aguça" o ruído para criar manchas densas de preto, não um degradê plano
	float noise_mask = smoothstep(0.35, 0.72, n);

	// --- Máscara radial de dissipação ---
	// core_radius  → borda interna do fade (alpha máximo dentro)
	// edge_radius  → borda externa (totalmente transparente)
	float edge_radius = core_radius + edge_softness;
	float radial_mask = 1.0 - smoothstep(core_radius, edge_radius, dist);

	// Alpha final: ruído × máscara radial
	float alpha = noise_mask * radial_mask;

	ALBEDO = vec3(0.0); // preto absoluto
	ALPHA  = alpha;
}
