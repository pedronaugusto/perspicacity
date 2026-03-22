//! Perspicacity v1 -- Round-trip serialization tests.
//!
//! Run with: zig build test

const std = @import("std");
const testing = std.testing;
const p = @import("perception.zig");
const serialize = @import("serialize.zig");
const parse = @import("parse.zig");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create an arena allocator backed by the test allocator.
fn arena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(std.heap.page_allocator);
}

/// Compare two .picacia texts line by line, ignoring comments and blank lines.
fn compareLines(allocator: std.mem.Allocator, original: []const u8, roundtripped: []const u8) !void {
    var orig_lines: std.ArrayList([]const u8) = .empty;
    defer orig_lines.deinit(allocator);
    var rt_lines: std.ArrayList([]const u8) = .empty;
    defer rt_lines.deinit(allocator);

    var it1 = std.mem.splitScalar(u8, original, '\n');
    while (it1.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        try orig_lines.append(allocator, trimmed);
    }

    var it2 = std.mem.splitScalar(u8, roundtripped, '\n');
    while (it2.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        try rt_lines.append(allocator, trimmed);
    }

    const min_len = @min(orig_lines.items.len, rt_lines.items.len);
    for (0..min_len) |i| {
        try testing.expectEqualStrings(orig_lines.items[i], rt_lines.items[i]);
    }
    try testing.expectEqual(orig_lines.items.len, rt_lines.items.len);
}

// ---------------------------------------------------------------------------
// Minimal fixture tests
// ---------------------------------------------------------------------------

const minimal_fixture =
    \\# Perspicacity v1 — minimal fixture
    \\CAM Camera [0,0,5] 50mm
    \\LIGHT Key POINT 500W [1,1,1] [3,2,4]
    \\OBJ Cube [0,0,0] 15% mid-center d=5m Default(rgb=0.80,0.80,0.80,rough=0.5) dim=[2,2,2] rot=[0,0,45] facing=NE face=+Z has_uv
    \\OBJ Sphere [-2,0,0] 8% mid-left d=5.4m Metal(rgb=0.90,0.85,0.80,metal=1.0,rough=0.2) dim=[1,1,1] face=+Z has_uv
    \\OBJ Floor [0,0,-1] 35% bot-center d=5.8m Concrete(textured) dim=[10,10,0.2] no_uv
    \\REL Cube->Sphere 2m left same_level
    \\REL Cube->Floor 1m below contact
    \\REL Sphere->Floor 1m below contact
    \\SPATIAL Cube scale_ratio ratio=1.0 axes=[2,2,2]
    \\LIT Key->Cube @42° i=0.85
    \\LIT Key->Sphere @38° i=0.72
    \\LIT Key->Floor @65° i=0.45
    \\SHAD Key->Floor 12% casters:Cube,Sphere contact
    \\MAT Default: light grey matte
    \\MAT Metal: polished metal -- needs env reflections
    \\MAT Concrete: textured concrete
    \\WORLD bg=[0.05,0.05,0.05] strength=1
    \\COMP thirds=0.71 3/3_visible balance=0.62 depth=1/3
    \\RAY 12x12 Cube=15% Sphere=8% Floor=35% empty=42%
;

