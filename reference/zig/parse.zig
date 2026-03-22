//! Perspicacity v1 -- Text DSL parser.
//!
//! `fromText(text, allocator)` parses `.picacia` text into a `ScenePerception`.
//! All strings in the returned struct are owned by `allocator`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const p = @import("perception.zig");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn parseVec3(s: []const u8) p.Vec3 {
    var clean = s;
    if (clean.len > 0 and clean[0] == '[') clean = clean[1..];
    if (clean.len > 0 and clean[clean.len - 1] == ']') clean = clean[0 .. clean.len - 1];

    var it = std.mem.splitScalar(u8, clean, ',');
    const x = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
    const y = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
    const z = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
    return .{ .x = x, .y = y, .z = z };
}

fn parsePct(s: []const u8) f32 {
    const trimmed = std.mem.trimRight(u8, s, "%");
    return std.fmt.parseFloat(f32, trimmed) catch 0;
}

fn parseDist(s: []const u8) f32 {
    const trimmed = std.mem.trimRight(u8, s, "m");
    return std.fmt.parseFloat(f32, trimmed) catch 0;
}

/// Split `A->B` or `A\u{2192}B` into (A, B).
fn splitArrow(s: []const u8) struct { []const u8, []const u8 } {
    // Try ASCII arrow first
    if (std.mem.indexOf(u8, s, "->")) |idx| {
        return .{ s[0..idx], s[idx + 2 ..] };
    }
    // Try unicode arrow U+2192 (3 bytes in UTF-8: E2 86 92)
    const arrow_bytes = "\xe2\x86\x92";
    if (std.mem.indexOf(u8, s, arrow_bytes)) |idx| {
        return .{ s[0..idx], s[idx + 3 ..] };
    }
    return .{ s, "" };
}

/// Find a complete Vec3 token starting at `start`.  The vec3 `[x,y,z]`
/// is normally a single token but may be split if it contained spaces.
fn findVec3Token(tokens: []const []const u8, start: usize, allocator: Allocator) !struct { []const u8, usize } {
    if (start >= tokens.len) {
        const empty = try allocator.dupe(u8, "[]");
        return .{ empty, start + 1 };
    }
    var combined: std.ArrayList(u8) = .empty;
    defer combined.deinit(allocator);
    try combined.appendSlice(allocator, tokens[start]);
    var idx = start;
    while (std.mem.count(u8, combined.items, "[") > std.mem.count(u8, combined.items, "]")) {
        idx += 1;
        if (idx >= tokens.len) break;
        try combined.append(allocator, ',');
        try combined.appendSlice(allocator, tokens[idx]);
    }
    const result = try allocator.dupe(u8, combined.items);
    return .{ result, idx + 1 };
}

/// Split `text` by whitespace into a list of tokens.
fn tokenize(text: []const u8, allocator: Allocator) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);
    var it = std.mem.tokenizeAny(u8, text, " \t");
    while (it.next()) |tok| {
        try list.append(allocator, tok);
    }
    return list.toOwnedSlice(allocator);
}

/// Duplicate a slice of strings using `allocator`.
fn dupeStr(allocator: Allocator, s: []const u8) ![]const u8 {
    return allocator.dupe(u8, s);
}

/// Split comma-separated values.
fn splitComma(s: []const u8, allocator: Allocator) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);
    var it = std.mem.splitScalar(u8, s, ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (trimmed.len > 0) {
            try list.append(allocator, try dupeStr(allocator, trimmed));
        }
    }
    return list.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Line parsers
// ---------------------------------------------------------------------------

fn parseScene(rest: []const u8, scene_header: *?p.SceneHeader, allocator: Allocator) !void {
    const tokens_raw = try tokenize(rest, allocator);
    defer allocator.free(tokens_raw);
    if (tokens_raw.len < 5) return;

    // "N objects N lights NW ENGINE [ground_z=N]"
    const obj_count = std.fmt.parseInt(i32, tokens_raw[0], 10) catch 0;
    // tokens_raw[1] == "objects"
    const light_count = std.fmt.parseInt(i32, tokens_raw[2], 10) catch 0;
    // tokens_raw[3] == "lights"
    const energy = std.fmt.parseFloat(f32, std.mem.trimRight(u8, tokens_raw[4], "W")) catch 0;

    var engine: []const u8 = "";
    var ground_z: ?f32 = null;

    var i: usize = 5;
    while (i < tokens_raw.len) : (i += 1) {
        const t = tokens_raw[i];
        if (std.mem.startsWith(u8, t, "ground_z=")) {
            ground_z = std.fmt.parseFloat(f32, t[9..]) catch null;
        } else if (!std.mem.startsWith(u8, t, "ground_z=") and engine.len == 0) {
            engine = t;
        }
    }

    scene_header.* = .{
        .obj_count = obj_count,
        .light_count = light_count,
        .energy = energy,
        .engine = engine,
        .ground_z = ground_z,
    };
}

fn parseCam(rest: []const u8, cameras: *std.ArrayList(p.CameraData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 1) return;

    const name = try dupeStr(allocator, tokens[0]);
    const vec_result = try findVec3Token(tokens, 1, allocator);
    defer allocator.free(vec_result[0]);
    const pos = parseVec3(vec_result[0]);
    const next = vec_result[1];

    var focal: f32 = 50.0;
    if (next < tokens.len) {
        const fstr = std.mem.trimRight(u8, tokens[next], "m");
        // "50mm" -> trimRight of 'm' -> "50"
        focal = std.fmt.parseFloat(f32, fstr) catch 50.0;
    }

    try cameras.append(allocator, .{ .name = name, .position = pos, .focal_mm = focal });
}

