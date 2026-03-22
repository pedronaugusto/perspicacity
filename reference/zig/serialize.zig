//! Perspicacity v1 -- Text DSL serializer.
//!
//! `toText(perception, allocator)` converts a `ScenePerception` into the
//! `.picacia` text format.  The returned slice is owned by `allocator`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const p = @import("perception.zig");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Format a float with minimal representation.
/// Integers become "0", "5", "500".  Fractional values keep the minimum
/// number of decimal places needed: "0.85", "5.4", "0.05".
fn fmtFloat(buf: *std.ArrayList(u8), allocator: Allocator, v: f32) !void {
    // Check if the value is an integer by comparing with @trunc
    const truncated = @trunc(v);
    if (v == truncated and @abs(v) < 1e15) {
        const iv: i64 = @intFromFloat(truncated);
        try std.fmt.format(buf.writer(allocator), "{d}", .{iv});
        return;
    }
    // Use default float formatting which gives shortest round-trip representation
    var tmp: [64]u8 = undefined;
    const written = try std.fmt.bufPrint(&tmp, "{d}", .{v});
    try buf.appendSlice(allocator, written);
}

fn fmtVec3(buf: *std.ArrayList(u8), allocator: Allocator, v: p.Vec3) !void {
    try buf.append(allocator, '[');
    try fmtFloat(buf, allocator, v.x);
    try buf.append(allocator, ',');
    try fmtFloat(buf, allocator, v.y);
    try buf.append(allocator, ',');
    try fmtFloat(buf, allocator, v.z);
    try buf.append(allocator, ']');
}