test "minimal: parse" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();

    const perc = try parse.fromText(minimal_fixture, alloc);

    try testing.expectEqual(@as(usize, 1), perc.identity.cameras.len);
    try testing.expectEqualStrings("Camera", perc.identity.cameras[0].name);
    try testing.expectEqual(@as(f32, 50.0), perc.identity.cameras[0].focal_mm);

    try testing.expectEqual(@as(usize, 1), perc.identity.lights.len);
    try testing.expectEqualStrings("Key", perc.identity.lights[0].name);
    try testing.expectEqualStrings("POINT", perc.identity.lights[0].light_type);
    try testing.expectEqual(@as(f32, 500.0), perc.identity.lights[0].energy_w);

    try testing.expectEqual(@as(usize, 3), perc.identity.objects.len);
    try testing.expectEqualStrings("Cube", perc.identity.objects[0].name);
    try testing.expectEqualStrings("Sphere", perc.identity.objects[1].name);
    try testing.expectEqualStrings("Floor", perc.identity.objects[2].name);
    try testing.expectEqual(@as(f32, 15.0), perc.identity.objects[0].coverage);
    try testing.expectEqual(@as(f32, 5.0), perc.identity.objects[0].depth);
    try testing.expectEqualStrings("+Z", perc.identity.objects[0].face.?);
    try testing.expect(perc.identity.objects[2].face == null);

    // New v1 fields on objects
    try testing.expect(perc.identity.objects[0].dimensions != null);
    try testing.expectEqual(@as(f32, 2.0), perc.identity.objects[0].dimensions.?.x);
    try testing.expect(perc.identity.objects[0].rotation != null);
    try testing.expectEqual(@as(f32, 45.0), perc.identity.objects[0].rotation.?.z);
    try testing.expectEqualStrings("NE", perc.identity.objects[0].facing.?);
    try testing.expect(perc.identity.objects[0].has_uv != null);
    try testing.expect(perc.identity.objects[0].has_uv.?);
    try testing.expect(perc.identity.objects[2].has_uv != null);
    try testing.expect(!perc.identity.objects[2].has_uv.?);

    try testing.expectEqual(@as(usize, 3), perc.spatial.relationships.len);
    try testing.expectEqualStrings("Cube", perc.spatial.relationships[0].from_obj);
    try testing.expectEqualStrings("Sphere", perc.spatial.relationships[0].to_obj);
    try testing.expectEqual(@as(f32, 2.0), perc.spatial.relationships[0].distance);
    try testing.expectEqualStrings("left", perc.spatial.relationships[0].direction);
    try testing.expectEqualStrings("same_level", perc.spatial.relationships[0].vertical.?);
    try testing.expect(perc.spatial.relationships[1].contact);

    // SPATIAL facts
    try testing.expectEqual(@as(usize, 1), perc.spatial.spatial_facts.len);
    try testing.expectEqualStrings("Cube", perc.spatial.spatial_facts[0].object);
    try testing.expectEqualStrings("scale_ratio", perc.spatial.spatial_facts[0].fact_type);

    try testing.expectEqual(@as(usize, 3), perc.physical.light_analyses.len);
    try testing.expectEqual(@as(f32, 42.0), perc.physical.light_analyses[0].angle);
    try testing.expectEqual(@as(f32, 0.85), perc.physical.light_analyses[0].intensity);

    try testing.expectEqual(@as(usize, 1), perc.physical.shadow_analyses.len);
    try testing.expectEqual(@as(f32, 12.0), perc.physical.shadow_analyses[0].coverage);
    try testing.expectEqualStrings("Cube", perc.physical.shadow_analyses[0].casters[0]);
    try testing.expectEqualStrings("Sphere", perc.physical.shadow_analyses[0].casters[1]);
    try testing.expect(perc.physical.shadow_analyses[0].contact);

    try testing.expectEqual(@as(usize, 3), perc.physical.materials.len);
    try testing.expectEqualStrings("env reflections", perc.physical.materials[1].needs.?);

    try testing.expect(perc.physical.world != null);
    try testing.expect(perc.physical.world.?.bg_color != null);
    try testing.expectEqual(@as(f32, 1.0), perc.physical.world.?.strength);

    try testing.expect(perc.visual.composition != null);
    try testing.expectEqual(@as(f32, 0.71), perc.visual.composition.?.thirds);
    try testing.expectEqual(@as(i32, 3), perc.visual.composition.?.visible);
    try testing.expectEqual(@as(i32, 3), perc.visual.composition.?.total);

    try testing.expect(perc.visual.ray_grid != null);
    try testing.expectEqual(@as(i32, 12), perc.visual.ray_grid.?.resolution);
    try testing.expectEqual(@as(f32, 15.0), perc.visual.ray_grid.?.getCoverage("Cube").?);
    try testing.expectEqual(@as(f32, 42.0), perc.visual.ray_grid.?.empty);
}

test "minimal: round-trip" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();

    const perc = try parse.fromText(minimal_fixture, alloc);
    const rt = try serialize.toText(perc, alloc);
    try compareLines(alloc, minimal_fixture, rt);
}

// ---------------------------------------------------------------------------
// Full fixture tests
// ---------------------------------------------------------------------------

