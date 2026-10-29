extends RefCounted
## Game pursuit, separate from measured watts and workout scoring.
static func speed(base: float, rider: float, gap: float, awake: bool, grace: bool, surge: bool, handicap: float = 80.0) -> float:
 if grace:
  return base * 0.3
 # Outside the selected head start, smoothly recover the excess gap.
 # Once back within the handicap, ordinary pace governs the pursuit again.
 var target := 8.0 if awake and surge else maxf(8.0, handicap)
 var closing := clampf((gap - target) * 0.035, 0.0, 1.5)
 if awake and surge and gap > target:
  closing = maxf(0.9, closing)
 if gap > target:
  return maxf(base, rider + closing)
 return base

# First a stumble, then easy pursuit, then a smooth return to ordinary speed.
# Never apply the gap-closing buff during this window.
static func recovery_speed(base: float, remaining: float, total: float) -> float:
 if remaining <= 0.0:
  return base
 var elapsed := maxf(0.0, total - remaining)
 if elapsed < 3.0:
  return base * 0.15
 var ramp := clampf((4.0 - remaining) / 4.0, 0.0, 1.0)
 return base * lerpf(0.3, 1.0, ramp * ramp * (3.0 - 2.0 * ramp))

static func recovery_seconds(outcome: String) -> float:
 return 6.0 if outcome == "dragged down" else 12.0
