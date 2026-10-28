shader_type canvas_item;
// Gentle swimming wave for a fish sprite cut from an atlas: the tail end of
// the frame sways up and down, the head stays still.
// `region` is the frame's rect in atlas UV space (x, y, w, h).

uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool tail_right = false;   // false: the tail is at the left of the frame
uniform float amount = 0.05;       // sway, as a fraction of the frame height
uniform float speed = 8.0;
uniform float phase = 0.0;         // per-fish offset so they don't swim in sync

void fragment() {
	vec2 local = (UV - region.xy) / region.zw;
	float tail = tail_right ? local.x : 1.0 - local.x;
	float weight = smoothstep(0.4, 1.0, tail);
	float wave = sin(TIME * speed + phase - local.x * 7.0) * amount * weight;
	vec2 uv = UV + vec2(0.0, wave * region.w);
	// Never sample outside this frame (the neighbouring sprite would bleed in).
	float inside = step(region.y, uv.y) * step(uv.y, region.y + region.w);
	COLOR = texture(TEXTURE, uv) * COLOR * inside;
}