const full_fixture =
    \\# Perspicacity v1 — full fixture (game-like warehouse scene)
    \\SCENE 11 objects 2 lights 1100W BLENDER_EEVEE ground_z=0
    \\CAM PlayerCam [0,2,8] 35mm
    \\LIGHT Overhead AREA 800W [1,0.98,0.95] [0,5,0]
    \\LIGHT Spot1 SPOT 300W [1,0.9,0.8] [4,3,2]
    \\OBJ Crate_A [1,0,2] 12% mid-right d=6.3m Wood(rgb=0.55,0.40,0.25,rough=0.8) dim=[1,1,1] rot=[0,0,15] facing=NE zone=storage face=+Z lum=0.7 has_uv
    \\OBJ Crate_B [1,1,2] 8% top-right d=6.5m Wood(rgb=0.55,0.40,0.25,rough=0.8) dim=[1,1,1] zone=storage face=+Z lum=0.65 has_uv
    \\OBJ Barrel [-2,0,3] 10% mid-left d=5.8m Metal(rgb=0.30,0.30,0.32,metal=0.8,rough=0.6) dim=[0.6,0.6,0.9] rot=[5,0,0] facing=N zone=storage face=+Z lum=0.5 has_uv
    \\OBJ Forklift [3,0,0] 18% mid-right d=8.2m Paint(rgb=0.90,0.70,0.10,rough=0.4) dim=[2.5,1.2,2] rot=[0,0,90] facing=E zone=dock face=-X lum=0.6 has_uv
    \\OBJ Guard [-1,0,6] 6% mid-center d=2.5m Cloth(rgb=0.20,0.20,0.25,rough=0.9) dim=[0.5,0.3,1.8] zone=patrol face=+Z lum=0.4 has_uv
    \\OBJ Rifle [-0.8,1.2,6] 2% mid-center d=2.6m Metal(rgb=0.15,0.15,0.15,metal=1.0,rough=0.3) dim=[0.05,0.05,0.9] face=+Z lum=0.3 has_uv
    \\OBJ GlassCase [2,0,5] 5% mid-right d=4m Glass(ior=1.45) dim=[0.6,0.6,1.2] zone=storage transparent has_uv contains:[Artifact]
    \\OBJ Artifact [2,0.1,5] 1% mid-right d=4.1m Gold(rgb=0.90,0.80,0.20,metal=1.0,rough=0.1) dim=[0.1,0.1,0.2] zone=storage lum=0.8 has_uv inside=GlassCase
    \\OBJ Floor [0,0,0] 30% bot-center d=8.5m Concrete(textured) dim=[20,20,0.3] no_uv
    \\OBJ Ceiling [0,6,0] 20% top-center d=10m Concrete(textured) dim=[20,20,0.3] no_uv
    \\OBJ Wall_N [0,3,-5] 15% mid-center d=13m Brick(textured) dim=[20,0.3,6] no_uv
    \\SGROUP "Crates" [1,0.5,2] dim=[1,1,2] top=3 Wood facing=NE members=2
    \\ASSEMBLY "Display" members=[GlassCase,Artifact] center=[2,0.05,5] types=MESH
    \\REL Crate_A->Crate_B 1m below aabb_overlap=8% contact
    \\REL Crate_A->Floor 0m below contact
    \\REL Crate_A->Barrel 3.2m left same_level
    \\REL Barrel->Floor 0m below contact
    \\REL Guard->Floor 0m below contact
    \\REL Guard->Crate_A 4.5m right same_level
    \\REL Rifle->Guard 0.3m right same_level
    \\REL Forklift->Floor 0m below contact
    \\REL Forklift->Wall_N 5.5m behind same_level
    \\REL GlassCase->Floor 0m below contact
    \\REL Artifact->GlassCase 0m below overlap=80% aabb_overlap=95%
    \\VERIFY FAIL Wall_N subdivide requested 4 cuts but mesh still has 4 faces
    \\CONTAIN GlassCase contains Artifact full
    \\SPATIAL Barrel bbox_below_surface surface=Floor surface_z=0.0 penetration=0.02 pct=2
    \\SPATIAL Wall_N scale_ratio ratio=66.7 axes=[20,0.3,6]
    \\LIT Overhead->Crate_A @15° i=0.9
    \\LIT Overhead->Barrel @22° i=0.82
    \\LIT Overhead->Guard @10° i=0.95
    \\LIT Overhead->Floor @0° i=1
    \\LIT Spot1->Forklift @35° i=0.6
    \\LIT Spot1->Crate_A @50° i=0.4
    \\SHAD Overhead->Floor 8% casters:Crate_A,Crate_B,Barrel contact
    \\SHAD Overhead->Floor 3% casters:Guard contact
    \\SHAD Spot1->Floor 5% casters:Forklift gap=0.1m
    \\MAT Wood: warm brown rough wood
    \\MAT Metal: dark metallic -- needs env reflections
    \\MAT Paint: yellow industrial paint
    \\MAT Cloth: dark tactical fabric
    \\MAT Concrete: textured concrete
    \\MAT Brick: red brick wall -- needs normal map
    \\MAT Glass: clear glass container
    \\MAT Gold: polished gold ornament
    \\HARMONY types=wood+metal+paint+cloth+concrete+brick+glass+gold temp=warm
    \\PALETTE lum=0.45 warm_brown dark_grey steel_blue
    \\WORLD bg=[0.02,0.02,0.03] strength=0.5
    \\PHYS Crate_A dynamic mass=25kg sleeping
    \\PHYS Crate_B dynamic mass=25kg sleeping
    \\PHYS Barrel dynamic mass=40kg sleeping
    \\PHYS Forklift kinematic mass=2000kg vel=[0,0,0]
    \\PHYS Guard kinematic mass=80kg vel=[0,0,0.5]
    \\PHYS Floor static mass=0kg sleeping
    \\CONTACT Crate_A<>Floor normal=[0,0,1] force=245.3N surface=concrete
    \\CONTACT Crate_B<>Crate_A normal=[0,0,1] force=245.3N surface=wood
    \\CONTACT Barrel<>Floor normal=[0,0,1] force=392.4N surface=concrete
    \\CONTACT Guard<>Floor normal=[0,0,1] force=784.8N surface=concrete
    \\SND Forklift type=point vol=0.4 dist=8.2m dir=right occ=0
    \\SND Radio type=point vol=0.2 dist=5m dir=left occ=0.6
    \\SND Ambience type=ambient vol=0.15 dist=0m dir=above occ=0
    \\COMP thirds=0.65 11/11_visible balance=0.55 depth=3/3 edge:[Floor,Ceiling]
    \\RAY 12x12 Crate_A=10% Crate_B=7% Barrel=9% Forklift=16% Guard=5% Rifle=2% GlassCase=4% Artifact=1% Floor=28% Ceiling=5% Wall_N=4% empty=9%
    \\MVIEW front: Crate_A=12% Barrel=10% Guard=8% Floor=35%
    \\MVIEW top: Floor=60% Crate_A=5% Barrel=4% Forklift=12% Guard=3%
    \\HIER Crate_B > Crate_A
    \\HIER Rifle > Guard
    \\HIER Artifact > GlassCase
    \\GRP Storage: Crate_A, Crate_B, Barrel, GlassCase, Artifact
    \\GRP Characters: Guard
    \\GRP Vehicles: Forklift
    \\GRP Structure: Floor, Ceiling, Wall_N
    \\ANIM Guard action=Patrol frame=45/120 playing
    \\ANIM Forklift action=Idle frame=1/1 stopped
;