fn parseLight(rest: []const u8, lights: *std.ArrayList(p.LightData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 4) return;

    const name = try dupeStr(allocator, tokens[0]);
    const ltype = try dupeStr(allocator, tokens[1]);
    const energy = std.fmt.parseFloat(f32, std.mem.trimRight(u8, tokens[2], "W")) catch 0;

    const color_result = try findVec3Token(tokens, 3, allocator);
    defer allocator.free(color_result[0]);
    const color = parseVec3(color_result[0]);

    const pos_result = try findVec3Token(tokens, color_result[1], allocator);
    defer allocator.free(pos_result[0]);
    const pos = parseVec3(pos_result[0]);

    try lights.append(allocator, .{
        .name = name,
        .light_type = ltype,
        .energy_w = energy,
        .color = color,
        .position = pos,
    });
}

fn parseObj(rest: []const u8, objects: *std.ArrayList(p.ObjectData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 5) return;

    const name = try dupeStr(allocator, tokens[0]);
    const vec_result = try findVec3Token(tokens, 1, allocator);
    defer allocator.free(vec_result[0]);
    const pos = parseVec3(vec_result[0]);
    const ni = vec_result[1];

    const coverage = parsePct(tokens[ni]);
    const quadrant = try dupeStr(allocator, tokens[ni + 1]);

    // d=5.0m
    const depth_tok = tokens[ni + 2];
    var depth: f32 = 0;
    if (std.mem.indexOf(u8, depth_tok, "=")) |eq| {
        depth = parseDist(depth_tok[eq + 1 ..]);
    }

    const material = try dupeStr(allocator, tokens[ni + 3]);

    var face: ?[]const u8 = null;
    var lum: ?f32 = null;
    var dimensions: ?p.Vec3 = null;
    var top_z: ?f32 = null;
    var rotation: ?p.Vec3 = null;
    var facing: ?[]const u8 = null;
    var zone: ?[]const u8 = null;
    var transparent = false;
    var has_uv: ?bool = null;
    var inside: ?[]const u8 = null;
    var contains_list: std.ArrayList([]const u8) = .empty;

    var i: usize = ni + 4;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.startsWith(u8, t, "dim=")) {
            // Collect vec3 token starting from this token
            var dim_combined: std.ArrayList(u8) = .empty;
            defer dim_combined.deinit(allocator);
            try dim_combined.appendSlice(allocator, t[4..]);
            while (std.mem.count(u8, dim_combined.items, "[") > std.mem.count(u8, dim_combined.items, "]")) {
                i += 1;
                if (i >= tokens.len) break;
                try dim_combined.append(allocator, ',');
                try dim_combined.appendSlice(allocator, tokens[i]);
            }
            dimensions = parseVec3(dim_combined.items);
        } else if (std.mem.startsWith(u8, t, "top=")) {
            top_z = std.fmt.parseFloat(f32, t[4..]) catch null;
        } else if (std.mem.startsWith(u8, t, "rot=")) {
            var rot_combined: std.ArrayList(u8) = .empty;
            defer rot_combined.deinit(allocator);
            try rot_combined.appendSlice(allocator, t[4..]);
            while (std.mem.count(u8, rot_combined.items, "[") > std.mem.count(u8, rot_combined.items, "]")) {
                i += 1;
                if (i >= tokens.len) break;
                try rot_combined.append(allocator, ',');
                try rot_combined.appendSlice(allocator, tokens[i]);
            }
            rotation = parseVec3(rot_combined.items);
        } else if (std.mem.startsWith(u8, t, "facing=")) {
            facing = try dupeStr(allocator, t[7..]);
        } else if (std.mem.startsWith(u8, t, "zone=")) {
            zone = try dupeStr(allocator, t[5..]);
        } else if (std.mem.startsWith(u8, t, "face=")) {
            face = try dupeStr(allocator, t[5..]);
        } else if (std.mem.startsWith(u8, t, "lum=")) {
            lum = std.fmt.parseFloat(f32, t[4..]) catch null;
        } else if (std.mem.eql(u8, t, "transparent")) {
            transparent = true;
        } else if (std.mem.eql(u8, t, "has_uv")) {
            has_uv = true;
        } else if (std.mem.eql(u8, t, "no_uv")) {
            has_uv = false;
        } else if (std.mem.startsWith(u8, t, "inside=")) {
            inside = try dupeStr(allocator, t[7..]);
        } else if (std.mem.startsWith(u8, t, "contains:[")) {
            // contains:[A,B,C]
            const bracket_content = t[10 .. t.len - 1]; // strip "contains:[" and "]"
            if (bracket_content.len > 0) {
                var cit = std.mem.splitScalar(u8, bracket_content, ',');
                while (cit.next()) |part| {
                    const trimmed = std.mem.trim(u8, part, " ");
                    if (trimmed.len > 0) {
                        try contains_list.append(allocator, try dupeStr(allocator, trimmed));
                    }
                }
            }
        }
        // Ignore unknown tokens
    }

    try objects.append(allocator, .{
        .name = name,
        .position = pos,
        .coverage = coverage,
        .quadrant = quadrant,
        .depth = depth,
        .material = material,
        .dimensions = dimensions,
        .top_z = top_z,
        .rotation = rotation,
        .facing = facing,
        .zone = zone,
        .face = face,
        .lum = lum,
        .transparent = transparent,
        .has_uv = has_uv,
        .inside = inside,
        .contains = try contains_list.toOwnedSlice(allocator),
    });
}

