extends RefCounted
## The shop-door bell, synthesized in code (no audio files): two quick strikes,
## each a mix of bell-like overtones that ring out and fade.

const RATE := 44100
const LENGTH := 1.6                     # seconds
const STRIKES := [0.0, 0.17]            # "ding-ding"
const FUNDAMENTAL := 1568.0             # G6
## [frequency ratio, loudness, decay rate] per overtone. Bells have
## inharmonic overtones, which is what makes them sound like bells.
const PARTIALS := [[1.0, 1.0, 2.4], [2.0, 0.45, 3.2], [2.76, 0.35, 4.5], [5.4, 0.12, 7.0], [0.5, 0.18, 1.6]]
const VOLUME := 0.5


static func make_stream() -> AudioStreamWAV:
	var frames := int(RATE * LENGTH)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var peak := 0.0
	for i in frames:
		var t := float(i) / RATE
		var v := 0.0
		for s in STRIKES.size():
			var local: float = t - STRIKES[s]
			if local < 0.0:
				continue
			var strike_gain := 1.0 if s == 0 else 0.7
			var attack := minf(local / 0.004, 1.0)  # tiny fade-in avoids a click
			for p in PARTIALS:
				v += sin(TAU * FUNDAMENTAL * p[0] * local) * p[1] * exp(-p[2] * local) * attack * strike_gain
		samples[i] = v
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var value := int(clampf(samples[i] / peak * VOLUME, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