test "full: parse" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();

    const perc = try parse.fromText(full_fixture, alloc);

    // SCENE header
    try testing.expect(perc.identity.scene_header != null);
    try testing.expectEqual(@as(i32, 11), perc.identity.scene_header.?.obj_count);
    try testing.expectEqual(@as(i32, 2), perc.identity.scene_header.?.light_count);
    try testing.expectEqual(@as(f32, 1100.0), perc.identity.scene_header.?.energy);
    try testing.expectEqual(@as(f32, 0.0), perc.identity.scene_header.?.ground_z.?);

    try testing.expectEqual(@as(usize, 1), perc.identity.cameras.len);
    try testing.expectEqualStrings("PlayerCam", perc.identity.cameras[0].name);
    try testing.expectEqual(@as(usize, 2), perc.identity.lights.len);
    try testing.expectEqual(@as(usize, 11), perc.identity.objects.len);

    // Check new OBJ fields
    const crate_a = perc.identity.objects[0];
    try testing.expectEqualStrings("Crate_A", crate_a.name);
    try testing.expect(crate_a.dimensions != null);
    try testing.expectEqual(@as(f32, 1.0), crate_a.dimensions.?.x);
    try testing.expect(crate_a.rotation != null);
    try testing.expectEqual(@as(f32, 15.0), crate_a.rotation.?.z);
    try testing.expectEqualStrings("NE", crate_a.facing.?);
    try testing.expectEqualStrings("storage", crate_a.zone.?);
    try testing.expectEqual(@as(f32, 0.7), crate_a.lum.?);
    try testing.expect(crate_a.has_uv != null);
    try testing.expect(crate_a.has_uv.?);

    // GlassCase: transparent, contains
    const glass = perc.identity.objects[6];
    try testing.expectEqualStrings("GlassCase", glass.name);
    try testing.expect(glass.transparent);
    try testing.expectEqual(@as(usize, 1), glass.contains.len);
    try testing.expectEqualStrings("Artifact", glass.contains[0]);

    // Artifact: inside
    const artifact = perc.identity.objects[7];
    try testing.expectEqualStrings("Artifact", artifact.name);
    try testing.expectEqualStrings("GlassCase", artifact.inside.?);

    // Floor: no_uv
    const floor = perc.identity.objects[8];
    try testing.expectEqualStrings("Floor", floor.name);
    try testing.expect(floor.has_uv != null);
    try testing.expect(!floor.has_uv.?);

    // SGROUP
    try testing.expectEqual(@as(usize, 1), perc.identity.semantic_groups.len);
    try testing.expectEqualStrings("Crates", perc.identity.semantic_groups[0].name);
    try testing.expectEqualStrings("NE", perc.identity.semantic_groups[0].facing.?);
    try testing.expectEqual(@as(i32, 2), perc.identity.semantic_groups[0].member_count);

    // ASSEMBLY
    try testing.expectEqual(@as(usize, 1), perc.identity.assemblies.len);
    try testing.expectEqualStrings("Display", perc.identity.assemblies[0].name);
    try testing.expectEqual(@as(usize, 2), perc.identity.assemblies[0].members.len);
    try testing.expectEqualStrings("GlassCase", perc.identity.assemblies[0].members[0]);
    try testing.expectEqualStrings("Artifact", perc.identity.assemblies[0].members[1]);
    try testing.expectEqualStrings("MESH", perc.identity.assemblies[0].types);

    // Relationships
    try testing.expectEqual(@as(usize, 11), perc.spatial.relationships.len);

    // Check aabb_overlap on first REL
    try testing.expectEqual(@as(f32, 8.0), perc.spatial.relationships[0].aabb_overlap_pct.?);
    // Check overlap=80% on Artifact->GlassCase
    try testing.expect(perc.spatial.relationships[10].overlap);
    try testing.expectEqual(@as(f32, 80.0), perc.spatial.relationships[10].overlap_pct.?);
    try testing.expectEqual(@as(f32, 95.0), perc.spatial.relationships[10].aabb_overlap_pct.?);

    // VERIFY
    try testing.expectEqual(@as(usize, 1), perc.spatial.verify.len);
    try testing.expectEqualStrings("Wall_N", perc.spatial.verify[0].object);

    // CONTAIN
    try testing.expectEqual(@as(usize, 1), perc.spatial.containment.len);
    try testing.expectEqualStrings("GlassCase", perc.spatial.containment[0].outer);
    try testing.expectEqualStrings("Artifact", perc.spatial.containment[0].inner);
    try testing.expectEqualStrings("full", perc.spatial.containment[0].mode);

    // SPATIAL
    try testing.expectEqual(@as(usize, 2), perc.spatial.spatial_facts.len);
    try testing.expectEqualStrings("Barrel", perc.spatial.spatial_facts[0].object);
    try testing.expectEqualStrings("bbox_below_surface", perc.spatial.spatial_facts[0].fact_type);

    try testing.expectEqual(@as(usize, 6), perc.physical.light_analyses.len);
    try testing.expectEqual(@as(usize, 3), perc.physical.shadow_analyses.len);
    try testing.expectEqual(@as(usize, 8), perc.physical.materials.len);
    try testing.expect(perc.physical.world != null);

    // HARMONY
    try testing.expect(perc.physical.harmony != null);
    try testing.expectEqualStrings("warm", perc.physical.harmony.?.temperature);

    // PALETTE
    try testing.expect(perc.physical.palette != null);
    try testing.expectEqual(@as(f32, 0.45), perc.physical.palette.?.luminance.?);
    try testing.expectEqual(@as(usize, 3), perc.physical.palette.?.palette.len);
    try testing.expectEqualStrings("warm_brown", perc.physical.palette.?.palette[0]);

    try testing.expectEqual(@as(usize, 6), perc.physical.physics_states.len);
    try testing.expectEqualStrings("Crate_A", perc.physical.physics_states[0].name);
    try testing.expectEqualStrings("dynamic", perc.physical.physics_states[0].phys_type);
    try testing.expectEqual(@as(f32, 25.0), perc.physical.physics_states[0].mass_kg);
    try testing.expect(perc.physical.physics_states[0].sleeping);

    try testing.expectEqual(@as(usize, 4), perc.physical.contacts.len);
    try testing.expectEqualStrings("Crate_A", perc.physical.contacts[0].obj_a);
    try testing.expectEqualStrings("Floor", perc.physical.contacts[0].obj_b);
    try testing.expectEqual(@as(f32, 245.3), perc.physical.contacts[0].force_n);

    try testing.expectEqual(@as(usize, 3), perc.physical.sounds.len);
    try testing.expectEqualStrings("Forklift", perc.physical.sounds[0].source);
    try testing.expectEqualStrings("point", perc.physical.sounds[0].sound_type);
    try testing.expectEqual(@as(f32, 8.2), perc.physical.sounds[0].distance);

    try testing.expect(perc.visual.composition != null);
    try testing.expectEqualStrings("Floor", perc.visual.composition.?.edge[0]);
    try testing.expectEqualStrings("Ceiling", perc.visual.composition.?.edge[1]);
    try testing.expect(perc.visual.ray_grid != null);
    try testing.expectEqual(@as(usize, 2), perc.visual.multi_views.len);

    try testing.expectEqual(@as(usize, 3), perc.semantic.hierarchy.len);
    try testing.expectEqualStrings("Crate_B", perc.semantic.hierarchy[0].chain[0]);
    try testing.expectEqualStrings("Crate_A", perc.semantic.hierarchy[0].chain[1]);
    try testing.expectEqualStrings("Rifle", perc.semantic.hierarchy[1].chain[0]);
    try testing.expectEqualStrings("Guard", perc.semantic.hierarchy[1].chain[1]);
    try testing.expectEqualStrings("Artifact", perc.semantic.hierarchy[2].chain[0]);
    try testing.expectEqualStrings("GlassCase", perc.semantic.hierarchy[2].chain[1]);

    try testing.expectEqual(@as(usize, 4), perc.semantic.groups.len);
    try testing.expectEqualStrings("Storage", perc.semantic.groups[0].name);
    try testing.expectEqualStrings("Crate_A", perc.semantic.groups[0].members[0]);
    try testing.expectEqualStrings("Crate_B", perc.semantic.groups[0].members[1]);
    try testing.expectEqualStrings("Barrel", perc.semantic.groups[0].members[2]);

    try testing.expectEqual(@as(usize, 2), perc.temporal.animations.len);
    try testing.expectEqualStrings("Guard", perc.temporal.animations[0].name);
    try testing.expectEqualStrings("Patrol", perc.temporal.animations[0].action);
    try testing.expectEqual(@as(i32, 45), perc.temporal.animations[0].frame);
    try testing.expectEqual(@as(i32, 120), perc.temporal.animations[0].total);
    try testing.expect(perc.temporal.animations[0].playing);
}

