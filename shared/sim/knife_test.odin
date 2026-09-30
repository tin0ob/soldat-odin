package sim

import "core:testing"

// The knife throw, against OpenSoldat's Control.pas: the throw-weapon button starts
// the ThrowWeapon wind-up at Speed 2 (two ticks a frame), and the knife leaves the
// hand the tick the button does — a tap is half the throw — or by itself at frame
// 16, 32 ticks in. The charge is Control.pas's D, the frame clamped between 8 and
// 16 over 16, times Speed * 1.5; the aim leaves the hand. The hand is empty
// afterwards, and a knife that stopped lands as a knife to pick up.

@(private = "file")
Fixture :: struct {
	level:  Level,
	anims:  ^Anims,
	skels:  ^Skeletons,
	ctx:    Context,
	world:  ^World,
	events: Events,
	cmds:   [MAX_PLAYERS]Command,
	aim:    Vec2, // where the cursor is held, which is what the throw follows
}

// One soldier with the knife in hand, landed and out of its spawn protection, facing
// its cursor far to the right.
@(private = "file")
fixture :: proc() -> (f: ^Fixture, ok: bool) {
	f = new(Fixture)
	f.level = level_load_file("assets", "Arena") or_return
	f.anims = anims_load_files("assets") or_return
	f.skels = skeletons_load_files("assets") or_return
	f.ctx = {level = &f.level, anims = f.anims, skeletons = f.skels}
	weapons_default(&f.ctx.weapons)
	f.world = new(World)
	world_init(f.world, 99)
	f.world.authority = true
	round_init(&f.world.round)
	s := &f.world.soldiers[0]
	soldier_spawn(&f.ctx, s, level_spawn_point(&f.level, .Alpha, &f.world.rng), .Alpha, .Knife, .Colt)
	s.cease_fire_counter = -1
	f.aim = {500, 0}
	hold(f, {}, 120) // land and come to rest
	return f, true
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	free(f.world)
	free(f.anims)
	free(f.skels)
	level_destroy(&f.level)
	free(f)
}

// `n` ticks with these buttons held, the cursor kept where the fixture put it.
@(private = "file")
hold :: proc(f: ^Fixture, buttons: Buttons, n: int) {
	s := &f.world.soldiers[0]
	for _ in 0 ..< n {
		f.cmds[0] = {seq = f.cmds[0].seq + 1, buttons = buttons, aim = s.pos + f.aim}
		step(&f.ctx, f.world, f.cmds[:], &f.events)
	}
}

@(private = "file")
thrown_knife :: proc(f: ^Fixture) -> (b: ^Bullet, found: bool) {
	for &b, i in f.world.bullets {
		if b.active && b.weapon == .Thrown_Knife do return &f.world.bullets[i], true
	}
	return nil, false
}

// Holding the throw to frame 16 throws by itself with the full momentum: D is 1
// there, so the thrown knife's speed times one and a half (Control.pas's Speed *
// 1.5). At Speed 2 the wind-up is two ticks a frame, so that is 31 ticks of hold.
@(test)
test_a_full_wind_up_throws_the_knife_with_full_momentum :: proc(t: ^testing.T) {
	f, ok := fixture()
	if !ok do return
	defer fixture_destroy(f)
	s := &f.world.soldiers[0]
	hold(f, {.Drop}, 31)
	b, found := thrown_knife(f)
	testing.expect(t, found, "no thrown knife after a full wind-up")
	if found {
		want := f.ctx.weapons[.Thrown_Knife].speed * 1.5
		testing.expectf(t, vec2_length(b.vel) >= want - 0.5, "full throw velocity %.2f, wanted %.2f", vec2_length(b.vel), want)
	}
	testing.expect_value(t, s.weapon.id, Weapon_Id.None)
}

// Letting the throw button go early throws early with less momentum, so less damage:
// D is the release frame over 16 (the 9th frame here, 16 held ticks plus the
// release), and past frame 8 the charge climbs with the hold.
@(test)
test_an_early_release_throws_with_less_momentum :: proc(t: ^testing.T) {
	f, ok := fixture()
	if !ok do return
	defer fixture_destroy(f)
	hold(f, {.Drop}, 16)
	hold(f, {}, 1) // the tick the button is let go
	b, found := thrown_knife(f)
	testing.expect(t, found, "no thrown knife after an early release")
	if found {
		speed := vec2_length(b.vel)
		want := f.ctx.weapons[.Thrown_Knife].speed * 1.5 * 9.0 / 16.0
		testing.expectf(t, speed >= want - 0.5 && speed < 6, "early throw velocity %.2f, wanted %.2f", speed, want)
	}
}

// A tap throws right away at half the momentum: D is clamped to 8 as its minimum, so
// the knife never leaves weaker than half strength.
@(test)
test_a_tap_throws_at_half_momentum :: proc(t: ^testing.T) {
	f, ok := fixture()
	if !ok do return
	defer fixture_destroy(f)
	hold(f, {.Drop}, 1)
	hold(f, {}, 1) // the tick the button is let go
	b, found := thrown_knife(f)
	testing.expect(t, found, "no thrown knife after a tap")
	if found {
		speed := vec2_length(b.vel)
		want := f.ctx.weapons[.Thrown_Knife].speed * 1.5 * 0.5
		testing.expectf(t, speed >= want - 0.5 && speed < 5, "tap throw velocity %.2f, wanted %.2f", speed, want)
	}
}

// A knife that stopped lands as a knife to pick up again, with the thrower as its
// owner and the usual resist time.
@(test)
test_a_landed_knife_is_a_knife_to_pick_up :: proc(t: ^testing.T) {
	f, ok := fixture()
	if !ok do return
	defer fixture_destroy(f)
	dropped_gun_land_knife(&f.ctx, f.world, 0, {100, 100}, {1, 0})
	found := false
	for &th in f.world.things {
		if th.style == .Weapon && th.weapon == .Knife && vec2_length(th.pos[0] - {100, 100}) < 1 {
			testing.expect(t, th.timeout == GUN_RESIST_TIME, "the knife's resist time")
			testing.expect(t, th.owner == 1, "the thrower is the owner")
			testing.expect(t, th.ammo == 1, "a knife's ammo")
			found = true
		}
	}
	testing.expect(t, found, "no landed knife at the position")
}