fn parseSgroup(rest: []const u8, sgroups: *std.ArrayList(p.SemanticGroupData), allocator: Allocator) !void {
    // Extract quoted name
    var name: []const u8 = "";
    var after_name: []const u8 = rest;

    if (rest.len > 0 and rest[0] == '"') {
        if (std.mem.indexOfPos(u8, rest, 1, "\"")) |end_quote| {
            name = try dupeStr(allocator, rest[1..end_quote]);
            after_name = std.mem.trim(u8, rest[end_quote + 1 ..], " \t");
        }
    }

    const tokens = try tokenize(after_name, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 1) return;

    const vec_result = try findVec3Token(tokens, 0, allocator);
    defer allocator.free(vec_result[0]);
    const position = parseVec3(vec_result[0]);

    var dimensions = p.Vec3{};
    var top_z: f32 = 0.0;
    var material: []const u8 = try dupeStr(allocator, "");
    var facing: ?[]const u8 = null;
    var member_count: i32 = 0;

    var i: usize = vec_result[1];
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.startsWith(u8, t, "dim=")) {
            var dim_combined: std.ArrayList(u8) = .empty;
            defer dim_combined.deinit(allocator);
            try dim_combined.appendSlice(allocator, t[4..]);
            while (std.mem.count(u8, dim_combined.items, "[") > std.mem.count(u8, dim_combined.items, "]")) {
                i += 1;
                if (i >= tokens.len) break;
                try dim_combined.append(allocator, ',');
                try dim_combined.appendSlice(allocator, tokens[i]);
            }
            dimensions = parseVec3(dim_combined.items);
        } else if (std.mem.startsWith(u8, t, "top=")) {
            top_z = std.fmt.parseFloat(f32, t[4..]) catch 0;
        } else if (std.mem.startsWith(u8, t, "facing=")) {
            facing = try dupeStr(allocator, t[7..]);
        } else if (std.mem.startsWith(u8, t, "members=")) {
            member_count = std.fmt.parseInt(i32, t[8..], 10) catch 0;
        } else {
            // Must be material (not a known key=value prefix)
            allocator.free(material);
            material = try dupeStr(allocator, t);
        }
    }

    try sgroups.append(allocator, .{
        .name = name,
        .position = position,
        .dimensions = dimensions,
        .top_z = top_z,
        .material = material,
        .facing = facing,
        .member_count = member_count,
    });
}

fn parseAssembly(rest: []const u8, assemblies: *std.ArrayList(p.AssemblyData), allocator: Allocator) !void {
    // Extract quoted name
    var name: []const u8 = "";
    var after_name: []const u8 = rest;

    if (rest.len > 0 and rest[0] == '"') {
        if (std.mem.indexOfPos(u8, rest, 1, "\"")) |end_quote| {
            name = try dupeStr(allocator, rest[1..end_quote]);
            after_name = std.mem.trim(u8, rest[end_quote + 1 ..], " \t");
        }
    }

    const tokens = try tokenize(after_name, allocator);
    defer allocator.free(tokens);

    var members: std.ArrayList([]const u8) = .empty;
    var center = p.Vec3{};
    var types: []const u8 = try dupeStr(allocator, "");

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.startsWith(u8, t, "members=[")) {
            // Collect the members list: "members=[A,B,C]" possibly spanning tokens
            var members_str_buf: std.ArrayList(u8) = .empty;
            defer members_str_buf.deinit(allocator);
            try members_str_buf.appendSlice(allocator, t[9..]); // after "members=["
            while (std.mem.indexOf(u8, members_str_buf.items, "]") == null) {
                i += 1;
                if (i >= tokens.len) break;
                try members_str_buf.append(allocator, ',');
                try members_str_buf.appendSlice(allocator, tokens[i]);
            }
            // Strip trailing ']'
            var ms = members_str_buf.items;
            if (ms.len > 0 and ms[ms.len - 1] == ']') {
                ms = ms[0 .. ms.len - 1];
            }
            var mit = std.mem.splitScalar(u8, ms, ',');
            while (mit.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " ");
                if (trimmed.len > 0) {
                    try members.append(allocator, try dupeStr(allocator, trimmed));
                }
            }
        } else if (std.mem.startsWith(u8, t, "center=")) {
            var center_combined: std.ArrayList(u8) = .empty;
            defer center_combined.deinit(allocator);
            try center_combined.appendSlice(allocator, t[7..]);
            while (std.mem.count(u8, center_combined.items, "[") > std.mem.count(u8, center_combined.items, "]")) {
                i += 1;
                if (i >= tokens.len) break;
                try center_combined.append(allocator, ',');
                try center_combined.appendSlice(allocator, tokens[i]);
            }
            center = parseVec3(center_combined.items);
        } else if (std.mem.startsWith(u8, t, "types=")) {
            allocator.free(types);
            types = try dupeStr(allocator, t[6..]);
        }
    }

    try assemblies.append(allocator, .{
        .name = name,
        .members = try members.toOwnedSlice(allocator),
        .center = center,
        .types = types,
    });
}

fn parseRel(rest: []const u8, rels: *std.ArrayList(p.RelationshipData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 3) return;

    const arrow = splitArrow(tokens[0]);
    const from_obj = try dupeStr(allocator, arrow[0]);
    const to_obj = try dupeStr(allocator, arrow[1]);
    const distance = parseDist(tokens[1]);
    const direction = try dupeStr(allocator, tokens[2]);

    var vertical: ?[]const u8 = null;
    var overlap = false;
    var overlap_pct: ?f32 = null;
    var aabb_overlap_pct: ?f32 = null;
    var contact = false;
    var occludes = false;
    var occ_pct: ?f32 = null;

    var i: usize = 3;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.eql(u8, t, "same_level") or std.mem.eql(u8, t, "above") or std.mem.eql(u8, t, "below")) {
            vertical = try dupeStr(allocator, t);
        } else if (std.mem.startsWith(u8, t, "overlap=")) {
            overlap = true;
            overlap_pct = parsePct(t[8..]);
        } else if (std.mem.eql(u8, t, "overlap")) {
            overlap = true;
        } else if (std.mem.startsWith(u8, t, "aabb_overlap=")) {
            aabb_overlap_pct = parsePct(t[13..]);
        } else if (std.mem.eql(u8, t, "contact")) {
            contact = true;
        } else if (std.mem.eql(u8, t, "occludes")) {
            occludes = true;
        } else if (std.mem.startsWith(u8, t, "occ=")) {
            occ_pct = parsePct(t[4..]);
        }
    }

    try rels.append(allocator, .{
        .from_obj = from_obj,
        .to_obj = to_obj,
        .distance = distance,
        .direction = direction,
        .vertical = vertical,
        .overlap = overlap,
        .overlap_pct = overlap_pct,
        .aabb_overlap_pct = aabb_overlap_pct,
        .contact = contact,
        .occludes = occludes,
        .occ_pct = occ_pct,
    });
}