test "full: round-trip" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();

    const perc = try parse.fromText(full_fixture, alloc);
    const rt = try serialize.toText(perc, alloc);
    try compareLines(alloc, full_fixture, rt);
}

// ---------------------------------------------------------------------------
// Individual line type parsing tests
// ---------------------------------------------------------------------------

test "line: CAM" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("CAM MyCam [1,2,3] 35mm", alloc);
    try testing.expectEqualStrings("MyCam", perc.identity.cameras[0].name);
    try testing.expectEqual(@as(f32, 1.0), perc.identity.cameras[0].position.x);
    try testing.expectEqual(@as(f32, 35.0), perc.identity.cameras[0].focal_mm);
}

test "line: LIGHT" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("LIGHT Sun SUN 2.5W [1.0,0.95,0.9] [0,0,10]", alloc);
    try testing.expectEqualStrings("Sun", perc.identity.lights[0].name);
    try testing.expectEqualStrings("SUN", perc.identity.lights[0].light_type);
    try testing.expectEqual(@as(f32, 2.5), perc.identity.lights[0].energy_w);
}

test "line: OBJ minimal" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("OBJ Box [0,0,0] 10% mid-center d=3.0m Default(textured)", alloc);
    const obj = perc.identity.objects[0];
    try testing.expectEqualStrings("Box", obj.name);
    try testing.expectEqual(@as(f32, 10.0), obj.coverage);
    try testing.expectEqual(@as(f32, 3.0), obj.depth);
    try testing.expect(obj.face == null);
    try testing.expect(obj.lum == null);
    try testing.expect(obj.dimensions == null);
}

test "line: OBJ full" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText(
        "OBJ Box [0,0,0] 10% mid-center d=3.0m Default(rgb=0.5,0.5,0.5) dim=[1,2,3] rot=[0,0,45] facing=NE zone=storage face=+X lum=0.7 has_uv inside=Room contains:[Item1,Item2]",
        alloc,
    );
    const obj = perc.identity.objects[0];
    try testing.expectEqualStrings("+X", obj.face.?);
    try testing.expectEqual(@as(f32, 0.7), obj.lum.?);
    try testing.expect(obj.dimensions != null);
    try testing.expectEqual(@as(f32, 1.0), obj.dimensions.?.x);
    try testing.expectEqual(@as(f32, 3.0), obj.dimensions.?.z);
    try testing.expect(obj.rotation != null);
    try testing.expectEqual(@as(f32, 45.0), obj.rotation.?.z);
    try testing.expectEqualStrings("NE", obj.facing.?);
    try testing.expectEqualStrings("storage", obj.zone.?);
    try testing.expect(obj.has_uv != null);
    try testing.expect(obj.has_uv.?);
    try testing.expectEqualStrings("Room", obj.inside.?);
    try testing.expectEqual(@as(usize, 2), obj.contains.len);
    try testing.expectEqualStrings("Item1", obj.contains[0]);
    try testing.expectEqualStrings("Item2", obj.contains[1]);
}

