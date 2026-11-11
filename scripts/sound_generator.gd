# sound_generator.gd
class_name SoundGenerator
extends Node

static func create_beep(freq: float = 440.0, duration: float = 0.15, volume: float = 0.3) -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := int(sample_rate * duration)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var envelope := 1.0 - (float(i) / float(num_samples))
		var val := sin(t * freq * TAU) * envelope * volume
		var ival := clampi(int(val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, ival)
		
	stream.data = data
	return stream

static func create_laser(duration: float = 0.18, volume: float = 0.35) -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := int(sample_rate * duration)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var freq := lerpf(1200.0, 200.0, progress * progress)
		var t := float(i) / float(sample_rate)
		var envelope := 1.0 - progress
		var val := sin(t * freq * TAU) * envelope * volume
		var ival := clampi(int(val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, ival)
		
	stream.data = data
	return stream

static func create_thruster(duration: float = 0.3, volume: float = 0.25) -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := int(sample_rate * duration)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	
	var last := 0.0
	for i in range(num_samples):
		var noise := randf_range(-1.0, 1.0)
		last = lerpf(last, noise, 0.2)
		var progress := float(i) / float(num_samples)
		var envelope := sin(progress * PI)
		var val := last * envelope * volume
		var ival := clampi(int(val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, ival)
		
	stream.data = data
	return stream

static func create_explosion(duration: float = 0.45, volume: float = 0.4) -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := int(sample_rate * duration)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	
	var last := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var noise := randf_range(-1.0, 1.0)
		last = lerpf(last, noise, 0.08)
		var envelope := (1.0 - progress) * (1.0 - progress)
		var val := last * envelope * volume
		var ival := clampi(int(val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, ival)
		
	stream.data = data
	return stream

static func create_build(duration: float = 0.12, volume: float = 0.3) -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := int(sample_rate * duration)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var freq := lerpf(400.0, 900.0, progress)
		var t := float(i) / float(sample_rate)
		var envelope := 1.0 - progress
		var val := (sin(t * freq * TAU) + 0.5 * sin(t * freq * 2.0 * TAU)) * envelope * volume * 0.7
		var ival := clampi(int(val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, ival)
		
	stream.data = data
	return stream
