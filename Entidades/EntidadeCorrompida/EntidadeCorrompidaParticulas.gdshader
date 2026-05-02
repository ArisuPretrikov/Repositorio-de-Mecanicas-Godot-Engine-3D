shader_type particles;
render_mode keep_data;

// Quantas voltas completas a partícula dá ao longo da vida
uniform float angular_speed : hint_range(0.1, 5.0, 0.1) = 1.5;
// Taxa de crescimento logarítmico vertical (b em: y = scale * e^(b*θ))
uniform float spiral_b : hint_range(0.05, 0.8, 0.01) = 0.2;
// Escala de altura máxima da espiral
uniform float spiral_scale : hint_range(0.01, 3.0, 0.05) = 0.5;
// Raio horizontal do enrolamento em torno de XZ
uniform float horiz_scale : hint_range(0.0, 1.0, 0.01) = 0.15;
// Amplitude do wobble lateral aleatório
uniform float wobble_amount : hint_range(0.0, 1.0, 0.05) = 0.25;
// Velocidade de translação aleatória por partícula (unidades/s)
uniform float drift_speed : hint_range(0.0, 5.0, 0.05) = 0.8;
// Tamanho base de cada partícula
uniform float particle_size : hint_range(0.01, 1.0, 0.01) = 0.1;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void start() {
	float s = float(INDEX);
	CUSTOM.x = hash(s * 1.7319) * TAU;   // ângulo inicial da espiral
	CUSTOM.y = hash(s * 2.3141) * TAU;   // ângulo de drift aleatório no plano XZ
	// CUSTOM.z codifica dois valores: z>0.5 = anti-horário, z<=0.5 = horário
	// fract(z*2) extrai o fator aleatório [0,1) dentro de cada metade
	CUSTOM.z = hash(s * 3.7145);
	CUSTOM.w = hash(s * 5.1729) * 0.15;  // offset de idade inicial

	float tiny = 0.001;
	TRANSFORM[0].xyz = vec3(tiny, 0.0,  0.0);
	TRANSFORM[1].xyz = vec3(0.0,  tiny, 0.0);
	TRANSFORM[2].xyz = vec3(0.0,  0.0,  tiny);
	TRANSFORM[3].xyz = vec3(0.0);
	VELOCITY = vec3(0.0);
	COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	ACTIVE = true;
}

void process() {
	float age = CUSTOM.w + DELTA / LIFETIME;
	CUSTOM.w = age;

	if (age >= 1.0) {
		ACTIVE = false;
	} else {
		float init_angle  = CUSTOM.x;
		float drift_angle = CUSTOM.y;
		float z_val       = CUSTOM.z;

		float dir = z_val > 0.5 ? 1.0 : -1.0;
		float rnd = fract(z_val * 2.0);

		float b     = spiral_b * (0.7 + rnd * 0.6);
		float scale = spiral_scale * (0.5 + rnd * 0.5);

		float theta_swept = dir * angular_speed * TAU * age;
		float theta       = init_angle + theta_swept;

		// Espiral logarítmica de baixo para cima:
		// Y cresce exponencialmente com o ângulo varrido — a altura É a espiral.
		// XZ fornece o enrolamento em torno dos eixos X e Z com raio compacto.
		float py = scale * (exp(b * abs(theta_swept)) - 1.0);

		float r_h      = horiz_scale * (0.5 + rnd * 0.8);
		float wobble_r = sin(age * 11.3 * TAU + rnd * 17.0) * wobble_amount * r_h;
		float wobble_a = sin(age * 7.7  * TAU + rnd * 13.0) * wobble_amount * 0.4;
		float r = r_h + wobble_r;

		float px = r * cos(theta + wobble_a);
		float pz = r * sin(theta + wobble_a);

		// Drift translacional: cada partícula segue uma direção fixa aleatória
		float elapsed = age * LIFETIME;
		px += cos(drift_angle) * drift_speed * elapsed;
		pz += sin(drift_angle) * drift_speed * elapsed;

		// Curva de escala: nasce pequena, cresce, some no final
		float grow   = smoothstep(0.0, 0.15, age);
		float shrink = smoothstep(1.0, 0.7,  age);
		float ps     = particle_size * (0.5 + rnd) * grow * shrink;

		TRANSFORM[0].xyz = vec3(ps, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, ps, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, ps);
		TRANSFORM[3].xyz = vec3(px, py, pz);
		VELOCITY = vec3(0.0);

		COLOR.a = shrink;
	}
}
