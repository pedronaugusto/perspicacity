//! Perspicacity v1 -- Pure Zig structs for scene perception.
//!
//! Zero dependencies beyond std. All heap allocations go through
//! the caller-provided `std.mem.Allocator`.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------------------
// Vec3
// ---------------------------------------------------------------------------

pub const Vec3 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
};

// ---------------------------------------------------------------------------
// Tier 0 -- Identity
// ---------------------------------------------------------------------------

pub const SceneHeader = struct {
    obj_count: i32 = 0,
    light_count: i32 = 0,
    energy: f32 = 0.0,
    engine: []const u8 = "",
    ground_z: ?f32 = null,
};

pub const CameraData = struct {
    name: []const u8 = "",
    position: Vec3 = .{},
    focal_mm: f32 = 50.0,
};

pub const LightData = struct {
    name: []const u8 = "",
    light_type: []const u8 = "POINT", // POINT | SUN | SPOT | AREA
    energy_w: f32 = 0.0,
    color: Vec3 = .{},
    position: Vec3 = .{},
};

pub const ObjectData = struct {
    name: []const u8 = "",
    position: Vec3 = .{},
    coverage: f32 = 0.0,
    quadrant: []const u8 = "mid-center",
    depth: f32 = 0.0,
    material: []const u8 = "",
    dimensions: ?Vec3 = null,
    top_z: ?f32 = null,
    rotation: ?Vec3 = null,
    facing: ?[]const u8 = null,
    zone: ?[]const u8 = null,
    face: ?[]const u8 = null,
    lum: ?f32 = null,
    transparent: bool = false,
    has_uv: ?bool = null,
    inside: ?[]const u8 = null,
    contains: []const []const u8 = &.{},
};

pub const SemanticGroupData = struct {
    name: []const u8 = "",
    position: Vec3 = .{},
    dimensions: Vec3 = .{},
    top_z: f32 = 0.0,
    material: []const u8 = "",
    facing: ?[]const u8 = null,
    member_count: i32 = 0,
};

pub const AssemblyData = struct {
    name: []const u8 = "",
    members: []const []const u8 = &.{},
    center: Vec3 = .{},
    types: []const u8 = "",
};

// ---------------------------------------------------------------------------
// Tier 1 -- Spatial
// ---------------------------------------------------------------------------

pub const RelationshipData = struct {
    from_obj: []const u8 = "",
    to_obj: []const u8 = "",
    distance: f32 = 0.0,
    direction: []const u8 = "",
    vertical: ?[]const u8 = null,
    overlap: bool = false,
    overlap_pct: ?f32 = null,
    aabb_overlap_pct: ?f32 = null,
    contact: bool = false,
    occludes: bool = false,
    occ_pct: ?f32 = null,
};

pub const VerifyResult = struct {
    object: []const u8 = "",
    message: []const u8 = "",
};

pub const ContainmentData = struct {
    outer: []const u8 = "",
    inner: []const u8 = "",
    mode: []const u8 = "full",
};

pub const SpatialFact = struct {
    object: []const u8 = "",
    fact_type: []const u8 = "",
    // Details stored as parallel key/value slices
    detail_keys: []const []const u8 = &.{},
    detail_vals: []const []const u8 = &.{},
};

// ---------------------------------------------------------------------------
// Tier 2 -- Visual
// ---------------------------------------------------------------------------

pub const CompositionData = struct {
    thirds: f32 = 0.0,
    visible: i32 = 0,
    total: i32 = 0,
    balance: f32 = 0.0,
    depth: []const u8 = "1/3",
    edge: []const []const u8 = &.{},
};

pub const RayGridData = struct {
    resolution: i32 = 0,
    coverage_keys: []const []const u8 = &.{},
    coverage_vals: []const f32 = &.{},
    empty: f32 = 0.0,

    /// Look up a coverage value by object name.
    pub fn getCoverage(self: *const RayGridData, key: []const u8) ?f32 {
        for (self.coverage_keys, 0..) |k, i| {
            if (std.mem.eql(u8, k, key)) return self.coverage_vals[i];
        }
        return null;
    }
};

pub const MultiViewData = struct {
    view: []const u8 = "",
    coverage_keys: []const []const u8 = &.{},
    coverage_vals: []const f32 = &.{},

    pub fn getCoverage(self: *const MultiViewData, key: []const u8) ?f32 {
        for (self.coverage_keys, 0..) |k, i| {
            if (std.mem.eql(u8, k, key)) return self.coverage_vals[i];
        }
        return null;
    }
};

