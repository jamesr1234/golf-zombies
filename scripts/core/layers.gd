class_name Layers
extends Object
## Central collision layer/mask bits so no script hardcodes magic numbers.

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ZOMBIE := 1 << 2
const BALL := 1 << 3
const BARRIER := 1 << 4
const PROP := 1 << 5
const PICKUP := 1 << 6
const SURFACE := 1 << 7
const VEHICLE := 1 << 8
const SHIELD := 1 << 9
## Deployed hex fort. Zombies and carts collide; players walk and shoot through.
const FORT := 1 << 10
## Cup well. Only the ball collides, so players do not fall in with it.
const CUP := 1 << 11
## Clubhouse mech. Players walk the stairs; rockets hit the hull.
const MECH := 1 << 12
## Fairway lip. Ball, players, carts, and zombies bounce; shots pass through.
const FORCEFIELD := 1 << 13

## Ground and props stop the ball, barriers deliberately do not (leaving the
## course is an out-of-bounds penalty, not a bounce). The well is added only
## while the ball is dropping in, so a fast putt can still rattle over the lip.
## The lip field is the exception: it kicks a shot back onto the landing strip.
const BALL_MASK := WORLD | PROP | FORCEFIELD
const PLAYER_MASK := WORLD | ZOMBIE | BARRIER | PROP | VEHICLE | MECH | FORCEFIELD
const ZOMBIE_MASK := WORLD | PLAYER | BARRIER | PROP | FORT | FORCEFIELD
const BULLET_MASK := WORLD | ZOMBIE | PROP | MECH
## Enemy bolts hit a planted shield and the players behind it. Friendly fire
## stays on BULLET_MASK, so a partner can still shoot through the panel.
const ENEMY_SHOT_MASK := WORLD | PLAYER | SHIELD | PROP | BARRIER | FORT
## The cart is stopped by scenery but not by bodies: zombies are there to be run
## over, and a player on foot should never be shoved around by their own ride.
const VEHICLE_MASK := WORLD | BARRIER | PROP | FORT | MECH | FORCEFIELD
## Grapple claw. Hits rides and scenery, flies through people and the undead.
const HOOK_MASK := WORLD | PROP | BARRIER | FORT | VEHICLE | MECH
