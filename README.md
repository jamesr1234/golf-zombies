# Golf Zombies

Local co-op survival golf: one or two players play nine procedurally generated
holes while zombies try to eat them. One shared ball, one club, one scorecard.
A double bogey costs money and you play on. Par or better pays into the pot.

## Requirements

- Godot **4.6.x** (developed against 4.6.1 stable, Forward+ renderer, Jolt physics)
- One PlayStation-style controller for 1-player (keyboard also works). Two
  controllers for 2-player co-op.

## Running

Open the project in Godot and press F5, or from the command line:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

The title screen picks **1 Player** or **2 Player**, then Easy / Medium / Hard /
Impossible.

- **1 Player:** full screen, keyboard or one pad, plus a CPU partner who
  follows, shoots, revives, and rides shotgun. Hold Circle / E to send the CPU
  to take the golf shot.
- **2 Player:** split-screen co-op. Player 1 uses controller 1 (keyboard still
  works on that seat). Player 2 uses controller 2.

## Controls

| Action | Keyboard (1P / P1) | Controller |
| --- | --- | --- |
| Move | WASD | Left stick |
| Aim | Mouse | Right stick |
| Sprint | Shift | Click left stick |
| Jump | Space | Cross |
| Shoot / cart boost | Left click | R2 |
| Aim down sights | Right click | L2 |
| Reload | R | Square |
| Melee shove | Q | L1 |
| Swap weapon | Tab | D-pad up/down |
| Interact: ball, then cart | E | Circle |
| CPU golf shot (1P, hold) | E | Circle |
| Revive partner (hold) | F | Triangle |
| Swing (all three clicks) | Left click | R2 |
| Pause | Esc | Options |

## Rules

- Walk up to the ball and press interact to become the golfer. Whoever gets
  there first owns the shot; press interact again to walk away from it. In
  1-player, hold interact to send the CPU partner to take the shot instead.
- The golfer is rooted in place and still takes damage. Getting hit mid-swing
  cancels the swing at no cost. The claim is released once the shot resolves, so
  you always have to walk to the ball.
- The swing is three clicks: start the backswing, click at the top to set power,
  click at the bottom for contact. A fast tap-tap is a short chip off the green,
  or a putt on the green and its collar. There is one club and no yardage readout
  anywhere, so judge the distance off the flag. A pink beam goes from the pin
  straight up into the sky so you can always see where the hole is.
- A cart waits behind every tee. Interact next to it to hop in: first one aboard
  drives (looking forward, hands on a cartoon wheel that turns with the stick),
  the second rides shotgun and can still look around and shoot. Hold R2 / click
  while driving for a little extra speed and a drift; hop out and that button
  shoots again. Anything you drive into at speed gets run over, and a new hole
  turns you out.
- Water and out of bounds cost one stroke and replay from the previous spot.
- Each hole allows par + 2 strokes. Come to rest on the last allowed stroke
  without holing out and the run ends.
- At zero health a player goes down and bleeds out over 45 seconds. The partner
  holds revive nearby for three seconds to bring them back. Nobody left standing
  ends the run.
- Melee (Q / L1) launches a zombie from where you hit them. Killing one this way
  leaves them flying for a second, then they explode into neon fireworks. Gun and
  cart kills burst on the spot.

## Layout

```
scripts/core      splitscreen root, input map, scorecard, match flow, difficulty
scripts/player    player controller, camera, robot body, raygun, health, weapons
scripts/golf      ball physics, swing meter, launch tuning, golf mode
scripts/course    seeded hole generator, heightmap, hole builder, surfaces, cup
scripts/zombies   zombie behaviour, archetype stats, spawn director
scripts/vehicles  the golf cart: driving, seats, running zombies over
scripts/ui        title menu, per-viewport HUD and swing meter drawing
resources         weapon and zombie tuning resources
assets/shaders    neon grid surfaces and the night sky
scenes            title menu, split-screen shell, world, player, ball, cart, zombie, HUD
tests/unit        GUT tests
```

## Look

The course plays at night under a synthwave sky, so the only things that read at
distance are the ones that glow. Every mesh is still a primitive built in code by
`scripts/course/mesh_factory.gd`, and every colour comes from
`scripts/core/palette.gd` except the surface lies, which own their grid looks in
`Surface.LOOK`. The ground and each patch use `assets/shaders/neon_grid.gdshader`,
where the grid cell shrinks as the lie improves: wide dim cells for rough, tight
bright ones for the green, and a scrolling blue grid for water. That, rather than
any label, is how you read the hole. Both players carry a lamp in their own colour
and the ball glows on its own, since moonlight alone will not show you your footing
or where your drive ended up. Each hole is a heightmap (`scripts/course/height_field.gd`)
with a gentle grade down the fairway, like a real course: a couple of metres of
rise or fall, a flat tee and green, and proper hills out in the rough. The fairway
is the bright green strip down the middle. Zombies burst into neon fireworks when they die. A melee kill
throws them from the hit point and the burst waits a second, so you see the body
fly before it goes.

Claiming the ball walks the golfer into a stance beside it and pulls the camera well
back, so you watch your own player swing the club rather than staring down a
crosshair. The club pose is read straight off the meter in
`scripts/golf/golf_club.gd`, which means the arc you see is the swing you are
timing. The shot then draws its flight line in the air behind the ball
(`scripts/fx/ball_trail.gd`) and that line fades a couple of seconds after the ball
settles, so it shows you the shape of the shot without leaving a yardage marker on
the hole.

Each player is a blocky humanoid robot in their own colour (`scripts/player/player_body.gd`)
carrying a raygun (`scripts/player/raygun.gd`). Both are driven by one number, the
fraction of a sprint the player is actually travelling at, so the stride and the gun
bob always agree and the run fades in and out instead of snapping between an idle and
a run. The gun rides up and down while you move and locks dead still the moment the
trigger goes down, so a shot is never taken from a swinging gun. It also sits on its
own render layer, which is how the lamp the player carries lights the world without
washing out the gun a hand's width from the lens.

The cart is deliberately not solid to bodies (`Layers.VEHICLE_MASK`): trees and
barriers stop it, but zombies and players do not, so a fast pass ploughs through a
pack instead of grinding to a halt on the first one. Damage scales with speed in
`GolfCart.crush_damage`, which flattens walkers and runners outright and wears a
brute down over a few passes. Steering is tied to speed, so a parked cart cannot
pirouette. The driver camera is locked to the cart heading; a goofy wheel in
`scripts/vehicles/steering_wheel.gd` turns with the stick and carries a pair of
chunky hands tinted to whoever is driving.

## Tests

The suite covers the scorecard boundary, the swing meter, hole generation, the
health and revive rules, and an integration pass over a live world.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Tuning knobs live at the top of their own scripts: `Shot` for how far the club
hits, `SwingMeter` for timing, `Surface` for how each lie rolls, `SpawnDirector`
and `GameSettings` for zombie pressure, and `Health` for downed and revive timings.
