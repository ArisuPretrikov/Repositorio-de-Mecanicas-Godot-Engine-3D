shader_type canvas_item;

// Para SubViewportContainer (ou qualquer CanvasItem) — pós-processamento simples.

// Intensidade da inversão de cores: 0 = original, 1 = totalmente invertida (negativo).
// Valores intermediários fazem blend (0.5 = meio-cinza com cores misturadas).
uniform float invert : hint_range(0.0, 1.0, 0.01) = 0.0;

// 0.0 = totalmente cinza (grayscale), 1.0 = cor normal, > 1.0 = cor mais saturada.
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	// Mistura linear entre cor original e cor invertida (1.0 - col.rgb).
	col.rgb = mix(col.rgb, 1.0 - col.rgb, invert);

	// Luminância perceptual (pesos Rec. 601). Mistura entre cinza e cor original.
	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(vec3(gray), col.rgb, saturation);

	COLOR = col;
}