fn parseVerify(rest: []const u8, verify_list: *std.ArrayList(p.VerifyResult), allocator: Allocator) !void {
    // rest = "FAIL ObjName reason text..."
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 3) return;

    // tokens[0] is "FAIL"
    const object = try dupeStr(allocator, tokens[1]);

    // Reconstruct message from remaining tokens
    var msg_buf: std.ArrayList(u8) = .empty;
    var i: usize = 2;
    while (i < tokens.len) : (i += 1) {
        if (i > 2) try msg_buf.append(allocator, ' ');
        try msg_buf.appendSlice(allocator, tokens[i]);
    }
    const message = try msg_buf.toOwnedSlice(allocator);

    try verify_list.append(allocator, .{
        .object = object,
        .message = message,
    });
}

fn parseContain(rest: []const u8, containment: *std.ArrayList(p.ContainmentData), allocator: Allocator) !void {
    // "Outer contains Inner mode"
    if (std.mem.indexOf(u8, rest, " contains ")) |ci| {
        const outer = try dupeStr(allocator, std.mem.trim(u8, rest[0..ci], " "));
        const remainder = rest[ci + 10 ..]; // after " contains "
        // Last word is mode
        const trimmed = std.mem.trim(u8, remainder, " ");
        if (std.mem.lastIndexOf(u8, trimmed, " ")) |last_sp| {
            const inner = try dupeStr(allocator, std.mem.trim(u8, trimmed[0..last_sp], " "));
            const mode = try dupeStr(allocator, std.mem.trim(u8, trimmed[last_sp + 1 ..], " "));
            try containment.append(allocator, .{ .outer = outer, .inner = inner, .mode = mode });
        } else {
            const inner = try dupeStr(allocator, trimmed);
            const mode = try dupeStr(allocator, "full");
            try containment.append(allocator, .{ .outer = outer, .inner = inner, .mode = mode });
        }
    }
}

fn parseSpatial(rest: []const u8, facts: *std.ArrayList(p.SpatialFact), allocator: Allocator) !void {
    // "ObjName fact_type key=value key=value ..."
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 2) return;

    const object = try dupeStr(allocator, tokens[0]);
    const fact_type = try dupeStr(allocator, tokens[1]);

    var keys: std.ArrayList([]const u8) = .empty;
    var vals: std.ArrayList([]const u8) = .empty;

    var i: usize = 2;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.indexOf(u8, t, "=")) |eq| {
            try keys.append(allocator, try dupeStr(allocator, t[0..eq]));
            // Handle vec3 values that may span tokens
            var val_buf: std.ArrayList(u8) = .empty;
            defer val_buf.deinit(allocator);
            try val_buf.appendSlice(allocator, t[eq + 1 ..]);
            while (std.mem.count(u8, val_buf.items, "[") > std.mem.count(u8, val_buf.items, "]")) {
                i += 1;
                if (i >= tokens.len) break;
                try val_buf.append(allocator, ',');
                try val_buf.appendSlice(allocator, tokens[i]);
            }
            try vals.append(allocator, try dupeStr(allocator, val_buf.items));
        }
    }

    try facts.append(allocator, .{
        .object = object,
        .fact_type = fact_type,
        .detail_keys = try keys.toOwnedSlice(allocator),
        .detail_vals = try vals.toOwnedSlice(allocator),
    });
}

fn parseLit(rest: []const u8, las: *std.ArrayList(p.LightAnalysisData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 3) return;

    const arrow = splitArrow(tokens[0]);
    const light = try dupeStr(allocator, arrow[0]);
    const surface = try dupeStr(allocator, arrow[1]);

    // @42\u00b0 -> strip '@' and degree sign
    var angle_str = tokens[1];
    if (angle_str.len > 0 and angle_str[0] == '@') angle_str = angle_str[1..];
    // Strip trailing degree sign (UTF-8: C2 B0)
    if (angle_str.len >= 2 and angle_str[angle_str.len - 2] == 0xC2 and angle_str[angle_str.len - 1] == 0xB0) {
        angle_str = angle_str[0 .. angle_str.len - 2];
    }
    const angle = std.fmt.parseFloat(f32, angle_str) catch 0;

    // i=0.85
    var intensity: f32 = 0;
    if (std.mem.indexOf(u8, tokens[2], "=")) |eq| {
        intensity = std.fmt.parseFloat(f32, tokens[2][eq + 1 ..]) catch 0;
    }

    var shadow: []const []const u8 = &.{};
    var i: usize = 3;
    while (i < tokens.len) : (i += 1) {
        if (std.mem.startsWith(u8, tokens[i], "shadow:")) {
            shadow = try splitComma(tokens[i][7..], allocator);
        }
    }

    try las.append(allocator, .{
        .light = light,
        .surface = surface,
        .angle = angle,
        .intensity = intensity,
        .shadow = shadow,
    });
}