test "line: OBJ transparent no_uv" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText(
        "OBJ Glass [0,0,0] 5% mid-center d=4m Glass(ior=1.45) transparent no_uv",
        alloc,
    );
    const obj = perc.identity.objects[0];
    try testing.expect(obj.transparent);
    try testing.expect(obj.has_uv != null);
    try testing.expect(!obj.has_uv.?);
}

test "line: SCENE" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("SCENE 11 objects 2 lights 1100W BLENDER_EEVEE ground_z=0", alloc);
    try testing.expect(perc.identity.scene_header != null);
    try testing.expectEqual(@as(i32, 11), perc.identity.scene_header.?.obj_count);
    try testing.expectEqual(@as(i32, 2), perc.identity.scene_header.?.light_count);
    try testing.expectEqual(@as(f32, 1100.0), perc.identity.scene_header.?.energy);
    try testing.expectEqual(@as(f32, 0.0), perc.identity.scene_header.?.ground_z.?);
}

test "line: SGROUP" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText(
        "SGROUP \"Crates\" [1,0.5,2] dim=[1,1,2] top=3 Wood facing=NE members=2",
        alloc,
    );
    try testing.expectEqual(@as(usize, 1), perc.identity.semantic_groups.len);
    try testing.expectEqualStrings("Crates", perc.identity.semantic_groups[0].name);
    try testing.expectEqualStrings("NE", perc.identity.semantic_groups[0].facing.?);
    try testing.expectEqual(@as(i32, 2), perc.identity.semantic_groups[0].member_count);
    try testing.expectEqualStrings("Wood", perc.identity.semantic_groups[0].material);
}

test "line: ASSEMBLY" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText(
        "ASSEMBLY \"Display\" members=[GlassCase,Artifact] center=[2,0.05,5] types=MESH",
        alloc,
    );
    try testing.expectEqual(@as(usize, 1), perc.identity.assemblies.len);
    try testing.expectEqualStrings("Display", perc.identity.assemblies[0].name);
    try testing.expectEqual(@as(usize, 2), perc.identity.assemblies[0].members.len);
    try testing.expectEqualStrings("GlassCase", perc.identity.assemblies[0].members[0]);
    try testing.expectEqualStrings("MESH", perc.identity.assemblies[0].types);
}

test "line: REL basic" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("REL A->B 2.0m left same_level", alloc);
    const rel = perc.spatial.relationships[0];
    try testing.expectEqualStrings("A", rel.from_obj);
    try testing.expectEqualStrings("B", rel.to_obj);
    try testing.expectEqual(@as(f32, 2.0), rel.distance);
    try testing.expectEqualStrings("left", rel.direction);
    try testing.expectEqualStrings("same_level", rel.vertical.?);
    try testing.expect(!rel.contact);
}

test "line: REL contact" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("REL A->B 0.0m below contact", alloc);
    const rel = perc.spatial.relationships[0];
    try testing.expectEqualStrings("below", rel.direction);
    try testing.expect(rel.contact);
}

test "line: REL overlap with pct" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("REL A->B 0m below overlap=80% aabb_overlap=95% contact", alloc);
    const rel = perc.spatial.relationships[0];
    try testing.expect(rel.overlap);
    try testing.expectEqual(@as(f32, 80.0), rel.overlap_pct.?);
    try testing.expectEqual(@as(f32, 95.0), rel.aabb_overlap_pct.?);
    try testing.expect(rel.contact);
}

test "line: REL aabb_overlap" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("REL A->B 1m below aabb_overlap=8% contact", alloc);
    const rel = perc.spatial.relationships[0];
    try testing.expectEqual(@as(f32, 8.0), rel.aabb_overlap_pct.?);
    try testing.expect(rel.contact);
}

test "line: REL unicode arrow" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("REL A\xe2\x86\x92B 2.0m left same_level", alloc);
    const rel = perc.spatial.relationships[0];
    try testing.expectEqualStrings("A", rel.from_obj);
    try testing.expectEqualStrings("B", rel.to_obj);
}

test "line: VERIFY FAIL" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("VERIFY FAIL Wall_N subdivide requested 4 cuts but mesh still has 4 faces", alloc);
    try testing.expectEqual(@as(usize, 1), perc.spatial.verify.len);
    try testing.expectEqualStrings("Wall_N", perc.spatial.verify[0].object);
    try testing.expectEqualStrings("subdivide requested 4 cuts but mesh still has 4 faces", perc.spatial.verify[0].message);
}

test "line: CONTAIN" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("CONTAIN GlassCase contains Artifact full", alloc);
    try testing.expectEqual(@as(usize, 1), perc.spatial.containment.len);
    try testing.expectEqualStrings("GlassCase", perc.spatial.containment[0].outer);
    try testing.expectEqualStrings("Artifact", perc.spatial.containment[0].inner);
    try testing.expectEqualStrings("full", perc.spatial.containment[0].mode);
}