fn fmtPct(buf: *std.ArrayList(u8), allocator: Allocator, v: f32) !void {
    try fmtFloat(buf, allocator, v);
    try buf.append(allocator, '%');
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Serialize a `ScenePerception` to `.picacia` text.
/// Caller owns the returned slice.
pub fn toText(perc: p.ScenePerception, allocator: Allocator) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    const w = buf.writer(allocator);

    // Header
    try w.writeAll("# Perspicacity v1\n");

    // SCENE header
    if (perc.identity.scene_header) |sh| {
        try w.writeAll("SCENE ");
        try std.fmt.format(w, "{d}", .{sh.obj_count});
        try w.writeAll(" objects ");
        try std.fmt.format(w, "{d}", .{sh.light_count});
        try w.writeAll(" lights ");
        try fmtFloat(&buf, allocator, sh.energy);
        try w.writeAll("W ");
        try w.writeAll(sh.engine);
        if (sh.ground_z) |gz| {
            try w.writeAll(" ground_z=");
            try fmtFloat(&buf, allocator, gz);
        }
        try w.writeAll("\n");
    }

    // Tier 0 -- Identity
    for (perc.identity.cameras) |cam| {
        try w.writeAll("CAM ");
        try w.writeAll(cam.name);
        try w.writeAll(" ");
        try fmtVec3(&buf, allocator, cam.position);
        try w.writeAll(" ");
        try fmtFloat(&buf, allocator, cam.focal_mm);
        try w.writeAll("mm\n");
    }

    for (perc.identity.lights) |light| {
        try w.writeAll("LIGHT ");
        try w.writeAll(light.name);
        try w.writeAll(" ");
        try w.writeAll(light.light_type);
        try w.writeAll(" ");
        try fmtFloat(&buf, allocator, light.energy_w);
        try w.writeAll("W ");
        try fmtVec3(&buf, allocator, light.color);
        try w.writeAll(" ");
        try fmtVec3(&buf, allocator, light.position);
        try w.writeAll("\n");
    }

    for (perc.identity.objects) |obj| {
        try w.writeAll("OBJ ");
        try w.writeAll(obj.name);
        try w.writeAll(" ");
        try fmtVec3(&buf, allocator, obj.position);
        try w.writeAll(" ");
        try fmtPct(&buf, allocator, obj.coverage);
        try w.writeAll(" ");
        try w.writeAll(obj.quadrant);
        try w.writeAll(" d=");
        try fmtFloat(&buf, allocator, obj.depth);
        try w.writeAll("m ");
        try w.writeAll(obj.material);
        if (obj.dimensions) |dim| {
            try w.writeAll(" dim=");
            try fmtVec3(&buf, allocator, dim);
        }
        if (obj.rotation) |rot| {
            try w.writeAll(" rot=");
            try fmtVec3(&buf, allocator, rot);
        }
        if (obj.facing) |facing| {
            try w.writeAll(" facing=");
            try w.writeAll(facing);
        }
        if (obj.zone) |zone| {
            try w.writeAll(" zone=");
            try w.writeAll(zone);
        }
        if (obj.face) |face| {
            try w.writeAll(" face=");
            try w.writeAll(face);
        }
        if (obj.lum) |lum| {
            try w.writeAll(" lum=");
            try fmtFloat(&buf, allocator, lum);
        }
        if (obj.transparent) try w.writeAll(" transparent");
        if (obj.has_uv) |uv| {
            if (uv) {
                try w.writeAll(" has_uv");
            } else {
                try w.writeAll(" no_uv");
            }
        }
        if (obj.inside) |inside| {
            try w.writeAll(" inside=");
            try w.writeAll(inside);
        }
        if (obj.contains.len > 0) {
            try w.writeAll(" contains:[");
            for (obj.contains, 0..) |c, ci| {
                if (ci > 0) try w.writeAll(",");
                try w.writeAll(c);
            }
            try w.writeAll("]");
        }
        try w.writeAll("\n");
    }

    // SGROUP lines
    for (perc.identity.semantic_groups) |sg| {
        try w.writeAll("SGROUP \"");
        try w.writeAll(sg.name);
        try w.writeAll("\" ");
        try fmtVec3(&buf, allocator, sg.position);
        try w.writeAll(" dim=");
        try fmtVec3(&buf, allocator, sg.dimensions);
        try w.writeAll(" top=");
        try fmtFloat(&buf, allocator, sg.top_z);
        try w.writeAll(" ");
        try w.writeAll(sg.material);
        if (sg.facing) |facing| {
            try w.writeAll(" facing=");
            try w.writeAll(facing);
        }
        try w.writeAll(" members=");
        try std.fmt.format(w, "{d}", .{sg.member_count});
        try w.writeAll("\n");
    }

    // ASSEMBLY lines
    for (perc.identity.assemblies) |asm_data| {
        try w.writeAll("ASSEMBLY \"");
        try w.writeAll(asm_data.name);
        try w.writeAll("\" members=[");
        for (asm_data.members, 0..) |m, mi| {
            if (mi > 0) try w.writeAll(",");
            try w.writeAll(m);
        }
        try w.writeAll("] center=");
        try fmtVec3(&buf, allocator, asm_data.center);
        try w.writeAll(" types=");
        try w.writeAll(asm_data.types);
        try w.writeAll("\n");
    }

    // Tier 1 -- Spatial
    for (perc.spatial.relationships) |rel| {
        try w.writeAll("REL ");
        try w.writeAll(rel.from_obj);
        try w.writeAll("->");
        try w.writeAll(rel.to_obj);
        try w.writeAll(" ");
        try fmtFloat(&buf, allocator, rel.distance);
        try w.writeAll("m ");
        try w.writeAll(rel.direction);
        if (rel.vertical) |vert| {
            try w.writeAll(" ");
            try w.writeAll(vert);
        }
        if (rel.overlap) {
            if (rel.overlap_pct) |opct| {
                try w.writeAll(" overlap=");
                try fmtPct(&buf, allocator, opct);
            } else {
                try w.writeAll(" overlap");
            }
        }
        if (rel.aabb_overlap_pct) |aabb| {
            try w.writeAll(" aabb_overlap=");
            try fmtPct(&buf, allocator, aabb);
        }
        if (rel.contact) try w.writeAll(" contact");
        if (rel.occludes) try w.writeAll(" occludes");
        if (rel.occ_pct) |occ| {
            try w.writeAll(" occ=");
            try fmtPct(&buf, allocator, occ);
        }
        try w.writeAll("\n");
    }

    // VERIFY FAIL lines
    for (perc.spatial.verify) |v| {
        try w.writeAll("VERIFY FAIL ");
        try w.writeAll(v.object);
        try w.writeAll(" ");
        try w.writeAll(v.message);
        try w.writeAll("\n");
    }

    // CONTAIN lines
    for (perc.spatial.containment) |ct| {
        try w.writeAll("CONTAIN ");
        try w.writeAll(ct.outer);
        try w.writeAll(" contains ");
        try w.writeAll(ct.inner);
        try w.writeAll(" ");
        try w.writeAll(ct.mode);
        try w.writeAll("\n");
    }

    // SPATIAL lines
    for (perc.spatial.spatial_facts) |sf| {
        try w.writeAll("SPATIAL ");
        try w.writeAll(sf.object);
        try w.writeAll(" ");
        try w.writeAll(sf.fact_type);
        for (sf.detail_keys, 0..) |k, ki| {
            try w.writeAll(" ");
            try w.writeAll(k);
            try w.writeAll("=");
            try w.writeAll(sf.detail_vals[ki]);
        }
        try w.writeAll("\n");
    }

    // Tier 3 -- Physical (LIT, SHAD, MAT, HARMONY, PALETTE, WORLD before Tier 2 per ordering)
    for (perc.physical.light_analyses) |la| {
        try w.writeAll("LIT ");
        try w.writeAll(la.light);
        try w.writeAll("->");
        try w.writeAll(la.surface);
        try w.writeAll(" @");
        try fmtFloat(&buf, allocator, la.angle);
        try w.writeAll("\xc2\xb0 i="); // UTF-8 for degree sign U+00B0
        try fmtFloat(&buf, allocator, la.intensity);
        if (la.shadow.len > 0) {
            try w.writeAll(" shadow:");
            for (la.shadow, 0..) |s, i| {
                if (i > 0) try w.writeAll(",");
                try w.writeAll(s);
            }
        }
        try w.writeAll("\n");
    }

    for (perc.physical.shadow_analyses) |sa| {
        try w.writeAll("SHAD ");
        try w.writeAll(sa.light);
        try w.writeAll("->");
        try w.writeAll(sa.surface);
        try w.writeAll(" ");
        try fmtPct(&buf, allocator, sa.coverage);
        if (sa.casters.len > 0) {
            try w.writeAll(" casters:");
            for (sa.casters, 0..) |c, i| {
                if (i > 0) try w.writeAll(",");
                try w.writeAll(c);
            }
        }
        if (sa.contact) try w.writeAll(" contact");
        if (sa.gap) |g| {
            try w.writeAll(" gap=");
            try fmtFloat(&buf, allocator, g);
            try w.writeAll("m");
        }
        try w.writeAll("\n");
    }

    for (perc.physical.materials) |mat| {
        try w.writeAll("MAT ");
        try w.writeAll(mat.name);
        try w.writeAll(": ");
        try w.writeAll(mat.appearance);
        if (mat.needs) |needs| {
            try w.writeAll(" -- needs ");
            try w.writeAll(needs);
        } else if (mat.warning) |warn| {
            try w.writeAll(" -- ");
            try w.writeAll(warn);
        }
        try w.writeAll("\n");
    }

    // HARMONY
    if (perc.physical.harmony) |h| {
        try w.writeAll("HARMONY types=");
        try w.writeAll(h.types);
        try w.writeAll(" temp=");
        try w.writeAll(h.temperature);
        try w.writeAll("\n");
    }

    // PALETTE
    if (perc.physical.palette) |pal| {
        try w.writeAll("PALETTE");
        if (pal.luminance) |lum| {
            try w.writeAll(" lum=");
            try fmtFloat(&buf, allocator, lum);
        }
        for (pal.palette) |color| {
            try w.writeAll(" ");
            try w.writeAll(color);
        }
        try w.writeAll("\n");
    }

    if (perc.physical.world) |world| {
        if (world.hdri) {
            try w.writeAll("WORLD hdri strength=");
            try fmtFloat(&buf, allocator, world.strength);
            try w.writeAll("\n");
        } else if (world.bg_color) |bg| {
            try w.writeAll("WORLD bg=");
            try fmtVec3(&buf, allocator, bg);
            try w.writeAll(" strength=");
            try fmtFloat(&buf, allocator, world.strength);
            try w.writeAll("\n");
        }
    }

    for (perc.physical.physics_states) |ps| {
        try w.writeAll("PHYS ");
        try w.writeAll(ps.name);
        try w.writeAll(" ");
        try w.writeAll(ps.phys_type);
        try w.writeAll(" mass=");
        try fmtFloat(&buf, allocator, ps.mass_kg);
        try w.writeAll("kg");
        if (ps.velocity) |vel| {
            try w.writeAll(" vel=");
            try fmtVec3(&buf, allocator, vel);
        }
        if (ps.sleeping) try w.writeAll(" sleeping");
        try w.writeAll("\n");
    }

    for (perc.physical.contacts) |ct| {
        try w.writeAll("CONTACT ");
        try w.writeAll(ct.obj_a);
        try w.writeAll("<>");
        try w.writeAll(ct.obj_b);
        try w.writeAll(" normal=");
        try fmtVec3(&buf, allocator, ct.normal);
        try w.writeAll(" force=");
        try fmtFloat(&buf, allocator, ct.force_n);
        try w.writeAll("N surface=");
        try w.writeAll(ct.surface);
        try w.writeAll("\n");
    }

    for (perc.physical.sounds) |snd| {
        try w.writeAll("SND ");
        try w.writeAll(snd.source);
        try w.writeAll(" type=");
        try w.writeAll(snd.sound_type);
        try w.writeAll(" vol=");
        try fmtFloat(&buf, allocator, snd.volume);
        try w.writeAll(" dist=");
        try fmtFloat(&buf, allocator, snd.distance);
        try w.writeAll("m dir=");
        try w.writeAll(snd.direction);
        try w.writeAll(" occ=");
        try fmtFloat(&buf, allocator, snd.occlusion);
        try w.writeAll("\n");
    }

    // Tier 2 -- Visual
    if (perc.visual.composition) |comp| {
        try w.writeAll("COMP thirds=");
        try fmtFloat(&buf, allocator, comp.thirds);
        try w.writeAll(" ");
        try std.fmt.format(w, "{d}/{d}_visible", .{ comp.visible, comp.total });
        try w.writeAll(" balance=");
        try fmtFloat(&buf, allocator, comp.balance);
        try w.writeAll(" depth=");
        try w.writeAll(comp.depth);
        if (comp.edge.len > 0) {
            try w.writeAll(" edge:[");
            for (comp.edge, 0..) |e, i| {
                if (i > 0) try w.writeAll(",");
                try w.writeAll(e);
            }
            try w.writeAll("]");
        }
        try w.writeAll("\n");
    }

    if (perc.visual.ray_grid) |rg| {
        try w.writeAll("RAY ");
        try std.fmt.format(w, "{d}x{d}", .{ rg.resolution, rg.resolution });
        for (rg.coverage_keys, 0..) |key, i| {
            try w.writeAll(" ");
            try w.writeAll(key);
            try w.writeAll("=");
            try fmtPct(&buf, allocator, rg.coverage_vals[i]);
        }
        if (rg.empty > 0) {
            try w.writeAll(" empty=");
            try fmtPct(&buf, allocator, rg.empty);
        }
        try w.writeAll("\n");
    }

    for (perc.visual.multi_views) |mv| {
        try w.writeAll("MVIEW ");
        try w.writeAll(mv.view);
        try w.writeAll(":");
        for (mv.coverage_keys, 0..) |key, i| {
            try w.writeAll(" ");
            try w.writeAll(key);
            try w.writeAll("=");
            try fmtPct(&buf, allocator, mv.coverage_vals[i]);
        }
        try w.writeAll("\n");
    }

    // Tier 4 -- Semantic
    for (perc.semantic.hierarchy) |h| {
        try w.writeAll("HIER ");
        for (h.chain, 0..) |c, i| {
            if (i > 0) try w.writeAll(" > ");
            try w.writeAll(c);
        }
        try w.writeAll("\n");
    }

    for (perc.semantic.groups) |g| {
        try w.writeAll("GRP ");
        try w.writeAll(g.name);
        try w.writeAll(": ");
        for (g.members, 0..) |m, i| {
            if (i > 0) try w.writeAll(", ");
            try w.writeAll(m);
        }
        try w.writeAll("\n");
    }

    // Tier 5 -- Temporal
    for (perc.temporal.animations) |a| {
        try w.writeAll("ANIM ");
        try w.writeAll(a.name);
        try w.writeAll(" action=");
        try w.writeAll(a.action);
        try w.writeAll(" frame=");
        try std.fmt.format(w, "{d}/{d}", .{ a.frame, a.total });
        if (a.playing) {
            try w.writeAll(" playing");
        } else {
            try w.writeAll(" stopped");
        }
        try w.writeAll("\n");
    }

    for (perc.temporal.deltas) |d| {
        try w.writeAll("DELTA ");
        try w.writeAll(d);
        try w.writeAll("\n");
    }

    return buf.toOwnedSlice(allocator);
}