fn parseShad(rest: []const u8, sas: *std.ArrayList(p.ShadowAnalysisData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 2) return;

    const arrow = splitArrow(tokens[0]);
    const light = try dupeStr(allocator, arrow[0]);
    const surface = try dupeStr(allocator, arrow[1]);
    const coverage = parsePct(tokens[1]);

    var casters: []const []const u8 = &.{};
    var contact = false;
    var gap: ?f32 = null;

    var i: usize = 2;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.startsWith(u8, t, "casters:")) {
            casters = try splitComma(t[8..], allocator);
        } else if (std.mem.eql(u8, t, "contact")) {
            contact = true;
        } else if (std.mem.startsWith(u8, t, "gap=")) {
            gap = parseDist(t[4..]);
        }
    }

    try sas.append(allocator, .{
        .light = light,
        .surface = surface,
        .coverage = coverage,
        .casters = casters,
        .contact = contact,
        .gap = gap,
    });
}

fn parseMat(rest: []const u8, mats: *std.ArrayList(p.MaterialPrediction), allocator: Allocator) !void {
    // rest is "name: appearance [-- notes]"
    const colon_idx = std.mem.indexOf(u8, rest, ": ") orelse return;
    const name = try dupeStr(allocator, rest[0..colon_idx]);
    var after = rest[colon_idx + 2 ..];

    var needs: ?[]const u8 = null;
    var warning: ?[]const u8 = null;
    var appearance: []const u8 = "";

    if (std.mem.indexOf(u8, after, " -- ")) |dash_idx| {
        appearance = try dupeStr(allocator, after[0..dash_idx]);
        const note = std.mem.trim(u8, after[dash_idx + 4 ..], " ");
        if (std.mem.startsWith(u8, note, "needs ")) {
            needs = try dupeStr(allocator, note[6..]);
        } else if (note.len > 0) {
            warning = try dupeStr(allocator, note);
        }
    } else {
        appearance = try dupeStr(allocator, after);
    }

    try mats.append(allocator, .{
        .name = name,
        .appearance = appearance,
        .needs = needs,
        .warning = warning,
    });
}

fn parseHarmony(rest: []const u8, harmony: *?p.HarmonyData, allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);

    var types: []const u8 = "";
    var temperature: []const u8 = "";

    for (tokens) |t| {
        if (std.mem.startsWith(u8, t, "types=")) {
            types = t[6..];
        } else if (std.mem.startsWith(u8, t, "temp=")) {
            temperature = t[5..];
        }
    }

    harmony.* = .{
        .types = types,
        .temperature = temperature,
    };
}

fn parsePalette(rest: []const u8, palette: *?p.PaletteData, allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);

    var luminance: ?f32 = null;
    var colors: std.ArrayList([]const u8) = .empty;

    for (tokens) |t| {
        if (std.mem.startsWith(u8, t, "lum=")) {
            luminance = std.fmt.parseFloat(f32, t[4..]) catch null;
        } else {
            try colors.append(allocator, try dupeStr(allocator, t));
        }
    }

    palette.* = .{
        .luminance = luminance,
        .palette = try colors.toOwnedSlice(allocator),
    };
}

fn parseWorld(rest: []const u8, physical: *PhysicalBuilder) void {
    if (std.mem.startsWith(u8, rest, "hdri")) {
        var strength: f32 = 1.0;
        if (std.mem.indexOf(u8, rest, "strength=")) |si| {
            strength = std.fmt.parseFloat(f32, rest[si + 9 ..]) catch 1.0;
        }
        physical.world = .{ .hdri = true, .strength = strength };
    } else if (std.mem.startsWith(u8, rest, "bg=")) {
        const bracket_end = (std.mem.indexOf(u8, rest, "]") orelse return) + 1;
        const bg_str = rest[3..bracket_end];
        var strength: f32 = 1.0;
        if (std.mem.indexOf(u8, rest[bracket_end..], "strength=")) |si| {
            strength = std.fmt.parseFloat(f32, rest[bracket_end + si + 9 ..]) catch 1.0;
        }
        physical.world = .{ .bg_color = parseVec3(bg_str), .strength = strength };
    }
}

fn parsePhys(rest: []const u8, states: *std.ArrayList(p.PhysicsState), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 3) return;

    const name = try dupeStr(allocator, tokens[0]);
    const ptype = try dupeStr(allocator, tokens[1]);

    // mass=25.0kg
    var mass: f32 = 0;
    if (std.mem.indexOf(u8, tokens[2], "=")) |eq| {
        mass = std.fmt.parseFloat(f32, std.mem.trimRight(u8, tokens[2][eq + 1 ..], "kg")) catch 0;
    }

    var velocity: ?p.Vec3 = null;
    var sleeping = false;

    var i: usize = 3;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.startsWith(u8, t, "vel=")) {
            // Collect possible multi-token vec3
            var vec_str_list: std.ArrayList(u8) = .empty;
            defer vec_str_list.deinit(allocator);
            try vec_str_list.appendSlice(allocator, t[4..]);
            while (std.mem.count(u8, vec_str_list.items, "[") > std.mem.count(u8, vec_str_list.items, "]")) {
                i += 1;
                if (i >= tokens.len) break;
                try vec_str_list.append(allocator, ',');
                try vec_str_list.appendSlice(allocator, tokens[i]);
            }
            velocity = parseVec3(vec_str_list.items);
        } else if (std.mem.eql(u8, t, "sleeping")) {
            sleeping = true;
        }
    }

    try states.append(allocator, .{
        .name = name,
        .phys_type = ptype,
        .mass_kg = mass,
        .velocity = velocity,
        .sleeping = sleeping,
    });
}

