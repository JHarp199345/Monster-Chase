extends RefCounted
## Correct the baked knee roll while keeping anatomy and both feet on the crank.
static func bone(s: Skeleton3D, suffix: String) -> int:
 for i in s.get_bone_count():
  if s.get_bone_name(i).ends_with(suffix):return i
 return -1
static func solve(s: Skeleton3D, model: Node3D, g: Dictionary, phase: float) -> Array:
 s.clear_bones_global_pose_override()
 s.force_update_all_bone_transforms()
 var result: Array=[]
 var sg:=s.global_transform
 for side in ["Left","Right"]:
  var thigh:=bone(s,side+"UpLeg")
  var shin:=bone(s,side+"Leg")
  var foot:=bone(s,side+"Foot")
  if thigh<0 or shin<0 or foot<0:continue
  var sign_x:=1.0 if side=="Left" else -1.0
  var angle:=phase+(0.0 if side=="Left" else PI)
  var size: float=g.size
  var bb: Array=g.bb
  var crank: float=g.crank
  var up: float=g.get("ankle_up",0.09*size)
  var back: float=g.get("ankle_back",0.06*size)
  var local_target:=Vector3(sign_x*0.11*size,float(bb[2])+cos(angle)*crank+up,sin(angle)*crank-back)
  var target:=model.to_global(local_target)
  var hip:=sg*s.get_bone_global_pose(thigh).origin
  var rt:=sg*s.get_bone_global_rest(thigh).origin
  var rk:=sg*s.get_bone_global_rest(shin).origin
  var rf:=sg*s.get_bone_global_rest(foot).origin
  var a:=rt.distance_to(rk)
  var b:=rk.distance_to(rf)
  var direction: Vector3=(target-hip).normalized()
  var distance:=clampf(hip.distance_to(target),absf(a-b)+0.0001,a+b-0.0001)
  var reached:=hip+direction*distance
  var front:=model.global_basis.orthonormalized()*Vector3.FORWARD*-1.0
  var bend: Vector3=(front-direction*front.dot(direction)).normalized()
  var along: float=(a*a-b*b+distance*distance)/(2.0*distance)
  var knee: Vector3=hip+direction*along+bend*sqrt(maxf(0.0,a*a-along*along))
  var qt:=Quaternion((rk-rt).normalized(),(knee-hip).normalized())
  var qk:=Quaternion((rf-rk).normalized(),(reached-knee).normalized())
  var bt: Basis=Basis(qt)*(sg.basis*s.get_bone_global_rest(thigh).basis)
  var bk: Basis=Basis(qk)*(sg.basis*s.get_bone_global_rest(shin).basis)
  var bf: Basis=(sg.basis*s.get_bone_global_rest(foot).basis)
  s.set_bone_global_pose_override(thigh,sg.affine_inverse()*Transform3D(bt,hip),1.0,true)
  s.set_bone_global_pose_override(shin,sg.affine_inverse()*Transform3D(bk,knee),1.0,true)
  s.set_bone_global_pose_override(foot,sg.affine_inverse()*Transform3D(bf,reached),1.0,true)
  result.append({"side":side,"hip":hip,"knee":knee,"ankle":reached,"target":target,"upper":a,"lower":b})
 return result
## Hands on this bike's grips: two-bone reach from each shoulder, elbows bent down, out and a little back.
## grips: {"Left": Vector3, "Right": Vector3} in the model's space (the same space as the bike).
static func solve_arms(s: Skeleton3D, model: Node3D, grips: Dictionary) -> Array:
 var result: Array=[]
 var sg:=s.global_transform
 for side in ["Left","Right"]:
  var upper:=bone(s,side+"Arm")
  var fore:=bone(s,side+"ForeArm")
  var hand:=bone(s,side+"Hand")
  if upper<0 or fore<0 or hand<0 or not grips.has(side):continue
  var sign_x:=1.0 if side=="Left" else -1.0
  var target:=model.to_global(grips[side])
  var shoulder:=sg*s.get_bone_global_pose(upper).origin
  var ru:=sg*s.get_bone_global_rest(upper).origin
  var rf:=sg*s.get_bone_global_rest(fore).origin
  var rh:=sg*s.get_bone_global_rest(hand).origin
  var a:=ru.distance_to(rf)
  var b:=rf.distance_to(rh)
  var palm:=0.35*b                              # the palm holds the bar, a hand's length beyond the wrist
  var grip_point:=target
  target=target-(target-shoulder).normalized()*palm
  var direction: Vector3=(target-shoulder).normalized()
  var distance:=clampf(shoulder.distance_to(target),absf(a-b)+0.0001,a+b-0.0001)
  var reached:=shoulder+direction*distance
  var mb:=model.global_basis.orthonormalized()
  var bend: Vector3=mb*Vector3(sign_x*0.6,-1.0,-0.3)
  bend=(bend-direction*bend.dot(direction)).normalized()
  var along: float=(a*a-b*b+distance*distance)/(2.0*distance)
  var elbow: Vector3=shoulder+direction*along+bend*sqrt(maxf(0.0,a*a-along*along))
  var qu:=Quaternion((rf-ru).normalized(),(elbow-shoulder).normalized())
  var qf:=Quaternion((rh-rf).normalized(),(reached-elbow).normalized())
  var bu: Basis=Basis(qu)*(sg.basis*s.get_bone_global_rest(upper).basis)
  var bf: Basis=Basis(qf)*(sg.basis*s.get_bone_global_rest(fore).basis)
  var bh: Basis=Basis(qf)*(sg.basis*s.get_bone_global_rest(hand).basis)
  s.set_bone_global_pose_override(upper,sg.affine_inverse()*Transform3D(bu,shoulder),1.0,true)
  s.set_bone_global_pose_override(fore,sg.affine_inverse()*Transform3D(bf,elbow),1.0,true)
  s.set_bone_global_pose_override(hand,sg.affine_inverse()*Transform3D(bh,reached),1.0,true)
  result.append({"side":side,"shoulder":shoulder,"elbow":elbow,"hand":reached,"target":target,"arm":a+b+palm,"reach":shoulder.distance_to(grip_point)})
 return result