test "line: SPATIAL" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("SPATIAL Barrel bbox_below_surface surface=Floor surface_z=0.0 penetration=0.02 pct=2", alloc);
    try testing.expectEqual(@as(usize, 1), perc.spatial.spatial_facts.len);
    try testing.expectEqualStrings("Barrel", perc.spatial.spatial_facts[0].object);
    try testing.expectEqualStrings("bbox_below_surface", perc.spatial.spatial_facts[0].fact_type);
    try testing.expectEqual(@as(usize, 4), perc.spatial.spatial_facts[0].detail_keys.len);
    try testing.expectEqualStrings("surface", perc.spatial.spatial_facts[0].detail_keys[0]);
    try testing.expectEqualStrings("Floor", perc.spatial.spatial_facts[0].detail_vals[0]);
}

test "line: HARMONY" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("HARMONY types=wood+metal temp=warm", alloc);
    try testing.expect(perc.physical.harmony != null);
    try testing.expectEqualStrings("wood+metal", perc.physical.harmony.?.types);
    try testing.expectEqualStrings("warm", perc.physical.harmony.?.temperature);
}

test "line: PALETTE" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("PALETTE lum=0.45 warm_brown dark_grey steel_blue", alloc);
    try testing.expect(perc.physical.palette != null);
    try testing.expectEqual(@as(f32, 0.45), perc.physical.palette.?.luminance.?);
    try testing.expectEqual(@as(usize, 3), perc.physical.palette.?.palette.len);
    try testing.expectEqualStrings("warm_brown", perc.physical.palette.?.palette[0]);
    try testing.expectEqualStrings("dark_grey", perc.physical.palette.?.palette[1]);
    try testing.expectEqualStrings("steel_blue", perc.physical.palette.?.palette[2]);
}

test "line: PALETTE no lum" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("PALETTE red blue green", alloc);
    try testing.expect(perc.physical.palette != null);
    try testing.expect(perc.physical.palette.?.luminance == null);
    try testing.expectEqual(@as(usize, 3), perc.physical.palette.?.palette.len);
}

test "line: LIT" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("LIT Key->Cube @42\xc2\xb0 i=0.85", alloc);
    const la = perc.physical.light_analyses[0];
    try testing.expectEqualStrings("Key", la.light);
    try testing.expectEqualStrings("Cube", la.surface);
    try testing.expectEqual(@as(f32, 42.0), la.angle);
    try testing.expectEqual(@as(f32, 0.85), la.intensity);
}

test "line: LIT with shadow" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("LIT Key->Floor @65\xc2\xb0 i=0.45 shadow:Cube,Sphere", alloc);
    const la = perc.physical.light_analyses[0];
    try testing.expectEqualStrings("Cube", la.shadow[0]);
    try testing.expectEqualStrings("Sphere", la.shadow[1]);
}

test "line: SHAD" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("SHAD Key->Floor 12% casters:Cube,Sphere contact", alloc);
    const sa = perc.physical.shadow_analyses[0];
    try testing.expectEqual(@as(f32, 12.0), sa.coverage);
    try testing.expectEqualStrings("Cube", sa.casters[0]);
    try testing.expectEqualStrings("Sphere", sa.casters[1]);
    try testing.expect(sa.contact);
    try testing.expect(sa.gap == null);
}

test "line: SHAD gap" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("SHAD Sun->Wall 5% casters:Tree gap=0.3m", alloc);
    const sa = perc.physical.shadow_analyses[0];
    try testing.expectEqual(@as(f32, 0.3), sa.gap.?);
    try testing.expect(!sa.contact);
}

test "line: MAT simple" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("MAT Default: light grey matte", alloc);
    const mat = perc.physical.materials[0];
    try testing.expectEqualStrings("Default", mat.name);
    try testing.expectEqualStrings("light grey matte", mat.appearance);
    try testing.expect(mat.needs == null);
}

test "line: MAT needs" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("MAT Metal: polished metal -- needs env reflections", alloc);
    const mat = perc.physical.materials[0];
    try testing.expectEqualStrings("polished metal", mat.appearance);
    try testing.expectEqualStrings("env reflections", mat.needs.?);
}

test "line: WORLD bg" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("WORLD bg=[0.05,0.05,0.05] strength=1.0", alloc);
    const w = perc.physical.world.?;
    try testing.expect(w.bg_color != null);
    try testing.expectEqual(@as(f32, 0.05), w.bg_color.?.x);
    try testing.expectEqual(@as(f32, 1.0), w.strength);
    try testing.expect(!w.hdri);
}

test "line: WORLD hdri" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("WORLD hdri strength=2.0", alloc);
    const w = perc.physical.world.?;
    try testing.expect(w.hdri);
    try testing.expectEqual(@as(f32, 2.0), w.strength);
}

test "line: PHYS" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("PHYS Crate dynamic mass=25.0kg sleeping", alloc);
    const ps = perc.physical.physics_states[0];
    try testing.expectEqualStrings("Crate", ps.name);
    try testing.expectEqualStrings("dynamic", ps.phys_type);
    try testing.expectEqual(@as(f32, 25.0), ps.mass_kg);
    try testing.expect(ps.sleeping);
    try testing.expect(ps.velocity == null);
}

test "line: PHYS with vel" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("PHYS Ball dynamic mass=1.0kg vel=[0.0,0.0,-9.8]", alloc);
    const ps = perc.physical.physics_states[0];
    try testing.expect(ps.velocity != null);
    try testing.expectEqual(@as(f32, -9.8), ps.velocity.?.z);
}