fn parseContact(rest: []const u8, contacts: *std.ArrayList(p.ContactData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 4) return;

    // A<>B
    const ab = std.mem.indexOf(u8, tokens[0], "<>") orelse return;
    const obj_a = try dupeStr(allocator, tokens[0][0..ab]);
    const obj_b = try dupeStr(allocator, tokens[0][ab + 2 ..]);

    // normal=[x,y,z]
    var normal_str_buf: std.ArrayList(u8) = .empty;
    defer normal_str_buf.deinit(allocator);
    if (std.mem.indexOf(u8, tokens[1], "=")) |eq| {
        try normal_str_buf.appendSlice(allocator, tokens[1][eq + 1 ..]);
    }
    var idx: usize = 2;
    while (std.mem.count(u8, normal_str_buf.items, "[") > std.mem.count(u8, normal_str_buf.items, "]")) {
        if (idx >= tokens.len) break;
        try normal_str_buf.append(allocator, ',');
        try normal_str_buf.appendSlice(allocator, tokens[idx]);
        idx += 1;
    }
    const normal = parseVec3(normal_str_buf.items);

    // force=XN
    var force: f32 = 0;
    if (idx < tokens.len) {
        if (std.mem.indexOf(u8, tokens[idx], "=")) |eq| {
            force = std.fmt.parseFloat(f32, std.mem.trimRight(u8, tokens[idx][eq + 1 ..], "N")) catch 0;
        }
        idx += 1;
    }

    // surface=material
    var surface: []const u8 = "";
    if (idx < tokens.len) {
        if (std.mem.indexOf(u8, tokens[idx], "=")) |eq| {
            surface = try dupeStr(allocator, tokens[idx][eq + 1 ..]);
        }
    }

    try contacts.append(allocator, .{
        .obj_a = obj_a,
        .obj_b = obj_b,
        .normal = normal,
        .force_n = force,
        .surface = surface,
    });
}

fn parseSnd(rest: []const u8, sounds: *std.ArrayList(p.SoundData), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 1) return;

    const source = try dupeStr(allocator, tokens[0]);
    var stype: []const u8 = try dupeStr(allocator, "point");
    var volume: f32 = 0;
    var distance: f32 = 0;
    var direction: []const u8 = try dupeStr(allocator, "");
    var occlusion: f32 = 0;

    var i: usize = 1;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.startsWith(u8, t, "type=")) {
            allocator.free(stype);
            stype = try dupeStr(allocator, t[5..]);
        } else if (std.mem.startsWith(u8, t, "vol=")) {
            volume = std.fmt.parseFloat(f32, t[4..]) catch 0;
        } else if (std.mem.startsWith(u8, t, "dist=")) {
            distance = parseDist(t[5..]);
        } else if (std.mem.startsWith(u8, t, "dir=")) {
            allocator.free(direction);
            direction = try dupeStr(allocator, t[4..]);
        } else if (std.mem.startsWith(u8, t, "occ=")) {
            occlusion = std.fmt.parseFloat(f32, t[4..]) catch 0;
        }
    }

    try sounds.append(allocator, .{
        .source = source,
        .sound_type = stype,
        .volume = volume,
        .distance = distance,
        .direction = direction,
        .occlusion = occlusion,
    });
}

fn parseComp(rest: []const u8, visual: *VisualBuilder, allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 4) return;

    // thirds=0.71
    var thirds: f32 = 0;
    if (std.mem.indexOf(u8, tokens[0], "=")) |eq| {
        thirds = std.fmt.parseFloat(f32, tokens[0][eq + 1 ..]) catch 0;
    }

    // 3/3_visible -> strip "_visible" suffix
    var vis_str = tokens[1];
    if (std.mem.endsWith(u8, vis_str, "_visible")) {
        vis_str = vis_str[0 .. vis_str.len - 8];
    }
    var visible: i32 = 0;
    var total: i32 = 0;
    if (std.mem.indexOf(u8, vis_str, "/")) |slash| {
        visible = std.fmt.parseInt(i32, vis_str[0..slash], 10) catch 0;
        total = std.fmt.parseInt(i32, vis_str[slash + 1 ..], 10) catch 0;
    }

    // balance=0.62
    var balance: f32 = 0;
    if (std.mem.indexOf(u8, tokens[2], "=")) |eq| {
        balance = std.fmt.parseFloat(f32, tokens[2][eq + 1 ..]) catch 0;
    }

    // depth=1/3
    var depth: []const u8 = "1/3";
    if (std.mem.indexOf(u8, tokens[3], "=")) |eq| {
        depth = try dupeStr(allocator, tokens[3][eq + 1 ..]);
    }

    var edge: []const []const u8 = &.{};
    var i: usize = 4;
    while (i < tokens.len) : (i += 1) {
        if (std.mem.startsWith(u8, tokens[i], "edge:[")) {
            const edge_str = tokens[i][6 .. tokens[i].len - 1];
            edge = try splitComma(edge_str, allocator);
        }
    }

    visual.composition = .{
        .thirds = thirds,
        .visible = visible,
        .total = total,
        .balance = balance,
        .depth = depth,
        .edge = edge,
    };
}

fn parseRay(rest: []const u8, visual: *VisualBuilder, allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 1) return;

    // 12x12
    var res: i32 = 0;
    if (std.mem.indexOf(u8, tokens[0], "x")) |xi| {
        res = std.fmt.parseInt(i32, tokens[0][0..xi], 10) catch 0;
    }

    var keys: std.ArrayList([]const u8) = .empty;
    var vals: std.ArrayList(f32) = .empty;
    var empty: f32 = 0;

    var i: usize = 1;
    while (i < tokens.len) : (i += 1) {
        if (std.mem.indexOf(u8, tokens[i], "=")) |eq| {
            const k = tokens[i][0..eq];
            const v = tokens[i][eq + 1 ..];
            if (std.mem.eql(u8, k, "empty")) {
                empty = parsePct(v);
            } else {
                try keys.append(allocator, try dupeStr(allocator, k));
                try vals.append(allocator, parsePct(v));
            }
        }
    }

    visual.ray_grid = .{
        .resolution = res,
        .coverage_keys = try keys.toOwnedSlice(allocator),
        .coverage_vals = try vals.toOwnedSlice(allocator),
        .empty = empty,
    };
}