## Lean the torso forward until this bike's grips are within comfortable reach (real riders do the same on long,
## low bars); the head comes back up to look down the road. Call after solve() and before solve_arms().
static func solve_torso(s: Skeleton3D, model: Node3D, grips: Dictionary, comfort: float = 0.96) -> float:
 var spine:=bone(s,"Spine")
 var head:=bone(s,"Head")
 var la:=bone(s,"LeftArm");var lf:=bone(s,"LeftForeArm");var lh:=bone(s,"LeftHand");var ra:=bone(s,"RightArm")
 if spine<0 or la<0 or lf<0 or lh<0 or ra<0 or not grips.has("Left"):return 0.0
 s.force_update_all_bone_transforms()
 var sg:=s.global_transform
 var fore:=(sg*s.get_bone_global_rest(lf).origin).distance_to(sg*s.get_bone_global_rest(lh).origin)
 var arm:=(sg*s.get_bone_global_rest(la).origin).distance_to(sg*s.get_bone_global_rest(lf).origin)+fore*1.35   # to the palm
 var hips:=bone(s,"Hips")
 var pivot:=sg*s.get_bone_global_pose(hips if hips>=0 else spine).origin
 var shoulders:=(sg*s.get_bone_global_pose(la).origin+sg*s.get_bone_global_pose(ra).origin)/2.0
 var grip:=model.to_global((grips["Left"]+grips["Right"])/2.0)
 var axis:=model.global_basis.orthonormalized().x
 var best:=0.0
 var best_gap:=INF
 # the smallest lean that reaches: forward up to 75 degrees (long, low bars), or back up to 25 (tall BMX bars)
 for d in [0.0,2.5,-2.5,5.0,-5.0,7.5,-7.5,10.0,-10.0,12.5,-12.5,15.0,-15.0,17.5,-17.5,20.0,-20.0,22.5,-22.5,25.0,-25.0,27.5,30.0,32.5,35.0,37.5,40.0,42.5,45.0,47.5,50.0,52.5,55.0,57.5,60.0,62.5,65.0,67.5,70.0,72.5,75.0]:
  var t:=deg_to_rad(d)
  var reach:=(pivot+Basis(axis,t)*(shoulders-pivot)).distance_to(grip)
  if reach<=comfort*arm:
   best=t;best_gap=0.0;break
  var gap:=reach-comfort*arm
  if gap<best_gap:
   best_gap=gap;best=t
 if best==0.0:return 0.0
 var sp:=sg*s.get_bone_global_pose(spine)
 s.set_bone_global_pose_override(spine,sg.affine_inverse()*Transform3D(Basis(axis,best)*sp.basis,pivot+Basis(axis,best)*(sp.origin-pivot)),1.0,true)
 s.force_update_all_bone_transforms()
 if head>=0:
  var hp:=sg*s.get_bone_global_pose(head)
  s.set_bone_global_pose_override(head,sg.affine_inverse()*Transform3D(Basis(axis,-best*0.7)*hp.basis,hp.origin),1.0,true)
  s.force_update_all_bone_transforms()
 return best
## Fingers wrapped round the bar: each joint curls about the bar's axis (the model's side-to-side axis), after
## solve_arms has put the palms on the grips. The thumb wraps more gently from the other side.
static func solve_fingers(s: Skeleton3D, model: Node3D, curl: float = 1.0) -> void:
 var sg:=s.global_transform
 var axis:=model.global_basis.orthonormalized().x
 for side in ["Left","Right"]:
  for finger in ["Index","Middle","Ring","Pinky","Thumb"]:
   var angles: Array=[0.35,0.5,0.4] if finger=="Thumb" else [0.95,1.1,0.8]
   for j in 3:
    var i:=bone(s,side+"Hand"+finger+str(j+1))
    if i<0:continue
    s.force_update_all_bone_transforms()
    var gp:=sg*s.get_bone_global_pose(i)
    s.set_bone_global_pose_override(i,sg.affine_inverse()*Transform3D(Basis(axis,angles[j]*curl)*gp.basis,gp.origin),1.0,true)