test "line: CONTACT" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("CONTACT A<>B normal=[0,1,0] force=147.1N surface=concrete", alloc);
    const ct = perc.physical.contacts[0];
    try testing.expectEqualStrings("A", ct.obj_a);
    try testing.expectEqualStrings("B", ct.obj_b);
    try testing.expectEqual(@as(f32, 1.0), ct.normal.y);
    try testing.expectEqual(@as(f32, 147.1), ct.force_n);
    try testing.expectEqualStrings("concrete", ct.surface);
}

test "line: SND" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("SND Radio type=point vol=0.6 dist=3.2m dir=left occ=0.4", alloc);
    const snd = perc.physical.sounds[0];
    try testing.expectEqualStrings("Radio", snd.source);
    try testing.expectEqualStrings("point", snd.sound_type);
    try testing.expectEqual(@as(f32, 0.6), snd.volume);
    try testing.expectEqual(@as(f32, 3.2), snd.distance);
    try testing.expectEqualStrings("left", snd.direction);
    try testing.expectEqual(@as(f32, 0.4), snd.occlusion);
}

test "line: COMP" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("COMP thirds=0.71 3/3_visible balance=0.62 depth=1/3", alloc);
    const c = perc.visual.composition.?;
    try testing.expectEqual(@as(f32, 0.71), c.thirds);
    try testing.expectEqual(@as(i32, 3), c.visible);
    try testing.expectEqual(@as(i32, 3), c.total);
    try testing.expectEqual(@as(f32, 0.62), c.balance);
    try testing.expectEqualStrings("1/3", c.depth);
    try testing.expectEqual(@as(usize, 0), c.edge.len);
}

test "line: COMP with edge" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("COMP thirds=0.65 9/9_visible balance=0.55 depth=3/3 edge:[Floor,Ceiling]", alloc);
    const c = perc.visual.composition.?;
    try testing.expectEqualStrings("Floor", c.edge[0]);
    try testing.expectEqualStrings("Ceiling", c.edge[1]);
}

test "line: RAY" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("RAY 12x12 Cube=15% Floor=35% empty=42%", alloc);
    const rg = perc.visual.ray_grid.?;
    try testing.expectEqual(@as(i32, 12), rg.resolution);
    try testing.expectEqual(@as(f32, 15.0), rg.getCoverage("Cube").?);
    try testing.expectEqual(@as(f32, 35.0), rg.getCoverage("Floor").?);
    try testing.expectEqual(@as(f32, 42.0), rg.empty);
}

test "line: MVIEW" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("MVIEW front: Cube=20% Sphere=12%", alloc);
    const mv = perc.visual.multi_views[0];
    try testing.expectEqualStrings("front", mv.view);
    try testing.expectEqual(@as(f32, 20.0), mv.getCoverage("Cube").?);
}

test "line: HIER" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("HIER Wheel > Axle > Car", alloc);
    const h = perc.semantic.hierarchy[0];
    try testing.expectEqualStrings("Wheel", h.chain[0]);
    try testing.expectEqualStrings("Axle", h.chain[1]);
    try testing.expectEqualStrings("Car", h.chain[2]);
}

test "line: GRP" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("GRP Vehicles: Car, Truck, Bike", alloc);
    const g = perc.semantic.groups[0];
    try testing.expectEqualStrings("Vehicles", g.name);
    try testing.expectEqualStrings("Car", g.members[0]);
    try testing.expectEqualStrings("Truck", g.members[1]);
    try testing.expectEqualStrings("Bike", g.members[2]);
}

test "line: ANIM playing" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("ANIM Guard action=Patrol frame=45/120 playing", alloc);
    const anim = perc.temporal.animations[0];
    try testing.expectEqualStrings("Guard", anim.name);
    try testing.expectEqualStrings("Patrol", anim.action);
    try testing.expectEqual(@as(i32, 45), anim.frame);
    try testing.expectEqual(@as(i32, 120), anim.total);
    try testing.expect(anim.playing);
}

test "line: ANIM stopped" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("ANIM Door action=Open frame=24/24 stopped", alloc);
    try testing.expect(!perc.temporal.animations[0].playing);
}

test "line: DELTA" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("DELTA Crate moved [0.5,0,0] (+X)", alloc);
    try testing.expectEqual(@as(usize, 1), perc.temporal.deltas.len);
    try testing.expectEqualStrings("Crate moved [0.5,0,0] (+X)", perc.temporal.deltas[0]);
}

test "edge: empty scene" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("", alloc);
    try testing.expectEqual(@as(usize, 0), perc.identity.cameras.len);
    try testing.expectEqual(@as(usize, 0), perc.identity.objects.len);
}

test "edge: comments only" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("# just a comment\n# another comment\n", alloc);
    try testing.expectEqual(@as(usize, 0), perc.identity.cameras.len);
}

test "edge: viewpoint from camera" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("CAM MyCam [1,2,3] 50mm", alloc);
    try testing.expectEqualStrings("MyCam", perc.viewpoint);
    try testing.expectEqual(@as(f32, 1.0), perc.viewpoint_position.x);
    try testing.expectEqual(@as(f32, 2.0), perc.viewpoint_position.y);
    try testing.expectEqual(@as(f32, 3.0), perc.viewpoint_position.z);
}

test "edge: unknown prefix ignored" {
    var a = arena();
    defer a.deinit();
    const alloc = a.allocator();
    const perc = try parse.fromText("CAM Cam [0,0,5] 50mm\nFOO bar baz\nOBJ Cube [0,0,0] 10% mid-center d=5.0m Default(textured)", alloc);
    try testing.expectEqual(@as(usize, 1), perc.identity.cameras.len);
    try testing.expectEqual(@as(usize, 1), perc.identity.objects.len);
}