// ---------------------------------------------------------------------------
// Tier 3 -- Physical
// ---------------------------------------------------------------------------

pub const LightAnalysisData = struct {
    light: []const u8 = "",
    surface: []const u8 = "",
    angle: f32 = 0.0,
    intensity: f32 = 0.0,
    shadow: []const []const u8 = &.{},
};

pub const ShadowAnalysisData = struct {
    light: []const u8 = "",
    surface: []const u8 = "",
    coverage: f32 = 0.0,
    casters: []const []const u8 = &.{},
    contact: bool = false,
    gap: ?f32 = null,
};

pub const MaterialPrediction = struct {
    name: []const u8 = "",
    appearance: []const u8 = "",
    needs: ?[]const u8 = null,
    warning: ?[]const u8 = null,
};

pub const HarmonyData = struct {
    types: []const u8 = "",
    temperature: []const u8 = "",
};

pub const PaletteData = struct {
    luminance: ?f32 = null,
    palette: []const []const u8 = &.{},
};

pub const WorldData = struct {
    bg_color: ?Vec3 = null,
    hdri: bool = false,
    strength: f32 = 1.0,
};

pub const PhysicsState = struct {
    name: []const u8 = "",
    phys_type: []const u8 = "static", // static | dynamic | kinematic
    mass_kg: f32 = 0.0,
    velocity: ?Vec3 = null,
    sleeping: bool = false,
};

pub const ContactData = struct {
    obj_a: []const u8 = "",
    obj_b: []const u8 = "",
    normal: Vec3 = .{},
    force_n: f32 = 0.0,
    surface: []const u8 = "",
};

pub const SoundData = struct {
    source: []const u8 = "",
    sound_type: []const u8 = "point", // ambient | point | directional
    volume: f32 = 0.0,
    distance: f32 = 0.0,
    direction: []const u8 = "",
    occlusion: f32 = 0.0,
};

// ---------------------------------------------------------------------------
// Tier 4 -- Semantic
// ---------------------------------------------------------------------------

pub const HierarchyEntry = struct {
    chain: []const []const u8 = &.{},
};

pub const GroupEntry = struct {
    name: []const u8 = "",
    members: []const []const u8 = &.{},
};

// ---------------------------------------------------------------------------
// Tier 5 -- Temporal
// ---------------------------------------------------------------------------

pub const AnimationState = struct {
    name: []const u8 = "",
    action: []const u8 = "",
    frame: i32 = 0,
    total: i32 = 0,
    playing: bool = false,
};

// ---------------------------------------------------------------------------
// Tier containers
// ---------------------------------------------------------------------------

pub const IdentityTier = struct {
    scene_header: ?SceneHeader = null,
    cameras: []const CameraData = &.{},
    lights: []const LightData = &.{},
    objects: []const ObjectData = &.{},
    semantic_groups: []const SemanticGroupData = &.{},
    assemblies: []const AssemblyData = &.{},
};

pub const SpatialTier = struct {
    relationships: []const RelationshipData = &.{},
    verify: []const VerifyResult = &.{},
    containment: []const ContainmentData = &.{},
    spatial_facts: []const SpatialFact = &.{},
};

pub const VisualTier = struct {
    composition: ?CompositionData = null,
    ray_grid: ?RayGridData = null,
    multi_views: []const MultiViewData = &.{},
};

pub const PhysicalTier = struct {
    light_analyses: []const LightAnalysisData = &.{},
    shadow_analyses: []const ShadowAnalysisData = &.{},
    materials: []const MaterialPrediction = &.{},
    harmony: ?HarmonyData = null,
    palette: ?PaletteData = null,
    world: ?WorldData = null,
    physics_states: []const PhysicsState = &.{},
    contacts: []const ContactData = &.{},
    sounds: []const SoundData = &.{},
};

pub const SemanticTier = struct {
    hierarchy: []const HierarchyEntry = &.{},
    groups: []const GroupEntry = &.{},
};

pub const TemporalTier = struct {
    animations: []const AnimationState = &.{},
    deltas: []const []const u8 = &.{},
};

// ---------------------------------------------------------------------------
// Top-level struct
// ---------------------------------------------------------------------------

pub const ScenePerception = struct {
    viewpoint: []const u8 = "Camera",
    viewpoint_position: Vec3 = .{},
    viewpoint_forward: Vec3 = .{ .x = 0, .y = 0, .z = -1 },
    identity: IdentityTier = .{},
    spatial: SpatialTier = .{},
    visual: VisualTier = .{},
    physical: PhysicalTier = .{},
    semantic: SemanticTier = .{},
    temporal: TemporalTier = .{},
};