fn parseMview(rest: []const u8, views: *std.ArrayList(p.MultiViewData), allocator: Allocator) !void {
    // "front: Cube=20% Sphere=12%"
    const colon_idx = std.mem.indexOf(u8, rest, ":") orelse return;
    const view = try dupeStr(allocator, std.mem.trim(u8, rest[0..colon_idx], " "));
    const after = std.mem.trim(u8, rest[colon_idx + 1 ..], " ");

    const tokens = try tokenize(after, allocator);
    defer allocator.free(tokens);

    var keys: std.ArrayList([]const u8) = .empty;
    var vals: std.ArrayList(f32) = .empty;

    for (tokens) |t| {
        if (std.mem.indexOf(u8, t, "=")) |eq| {
            try keys.append(allocator, try dupeStr(allocator, t[0..eq]));
            try vals.append(allocator, parsePct(t[eq + 1 ..]));
        }
    }

    try views.append(allocator, .{
        .view = view,
        .coverage_keys = try keys.toOwnedSlice(allocator),
        .coverage_vals = try vals.toOwnedSlice(allocator),
    });
}

fn parseHier(rest: []const u8, entries: *std.ArrayList(p.HierarchyEntry), allocator: Allocator) !void {
    var chain: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitSequence(u8, rest, " > ");
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (trimmed.len > 0) {
            try chain.append(allocator, try dupeStr(allocator, trimmed));
        }
    }
    try entries.append(allocator, .{ .chain = try chain.toOwnedSlice(allocator) });
}

fn parseGrp(rest: []const u8, groups: *std.ArrayList(p.GroupEntry), allocator: Allocator) !void {
    const colon_idx = std.mem.indexOf(u8, rest, ":") orelse return;
    const name = try dupeStr(allocator, std.mem.trim(u8, rest[0..colon_idx], " "));
    const members_str = std.mem.trim(u8, rest[colon_idx + 1 ..], " ");
    const members = try splitComma(members_str, allocator);
    try groups.append(allocator, .{ .name = name, .members = members });
}

fn parseAnim(rest: []const u8, anims: *std.ArrayList(p.AnimationState), allocator: Allocator) !void {
    const tokens = try tokenize(rest, allocator);
    defer allocator.free(tokens);
    if (tokens.len < 1) return;

    const name = try dupeStr(allocator, tokens[0]);
    var action: []const u8 = try dupeStr(allocator, "");
    var frame: i32 = 0;
    var total: i32 = 0;
    var playing = false;

    var i: usize = 1;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (std.mem.startsWith(u8, t, "action=")) {
            allocator.free(action);
            action = try dupeStr(allocator, t[7..]);
        } else if (std.mem.startsWith(u8, t, "frame=")) {
            const ft = t[6..];
            if (std.mem.indexOf(u8, ft, "/")) |slash| {
                frame = std.fmt.parseInt(i32, ft[0..slash], 10) catch 0;
                total = std.fmt.parseInt(i32, ft[slash + 1 ..], 10) catch 0;
            }
        } else if (std.mem.eql(u8, t, "playing")) {
            playing = true;
        } else if (std.mem.eql(u8, t, "stopped")) {
            playing = false;
        }
    }

    try anims.append(allocator, .{
        .name = name,
        .action = action,
        .frame = frame,
        .total = total,
        .playing = playing,
    });
}

// ---------------------------------------------------------------------------
// Builder types (internal, used during parsing)
// ---------------------------------------------------------------------------

const VisualBuilder = struct {
    composition: ?p.CompositionData = null,
    ray_grid: ?p.RayGridData = null,
    multi_views: std.ArrayList(p.MultiViewData) = .empty,
};

