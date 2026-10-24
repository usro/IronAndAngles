class_name AudioMath
extends RefCounted
## Pure sound-propagation math for the AudioDirector: arrival delay at the speed of sound,
## distance loudness, air absorption (a low-pass that closes with distance) and stereo pan.
## Distances are world meters (GameConstants), like every position on EventBus.

const SPEED_OF_SOUND_M_S := 343.0
## Loudness falls off gently (a game, not a field recording): -10·log10(1 + d / REFERENCE).
## 220 m ≈ -6.7 dB, 1 km ≈ -12.5 dB, 2.4 km ≈ -16 dB.
const REFERENCE_DISTANCE_M := 60.0
const MIN_GAIN_DB := -30.0
## Air absorbs highs: the low-pass cutoff is MAX · e^(−d / FALLOFF), clamped to [MIN, MAX].
## 220 m ≈ 14 kHz, 1 km ≈ 5.9 kHz, 2.4 km ≈ 1.25 kHz.
const CUTOFF_MAX_HZ := 18000.0
const CUTOFF_MIN_HZ := 600.0
const CUTOFF_FALLOFF_M := 900.0
## A source at the screen edge pans this far (never hard left/right).
const PAN_WIDTH := 0.8
## Without a camera, a source this far to the side (meters) pans fully.
const PAN_FALLBACK_SPAN_M := 400.0
## Below this linear level a bus is muted instead of set to a huge negative dB.
const SILENT_LINEAR := 0.001


## Seconds a sound from source_m takes to reach listener_m.
static func arrival_delay(source_m: Vector2, listener_m: Vector2) -> float:
	return source_m.distance_to(listener_m) / SPEED_OF_SOUND_M_S


static func distance_gain_db(distance_m: float) -> float:
	var d := maxf(distance_m, 0.0)
	return maxf(-10.0 * log(1.0 + d / REFERENCE_DISTANCE_M) / log(10.0), MIN_GAIN_DB)


static func distance_cutoff_hz(distance_m: float) -> float:
	var d := maxf(distance_m, 0.0)
	return clampf(CUTOFF_MAX_HZ * exp(-d / CUTOFF_FALLOFF_M), CUTOFF_MIN_HZ, CUTOFF_MAX_HZ)


## offset_px: the source's horizontal distance from the screen centre, in screen pixels.
static func pan_from_screen(offset_px: float, half_width_px: float) -> float:
	if half_width_px <= 0.0:
		return 0.0
	return clampf(offset_px / half_width_px, -1.0, 1.0) * PAN_WIDTH


## Fallback when there is no camera: pan by the source's x offset from the listener.
static func pan_from_offset(dx_m: float) -> float:
	return clampf(dx_m / PAN_FALLBACK_SPAN_M, -1.0, 1.0) * PAN_WIDTH


## Volume slider (0..1) to bus dB; 0 and below is silence.
static func slider_to_db(linear: float) -> float:
	return linear_to_db(linear) if linear > SILENT_LINEAR else -80.0


## A random factor in [1 - spread, 1 + spread], so repeated sounds are never identical.
static func vary(rng: RandomNumberGenerator, spread: float) -> float:
	return 1.0 + rng.randf_range(-spread, spread)