const PhysicalBuilder = struct {
    world: ?p.WorldData = null,
    harmony: ?p.HarmonyData = null,
    palette: ?p.PaletteData = null,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse `.picacia` text into a `ScenePerception`.
/// All strings in the result are owned by `allocator`.
pub fn fromText(text: []const u8, allocator: Allocator) !p.ScenePerception {
    var cameras: std.ArrayList(p.CameraData) = .empty;
    var lights: std.ArrayList(p.LightData) = .empty;
    var objects: std.ArrayList(p.ObjectData) = .empty;
    var sgroups: std.ArrayList(p.SemanticGroupData) = .empty;
    var assemblies: std.ArrayList(p.AssemblyData) = .empty;
    var rels: std.ArrayList(p.RelationshipData) = .empty;
    var verify_list: std.ArrayList(p.VerifyResult) = .empty;
    var containment: std.ArrayList(p.ContainmentData) = .empty;
    var spatial_facts: std.ArrayList(p.SpatialFact) = .empty;
    var las: std.ArrayList(p.LightAnalysisData) = .empty;
    var sas: std.ArrayList(p.ShadowAnalysisData) = .empty;
    var mats: std.ArrayList(p.MaterialPrediction) = .empty;
    var physics: std.ArrayList(p.PhysicsState) = .empty;
    var contacts: std.ArrayList(p.ContactData) = .empty;
    var sounds: std.ArrayList(p.SoundData) = .empty;
    var hier: std.ArrayList(p.HierarchyEntry) = .empty;
    var groups: std.ArrayList(p.GroupEntry) = .empty;
    var anims: std.ArrayList(p.AnimationState) = .empty;
    var deltas: std.ArrayList([]const u8) = .empty;
    var visual_builder = VisualBuilder{};
    var physical_builder = PhysicalBuilder{};
    var scene_header: ?p.SceneHeader = null;

    var line_iter = std.mem.splitScalar(u8, text, '\n');
    while (line_iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        // Split into prefix and rest
        const space_idx = std.mem.indexOf(u8, line, " ");
        const prefix = if (space_idx) |si| line[0..si] else line;
        const rest = if (space_idx) |si| line[si + 1 ..] else "";

        if (std.mem.eql(u8, prefix, "SCENE")) {
            try parseScene(rest, &scene_header, allocator);
        } else if (std.mem.eql(u8, prefix, "CAM")) {
            try parseCam(rest, &cameras, allocator);
        } else if (std.mem.eql(u8, prefix, "LIGHT")) {
            try parseLight(rest, &lights, allocator);
        } else if (std.mem.eql(u8, prefix, "OBJ")) {
            try parseObj(rest, &objects, allocator);
        } else if (std.mem.eql(u8, prefix, "SGROUP")) {
            try parseSgroup(rest, &sgroups, allocator);
        } else if (std.mem.eql(u8, prefix, "ASSEMBLY")) {
            try parseAssembly(rest, &assemblies, allocator);
        } else if (std.mem.eql(u8, prefix, "REL")) {
            try parseRel(rest, &rels, allocator);
        } else if (std.mem.eql(u8, prefix, "VERIFY")) {
            try parseVerify(rest, &verify_list, allocator);
        } else if (std.mem.eql(u8, prefix, "CONTAIN")) {
            try parseContain(rest, &containment, allocator);
        } else if (std.mem.eql(u8, prefix, "SPATIAL")) {
            try parseSpatial(rest, &spatial_facts, allocator);
        } else if (std.mem.eql(u8, prefix, "LIT")) {
            try parseLit(rest, &las, allocator);
        } else if (std.mem.eql(u8, prefix, "SHAD")) {
            try parseShad(rest, &sas, allocator);
        } else if (std.mem.eql(u8, prefix, "MAT")) {
            try parseMat(rest, &mats, allocator);
        } else if (std.mem.eql(u8, prefix, "HARMONY")) {
            try parseHarmony(rest, &physical_builder.harmony, allocator);
        } else if (std.mem.eql(u8, prefix, "PALETTE")) {
            try parsePalette(rest, &physical_builder.palette, allocator);
        } else if (std.mem.eql(u8, prefix, "WORLD")) {
            parseWorld(rest, &physical_builder);
        } else if (std.mem.eql(u8, prefix, "PHYS")) {
            try parsePhys(rest, &physics, allocator);
        } else if (std.mem.eql(u8, prefix, "CONTACT")) {
            try parseContact(rest, &contacts, allocator);
        } else if (std.mem.eql(u8, prefix, "SND")) {
            try parseSnd(rest, &sounds, allocator);
        } else if (std.mem.eql(u8, prefix, "COMP")) {
            try parseComp(rest, &visual_builder, allocator);
        } else if (std.mem.eql(u8, prefix, "RAY")) {
            try parseRay(rest, &visual_builder, allocator);
        } else if (std.mem.eql(u8, prefix, "MVIEW")) {
            try parseMview(rest, &visual_builder.multi_views, allocator);
        } else if (std.mem.eql(u8, prefix, "HIER")) {
            try parseHier(rest, &hier, allocator);
        } else if (std.mem.eql(u8, prefix, "GRP")) {
            try parseGrp(rest, &groups, allocator);
        } else if (std.mem.eql(u8, prefix, "ANIM")) {
            try parseAnim(rest, &anims, allocator);
        } else if (std.mem.eql(u8, prefix, "DELTA")) {
            try deltas.append(allocator, try dupeStr(allocator, rest));
        }
        // Unknown prefixes silently ignored (forward compat)
    }

    // Set viewpoint from first camera if available
    var viewpoint: []const u8 = try dupeStr(allocator, "Camera");
    var viewpoint_position = p.Vec3{};
    if (cameras.items.len > 0) {
        allocator.free(viewpoint);
        viewpoint = try dupeStr(allocator, cameras.items[0].name);
        viewpoint_position = cameras.items[0].position;
    }

    return .{
        .viewpoint = viewpoint,
        .viewpoint_position = viewpoint_position,
        .viewpoint_forward = .{ .x = 0, .y = 0, .z = -1 },
        .identity = .{
            .scene_header = scene_header,
            .cameras = try cameras.toOwnedSlice(allocator),
            .lights = try lights.toOwnedSlice(allocator),
            .objects = try objects.toOwnedSlice(allocator),
            .semantic_groups = try sgroups.toOwnedSlice(allocator),
            .assemblies = try assemblies.toOwnedSlice(allocator),
        },
        .spatial = .{
            .relationships = try rels.toOwnedSlice(allocator),
            .verify = try verify_list.toOwnedSlice(allocator),
            .containment = try containment.toOwnedSlice(allocator),
            .spatial_facts = try spatial_facts.toOwnedSlice(allocator),
        },
        .visual = .{
            .composition = visual_builder.composition,
            .ray_grid = visual_builder.ray_grid,
            .multi_views = try visual_builder.multi_views.toOwnedSlice(allocator),
        },
        .physical = .{
            .light_analyses = try las.toOwnedSlice(allocator),
            .shadow_analyses = try sas.toOwnedSlice(allocator),
            .materials = try mats.toOwnedSlice(allocator),
            .harmony = physical_builder.harmony,
            .palette = physical_builder.palette,
            .world = physical_builder.world,
            .physics_states = try physics.toOwnedSlice(allocator),
            .contacts = try contacts.toOwnedSlice(allocator),
            .sounds = try sounds.toOwnedSlice(allocator),
        },
        .semantic = .{
            .hierarchy = try hier.toOwnedSlice(allocator),
            .groups = try groups.toOwnedSlice(allocator),
        },
        .temporal = .{
            .animations = try anims.toOwnedSlice(allocator),
            .deltas = try deltas.toOwnedSlice(allocator),
        },
    };
}
