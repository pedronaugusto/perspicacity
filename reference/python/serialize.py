"""Perspicacity v1 — Text DSL serializer and parser.

to_text(perception) -> str    Converts ScenePerception to .picacia text.
from_text(text) -> ScenePerception    Parses .picacia text to ScenePerception.

Zero dependencies beyond perception.py.
"""
from __future__ import annotations

from typing import Dict, List, Optional, Tuple

from perception import (
    AnimationState,
    AssemblyData,
    CameraData,
    CompositionData,
    ContactData,
    ContainmentData,
    FocusData,
    GroupEntry,
    HarmonyData,
    HierarchyEntry,
    IdentityTier,
    LightAnalysisData,
    LightData,
    MaterialPrediction,
    MultiViewData,
    ObjectData,
    PaletteData,
    PhysicalTier,
    PhysicsState,
    RayGridData,
    RelationshipData,
    SceneHeader,
    ScenePerception,
    SemanticGroupData,
    SemanticTier,
    ShadowAnalysisData,
    SoundData,
    SpatialFact,
    SpatialTier,
    TemporalTier,
    Vec3,
    VerifyResult,
    VisualTier,
    WorldData,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _fmt_float(v: float) -> str:
    """Format a float with minimal representation.

    Integers become '0', '5', '500'. Fractional values keep the minimum
    number of decimal places needed: '0.85', '5.4', '0.05'.
    """
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    # Use enough precision, strip trailing zeros
    s = f"{v:.10f}".rstrip("0").rstrip(".")
    return s


def _fmt_vec3(v: Vec3) -> str:
    return f"[{_fmt_float(v.x)},{_fmt_float(v.y)},{_fmt_float(v.z)}]"


def _fmt_pct(v: float) -> str:
    if v == int(v):
        return f"{int(v)}%"
    return f"{_fmt_float(v)}%"


def _parse_vec3(s: str) -> Vec3:
    """Parse '[x,y,z]' into Vec3."""
    s = s.strip("[] ")
    parts = s.split(",")
    return Vec3(float(parts[0]), float(parts[1]), float(parts[2]))


def _parse_pct(s: str) -> float:
    """Parse 'N%' into float."""
    return float(s.rstrip("%"))


def _parse_dist(s: str) -> float:
    """Parse 'Nm' into float."""
    return float(s.rstrip("m"))


def _split_arrow(s: str) -> Tuple[str, str]:
    """Split 'A->B' or 'A→B' into (A, B)."""
    for arrow in ("->", "\u2192"):
        if arrow in s:
            parts = s.split(arrow, 1)
            return parts[0], parts[1]
    raise ValueError(f"No arrow found in: {s}")


def _find_vec3_token(tokens: List[str], start: int) -> Tuple[str, int]:
    """Find a complete Vec3 token starting at index start.

    Vec3 may be split across tokens if it contains spaces (shouldn't normally,
    but handle gracefully). Returns (vec3_string, next_index).
    """
    combined = tokens[start]
    idx = start
    while combined.count("[") > combined.count("]"):
        idx += 1
        if idx >= len(tokens):
            break
        combined += "," + tokens[idx]
    return combined, idx + 1


# ---------------------------------------------------------------------------
# Serializer: struct -> text
# ---------------------------------------------------------------------------

def to_text(p: ScenePerception) -> str:
    """Convert a ScenePerception struct to .picacia text."""
    lines: List[str] = []

    # Header
    lines.append("# Perspicacity v1")

    # SCENE header
    if p.identity.scene_header is not None:
        sh = p.identity.scene_header
        s = f"SCENE {sh.obj_count} objects {sh.light_count} lights {_fmt_float(sh.energy)}W {sh.engine}"
        if sh.ground_z is not None:
            s += f" ground_z={_fmt_float(sh.ground_z)}"
        lines.append(s)

    # Focus (proximity-based perception)
    if p.focus is not None:
        f = p.focus
        lines.append(
            f"FOCUS {_fmt_vec3(f.position)} radius={_fmt_float(f.radius)}m "
            f"near={f.near} mid={f.mid} far={f.far} out={f.out}"
        )

    # Tier 0 — Identity
    for cam in p.identity.cameras:
        lines.append(f"CAM {cam.name} {_fmt_vec3(cam.position)} {_fmt_float(cam.focal_mm)}mm")

    for light in p.identity.lights:
        lines.append(
            f"LIGHT {light.name} {light.type} {_fmt_float(light.energy_w)}W "
            f"{_fmt_vec3(light.color)} {_fmt_vec3(light.position)}"
        )

    for obj in p.identity.objects:
        parts = [
            "OBJ",
            obj.name,
            _fmt_vec3(obj.position),
            _fmt_pct(obj.coverage),
            obj.quadrant,
            f"d={_fmt_float(obj.depth)}m",
            obj.material,
        ]
        if obj.dimensions is not None:
            parts.append(f"dim={_fmt_vec3(obj.dimensions)}")
        if obj.top_z is not None:
            parts.append(f"top={_fmt_float(obj.top_z)}")
        if obj.source is not None:
            parts.append(f"src={obj.source}")
        if obj.rotation is not None:
            parts.append(f"rot={_fmt_vec3(obj.rotation)}")
        if obj.facing is not None:
            parts.append(f"facing={obj.facing}")
        if obj.zone is not None:
            parts.append(f"zone={obj.zone}")
        if obj.face is not None:
            parts.append(f"face={obj.face}")
        if obj.lum is not None:
            parts.append(f"lum={_fmt_float(obj.lum)}")
        if obj.transparent:
            parts.append("transparent")
        if obj.has_uv is True:
            parts.append("has_uv")
        elif obj.has_uv is False:
            parts.append("no_uv")
        if obj.flipped_normals_pct is not None:
            parts.append(f"flipped_normals={_fmt_pct(obj.flipped_normals_pct)}")
        if obj.non_manifold_edges is not None:
            parts.append(f"non_manifold={obj.non_manifold_edges}")
        if obj.inside is not None:
            parts.append(f"inside={obj.inside}")
        if obj.contains:
            parts.append(f"contains:[{','.join(obj.contains)}]")
        lines.append(" ".join(parts))

    # SGROUP lines
    for sg in p.identity.semantic_groups:
        parts = [
            "SGROUP",
            f'"{sg.name}"',
            _fmt_vec3(sg.position),
            f"dim={_fmt_vec3(sg.dimensions)}",
            f"top={_fmt_float(sg.top_z)}",
            sg.material,
        ]
        if sg.facing is not None:
            parts.append(f"facing={sg.facing}")
        parts.append(f"members={sg.member_count}")
        lines.append(" ".join(parts))

    # ASSEMBLY lines
    for asm in p.identity.assemblies:
        members_str = ",".join(asm.members)
        lines.append(
            f'ASSEMBLY "{asm.name}" members=[{members_str}] '
            f"center={_fmt_vec3(asm.center)} types={asm.types}"
        )

    # Tier 1 — Spatial
    for rel in p.spatial.relationships:
        parts = [
            "REL",
            f"{rel.from_obj}->{rel.to_obj}",
            f"{_fmt_float(rel.distance)}m",
            rel.direction,
        ]
        if rel.vertical:
            parts.append(rel.vertical)
        if rel.overlap:
            if rel.overlap_pct is not None:
                parts.append(f"overlap={_fmt_pct(rel.overlap_pct)}")
            else:
                parts.append("overlap")
        if rel.aabb_overlap_pct is not None:
            parts.append(f"aabb_overlap={_fmt_pct(rel.aabb_overlap_pct)}")
        if rel.contact:
            parts.append("contact")
        if rel.occludes:
            parts.append("occludes")
        if rel.occ_pct is not None:
            parts.append(f"occ={_fmt_pct(rel.occ_pct)}")
        lines.append(" ".join(parts))

    # VERIFY (only on failure)
    for v in p.spatial.verify:
        lines.append(f"VERIFY FAIL {v.object} {v.message}")

    # Containment (Tier 1 — Spatial)
    for ct in p.spatial.containment:
        lines.append(f"CONTAIN {ct.outer} contains {ct.inner} {ct.mode}")

    # SPATIAL facts (Tier 1 — Spatial)
    for sf in p.spatial.spatial_facts:
        parts = ["SPATIAL", sf.object, sf.type]
        for k, v in sf.details.items():
            if isinstance(v, bool):
                parts.append(f"{k}={'true' if v else 'false'}")
            elif isinstance(v, Vec3):
                parts.append(f"{k}={_fmt_vec3(v)}")
            else:
                parts.append(f"{k}={v}")
        lines.append(" ".join(parts))

    # Tier 3 — Physical (LIT, SHAD, MAT, HARMONY, PALETTE, WORLD before Tier 2 per ordering)
    for la in p.physical.light_analyses:
        parts = [
            "LIT",
            f"{la.light}->{la.surface}",
            f"@{_fmt_float(la.angle)}\u00b0",
            f"i={_fmt_float(la.intensity)}",
        ]
        if la.effective is not None:
            parts.append(f"eff={_fmt_float(la.effective)}")
        if la.raw_intensity is not None:
            parts.append(f"raw={_fmt_float(la.raw_intensity)}")
        if la.shadow:
            parts.append(f"shadow:{','.join(la.shadow)}")
        lines.append(" ".join(parts))

    for sa in p.physical.shadow_analyses:
        parts = [
            "SHAD",
            f"{sa.light}->{sa.surface}",
            _fmt_pct(sa.coverage),
        ]
        if sa.casters:
            parts.append(f"casters:{','.join(sa.casters)}")
        if sa.contact:
            parts.append("contact")
        if sa.gap is not None:
            parts.append(f"gap={_fmt_float(sa.gap)}m")
        lines.append(" ".join(parts))

    for mat in p.physical.materials:
        s = f"MAT {mat.name}: {mat.appearance}"
        if mat.needs:
            s += f" -- needs {mat.needs}"
        elif mat.warning:
            s += f" -- {mat.warning}"
        lines.append(s)

    # HARMONY
    if p.physical.harmony is not None:
        h = p.physical.harmony
        lines.append(f"HARMONY types={h.types} temp={h.temperature}")

    # PALETTE
    if p.physical.palette is not None:
        pal = p.physical.palette
        parts = ["PALETTE"]
        if pal.luminance is not None:
            parts.append(f"lum={_fmt_float(pal.luminance)}")
        parts.extend(pal.palette)
        lines.append(" ".join(parts))

    if p.physical.world is not None:
        w = p.physical.world
        if w.hdri:
            lines.append(f"WORLD hdri strength={_fmt_float(w.strength)}")
        elif w.bg_color is not None:
            lines.append(f"WORLD bg={_fmt_vec3(w.bg_color)} strength={_fmt_float(w.strength)}")

    for ps in p.physical.physics_states:
        parts = [
            "PHYS",
            ps.name,
            ps.type,
            f"mass={_fmt_float(ps.mass_kg)}kg",
        ]
        if ps.velocity is not None:
            parts.append(f"vel={_fmt_vec3(ps.velocity)}")
        if ps.sleeping:
            parts.append("sleeping")
        lines.append(" ".join(parts))

    for ct in p.physical.contacts:
        lines.append(
            f"CONTACT {ct.obj_a}<>{ct.obj_b} normal={_fmt_vec3(ct.normal)} "
            f"force={_fmt_float(ct.force_n)}N surface={ct.surface}"
        )

    for snd in p.physical.sounds:
        lines.append(
            f"SND {snd.source} type={snd.type} vol={_fmt_float(snd.volume)} "
            f"dist={_fmt_float(snd.distance)}m dir={snd.direction} occ={_fmt_float(snd.occlusion)}"
        )

    # Tier 2 — Visual
    if p.visual.composition is not None:
        c = p.visual.composition
        parts = [
            "COMP",
            f"thirds={_fmt_float(c.thirds)}",
            f"{c.visible}/{c.total}_visible",
            f"balance={_fmt_float(c.balance)}",
            f"depth={c.depth}",
        ]
        if c.edge:
            parts.append(f"edge:[{','.join(c.edge)}]")
        lines.append(" ".join(parts))

    if p.visual.ray_grid is not None:
        rg = p.visual.ray_grid
        parts = [f"RAY {rg.resolution}x{rg.resolution}"]
        for name, cov in rg.coverage.items():
            parts.append(f"{name}={_fmt_pct(cov)}")
        if rg.empty > 0:
            parts.append(f"empty={_fmt_pct(rg.empty)}")
        lines.append(" ".join(parts))

    for mv in p.visual.multi_views:
        cov_parts = [f"{name}={_fmt_pct(cov)}" for name, cov in mv.coverage.items()]
        lines.append(f"MVIEW {mv.view}: {' '.join(cov_parts)}")

    # Tier 4 — Semantic
    for h in p.semantic.hierarchy:
        lines.append(f"HIER {' > '.join(h.chain)}")

    for g in p.semantic.groups:
        lines.append(f"GRP {g.name}: {', '.join(g.members)}")

    # Tier 5 — Temporal
    for a in p.temporal.animations:
        state = "playing" if a.playing else "stopped"
        lines.append(f"ANIM {a.name} action={a.action} frame={a.frame}/{a.total} {state}")
    for d in p.temporal.deltas:
        lines.append(f"DELTA {d}")

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Parser: text -> struct
# ---------------------------------------------------------------------------

def from_text(text: str) -> ScenePerception:
    """Parse .picacia text into a ScenePerception struct."""
    p = ScenePerception(
        identity=IdentityTier(),
        spatial=SpatialTier(),
        visual=VisualTier(multi_views=[]),
        physical=PhysicalTier(),
        semantic=SemanticTier(),
        temporal=TemporalTier(),
    )

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        # Split into prefix and rest
        space_idx = line.find(" ")
        if space_idx == -1:
            prefix = line
            rest = ""
        else:
            prefix = line[:space_idx]
            rest = line[space_idx + 1:]

        if prefix == "SCENE":
            _parse_scene(rest, p)
        elif prefix == "FOCUS":
            _parse_focus(rest, p)
        elif prefix == "CAM":
            _parse_cam(rest, p)
        elif prefix == "LIGHT":
            _parse_light(rest, p)
        elif prefix == "OBJ":
            _parse_obj(rest, p)
        elif prefix == "SGROUP":
            _parse_sgroup(rest, p)
        elif prefix == "ASSEMBLY":
            _parse_assembly(rest, p)
        elif prefix == "REL":
            _parse_rel(rest, p)
        elif prefix == "VERIFY":
            _parse_verify(rest, p)
        elif prefix == "CONTAIN":
            _parse_contain(rest, p)
        elif prefix == "SPATIAL":
            _parse_spatial(rest, p)
        elif prefix == "LIT":
            _parse_lit(rest, p)
        elif prefix == "SHAD":
            _parse_shad(rest, p)
        elif prefix == "MAT":
            _parse_mat(rest, p)
        elif prefix == "HARMONY":
            _parse_harmony(rest, p)
        elif prefix == "PALETTE":
            _parse_palette(rest, p)
        elif prefix == "WORLD":
            _parse_world(rest, p)
        elif prefix == "PHYS":
            _parse_phys(rest, p)
        elif prefix == "CONTACT":
            _parse_contact(rest, p)
        elif prefix == "SND":
            _parse_snd(rest, p)
        elif prefix == "COMP":
            _parse_comp(rest, p)
        elif prefix == "RAY":
            _parse_ray(rest, p)
        elif prefix == "MVIEW":
            _parse_mview(rest, p)
        elif prefix == "HIER":
            _parse_hier(rest, p)
        elif prefix == "GRP":
            _parse_grp(rest, p)
        elif prefix == "ANIM":
            _parse_anim(rest, p)
        elif prefix == "DELTA":
            p.temporal.deltas.append(rest)

    # Set viewpoint from first camera if available
    if p.identity.cameras:
        cam = p.identity.cameras[0]
        p.viewpoint = cam.name
        p.viewpoint_position = Vec3(cam.position.x, cam.position.y, cam.position.z)
        # Default forward is -Z (looking into screen)
        p.viewpoint_forward = Vec3(0, 0, -1)

    return p


def _parse_scene(rest: str, p: ScenePerception) -> None:
    """Parse 'N objects N lights NW ENGINE [ground_z=N]'."""
    tokens = rest.split()
    if len(tokens) < 5:
        return
    obj_count = int(tokens[0])
    light_count = int(tokens[2])
    energy_str = tokens[4].rstrip("W")
    energy = float(energy_str)
    engine = tokens[5] if len(tokens) > 5 else ""
    ground_z = None
    for t in tokens[6:]:
        if t.startswith("ground_z="):
            ground_z = float(t.split("=", 1)[1])
    p.identity.scene_header = SceneHeader(
        obj_count=obj_count, light_count=light_count,
        energy=energy, engine=engine, ground_z=ground_z,
    )


def _parse_cam(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    name = tokens[0]
    vec3_str, next_idx = _find_vec3_token(tokens, 1)
    focal_str = tokens[next_idx]  # e.g. "50mm"
    focal = float(focal_str.rstrip("mm"))
    cam = CameraData(name=name, position=_parse_vec3(vec3_str), focal_mm=focal)
    p.identity.cameras.append(cam)


def _parse_light(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    name = tokens[0]
    ltype = tokens[1]
    energy = float(tokens[2].rstrip("W"))
    color_str, next_idx = _find_vec3_token(tokens, 3)
    pos_str, _ = _find_vec3_token(tokens, next_idx)
    light = LightData(
        name=name, type=ltype, energy_w=energy,
        color=_parse_vec3(color_str), position=_parse_vec3(pos_str),
    )
    p.identity.lights.append(light)


def _parse_obj(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    name = tokens[0]
    pos_str, next_idx = _find_vec3_token(tokens, 1)
    coverage = _parse_pct(tokens[next_idx])
    quadrant = tokens[next_idx + 1]
    depth_str = tokens[next_idx + 2]  # d=5.0m
    depth = float(depth_str.split("=")[1].rstrip("m"))
    material = tokens[next_idx + 3]

    face: Optional[str] = None
    lum: Optional[float] = None
    inside: Optional[str] = None
    contains: List[str] = []
    dimensions: Optional[Vec3] = None
    top_z: Optional[float] = None
    source: Optional[str] = None
    rotation: Optional[Vec3] = None
    facing_dir: Optional[str] = None
    zone: Optional[str] = None
    transparent = False
    has_uv: Optional[bool] = None
    flipped_normals_pct: Optional[float] = None
    non_manifold_edges: Optional[int] = None

    i = next_idx + 4
    while i < len(tokens):
        t = tokens[i]
        if t.startswith("dim="):
            dim_str, i = _find_vec3_token(tokens, i)
            dim_str = dim_str.split("=", 1)[1]
            dimensions = _parse_vec3(dim_str)
            continue
        elif t.startswith("top="):
            top_z = float(t.split("=", 1)[1])
        elif t.startswith("src="):
            source = t.split("=", 1)[1].strip('"')
        elif t.startswith("rot="):
            rot_str, i = _find_vec3_token(tokens, i)
            rot_str = rot_str.split("=", 1)[1]
            rotation = _parse_vec3(rot_str)
            continue
        elif t.startswith("facing="):
            facing_dir = t.split("=", 1)[1]
        elif t.startswith("zone="):
            zone = t.split("=", 1)[1]
        elif t.startswith("face="):
            face = t.split("=", 1)[1]
        elif t.startswith("lum="):
            lum = float(t.split("=", 1)[1])
        elif t == "transparent":
            transparent = True
        elif t == "has_uv":
            has_uv = True
        elif t == "no_uv":
            has_uv = False
        elif t.startswith("flipped_normals="):
            flipped_normals_pct = _parse_pct(t.split("=", 1)[1])
        elif t.startswith("non_manifold="):
            non_manifold_edges = int(t.split("=", 1)[1])
        elif t.startswith("inside="):
            inside = t.split("=", 1)[1]
        elif t.startswith("contains:["):
            contains_str = t[len("contains:["):-1]
            contains = contains_str.split(",") if contains_str else []
        i += 1

    obj = ObjectData(
        name=name, position=_parse_vec3(pos_str), coverage=coverage,
        quadrant=quadrant, depth=depth, material=material,
        dimensions=dimensions, top_z=top_z, source=source,
        rotation=rotation, facing=facing_dir, zone=zone,
        face=face, lum=lum, transparent=transparent,
        has_uv=has_uv, flipped_normals_pct=flipped_normals_pct,
        non_manifold_edges=non_manifold_edges,
        inside=inside, contains=contains,
    )
    p.identity.objects.append(obj)


def _parse_sgroup(rest: str, p: ScenePerception) -> None:
    """Parse '"name" [x,y,z] dim=[w,h,d] top=N material [facing=DIR] members=N'."""
    # Extract quoted name
    if rest.startswith('"'):
        end_quote = rest.index('"', 1)
        name = rest[1:end_quote]
        rest = rest[end_quote + 1:].strip()
    else:
        tokens = rest.split(None, 1)
        name = tokens[0]
        rest = tokens[1] if len(tokens) > 1 else ""

    tokens = rest.split()
    pos_str, next_idx = _find_vec3_token(tokens, 0)
    position = _parse_vec3(pos_str)

    dimensions = Vec3()
    top_z = 0.0
    material = ""
    facing = None
    member_count = 0

    i = next_idx
    while i < len(tokens):
        t = tokens[i]
        if t.startswith("dim="):
            dim_str, i = _find_vec3_token(tokens, i)
            dim_str = dim_str.split("=", 1)[1]
            dimensions = _parse_vec3(dim_str)
            continue
        elif t.startswith("top="):
            top_z = float(t.split("=", 1)[1])
        elif t.startswith("facing="):
            facing = t.split("=", 1)[1]
        elif t.startswith("members="):
            member_count = int(t.split("=", 1)[1])
        else:
            # Must be material
            material = t
        i += 1

    p.identity.semantic_groups.append(SemanticGroupData(
        name=name, position=position, dimensions=dimensions,
        top_z=top_z, material=material, facing=facing,
        member_count=member_count,
    ))


def _parse_assembly(rest: str, p: ScenePerception) -> None:
    """Parse '"name" members=[A,B,C] center=[x,y,z] types=X+Y'."""
    # Extract quoted name
    if rest.startswith('"'):
        end_quote = rest.index('"', 1)
        name = rest[1:end_quote]
        rest = rest[end_quote + 1:].strip()
    else:
        tokens = rest.split(None, 1)
        name = tokens[0]
        rest = tokens[1] if len(tokens) > 1 else ""

    members: List[str] = []
    center = Vec3()
    types = ""

    tokens = rest.split()
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t.startswith("members=["):
            members_str = t[len("members=["):]
            # Collect until we find closing bracket
            while "]" not in members_str and i + 1 < len(tokens):
                i += 1
                members_str += "," + tokens[i]
            members_str = members_str.rstrip("]")
            members = [m.strip() for m in members_str.split(",") if m.strip()]
        elif t.startswith("center="):
            center_str, i = _find_vec3_token(tokens, i)
            center_str = center_str.split("=", 1)[1]
            center = _parse_vec3(center_str)
            continue
        elif t.startswith("types="):
            types = t.split("=", 1)[1]
        i += 1

    p.identity.assemblies.append(AssemblyData(
        name=name, members=members, center=center, types=types,
    ))


def _parse_rel(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    from_obj, to_obj = _split_arrow(tokens[0])
    distance = _parse_dist(tokens[1])
    direction = tokens[2]

    vertical: Optional[str] = None
    overlap = False
    overlap_pct: Optional[float] = None
    aabb_overlap_pct: Optional[float] = None
    contact = False
    occludes = False
    occ_pct: Optional[float] = None

    for i in range(3, len(tokens)):
        t = tokens[i]
        if t in ("same_level", "above", "below"):
            vertical = t
        elif t.startswith("overlap="):
            overlap = True
            overlap_pct = _parse_pct(t.split("=", 1)[1])
        elif t == "overlap":
            overlap = True
        elif t.startswith("aabb_overlap="):
            aabb_overlap_pct = _parse_pct(t.split("=", 1)[1])
        elif t == "contact":
            contact = True
        elif t == "occludes":
            occludes = True
        elif t.startswith("occ="):
            occ_pct = _parse_pct(t.split("=", 1)[1])

    rel = RelationshipData(
        from_obj=from_obj, to_obj=to_obj, distance=distance,
        direction=direction, vertical=vertical, overlap=overlap,
        overlap_pct=overlap_pct, aabb_overlap_pct=aabb_overlap_pct,
        contact=contact, occludes=occludes, occ_pct=occ_pct,
    )
    p.spatial.relationships.append(rel)


def _parse_verify(rest: str, p: ScenePerception) -> None:
    """Parse 'FAIL ObjName reason text'."""
    tokens = rest.split(None, 2)
    if len(tokens) < 3:
        return
    # tokens[0] is always "FAIL"
    p.spatial.verify.append(VerifyResult(
        object=tokens[1], message=tokens[2],
    ))


def _parse_contain(rest: str, p: ScenePerception) -> None:
    parts = rest.split(" contains ", 1)
    outer = parts[0].strip()
    remainder = parts[1].strip().rsplit(" ", 1)
    inner = remainder[0].strip()
    mode = remainder[1].strip() if len(remainder) > 1 else "full"
    p.spatial.containment.append(ContainmentData(outer=outer, inner=inner, mode=mode))


def _parse_spatial(rest: str, p: ScenePerception) -> None:
    """Parse 'ObjName fact_type key=value key=value ...'."""
    tokens = rest.split()
    if len(tokens) < 2:
        return
    obj_name = tokens[0]
    fact_type = tokens[1]
    details = {}
    for t in tokens[2:]:
        if "=" in t:
            k, v = t.split("=", 1)
            # Try to parse as number, bool, or leave as string
            if v == "true":
                details[k] = True
            elif v == "false":
                details[k] = False
            elif v.startswith("["):
                # Vec3 — store as string for now
                details[k] = v
            else:
                try:
                    if "." in v:
                        details[k] = float(v)
                    else:
                        details[k] = int(v)
                except ValueError:
                    details[k] = v
    p.spatial.spatial_facts.append(SpatialFact(
        object=obj_name, type=fact_type, details=details,
    ))


def _parse_lit(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    light, surface = _split_arrow(tokens[0])
    angle = float(tokens[1].lstrip("@").rstrip("\u00b0"))
    intensity = float(tokens[2].split("=")[1])

    shadow: List[str] = []
    effective: Optional[float] = None
    raw_intensity: Optional[float] = None
    for i in range(3, len(tokens)):
        t = tokens[i]
        if t.startswith("shadow:"):
            shadow = t.split(":", 1)[1].split(",")
        elif t.startswith("eff="):
            effective = float(t.split("=", 1)[1])
        elif t.startswith("raw="):
            raw_intensity = float(t.split("=", 1)[1])

    la = LightAnalysisData(
        light=light, surface=surface, angle=angle,
        intensity=intensity, effective=effective,
        raw_intensity=raw_intensity, shadow=shadow,
    )
    p.physical.light_analyses.append(la)


def _parse_shad(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    light, surface = _split_arrow(tokens[0])
    coverage = _parse_pct(tokens[1])

    casters: List[str] = []
    contact = False
    gap: Optional[float] = None

    for i in range(2, len(tokens)):
        t = tokens[i]
        if t.startswith("casters:"):
            casters = t.split(":", 1)[1].split(",")
        elif t == "contact":
            contact = True
        elif t.startswith("gap="):
            gap = _parse_dist(t.split("=", 1)[1])

    sa = ShadowAnalysisData(
        light=light, surface=surface, coverage=coverage,
        casters=casters, contact=contact, gap=gap,
    )
    p.physical.shadow_analyses.append(sa)


def _parse_mat(rest: str, p: ScenePerception) -> None:
    # rest is "name: appearance [-- notes]"
    colon_idx = rest.find(": ")
    if colon_idx == -1:
        return
    name = rest[:colon_idx]
    after = rest[colon_idx + 2:]

    needs: Optional[str] = None
    warning: Optional[str] = None

    if " -- " in after:
        parts = after.split(" -- ", 1)
        appearance = parts[0]
        note = parts[1].strip()
        if note.startswith("needs "):
            needs = note[len("needs "):]
        elif note:
            warning = note
    else:
        appearance = after

    mat = MaterialPrediction(
        name=name, appearance=appearance, needs=needs,
        warning=warning,
    )
    p.physical.materials.append(mat)


def _parse_harmony(rest: str, p: ScenePerception) -> None:
    """Parse 'types=X+Y temp=Z'."""
    types = ""
    temperature = ""
    for t in rest.split():
        if t.startswith("types="):
            types = t.split("=", 1)[1]
        elif t.startswith("temp="):
            temperature = t.split("=", 1)[1]
    p.physical.harmony = HarmonyData(types=types, temperature=temperature)


def _parse_palette(rest: str, p: ScenePerception) -> None:
    """Parse '[lum=N] color1 color2 ...'."""
    tokens = rest.split()
    luminance = None
    colors = []
    for t in tokens:
        if t.startswith("lum="):
            luminance = float(t.split("=", 1)[1])
        else:
            colors.append(t)
    p.physical.palette = PaletteData(luminance=luminance, palette=colors)


def _parse_world(rest: str, p: ScenePerception) -> None:
    if rest.startswith("hdri"):
        tokens = rest.split()
        strength = float(tokens[1].split("=")[1])
        p.physical.world = WorldData(hdri=True, strength=strength)
    elif rest.startswith("bg="):
        bracket_end = rest.index("]") + 1
        bg_str = rest[3:bracket_end]
        remaining = rest[bracket_end:].strip()
        strength = float(remaining.split("=")[1])
        p.physical.world = WorldData(
            bg_color=_parse_vec3(bg_str), strength=strength,
        )


def _parse_phys(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    name = tokens[0]
    ptype = tokens[1]
    mass = float(tokens[2].split("=")[1].rstrip("kg"))

    velocity: Optional[Vec3] = None
    sleeping = False

    i = 3
    while i < len(tokens):
        t = tokens[i]
        if t.startswith("vel="):
            vec_str = t.split("=", 1)[1]
            # May need to collect more tokens if split
            while vec_str.count("[") > vec_str.count("]") and i + 1 < len(tokens):
                i += 1
                vec_str += "," + tokens[i]
            velocity = _parse_vec3(vec_str)
        elif t == "sleeping":
            sleeping = True
        i += 1

    ps = PhysicsState(
        name=name, type=ptype, mass_kg=mass,
        velocity=velocity, sleeping=sleeping,
    )
    p.physical.physics_states.append(ps)


def _parse_contact(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    # A<>B
    ab = tokens[0].split("<>")
    obj_a = ab[0]
    obj_b = ab[1]

    # normal=[x,y,z]
    normal_str = tokens[1].split("=", 1)[1]
    idx = 2
    while normal_str.count("[") > normal_str.count("]") and idx < len(tokens):
        normal_str += "," + tokens[idx]
        idx += 1

    # force=XN
    force = float(tokens[idx].split("=")[1].rstrip("N"))
    idx += 1

    # surface=material
    surface = tokens[idx].split("=")[1]

    ct = ContactData(
        obj_a=obj_a, obj_b=obj_b, normal=_parse_vec3(normal_str),
        force_n=force, surface=surface,
    )
    p.physical.contacts.append(ct)


def _parse_snd(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    source = tokens[0]
    stype = ""
    volume = 0.0
    distance = 0.0
    direction = ""
    occlusion = 0.0

    for t in tokens[1:]:
        if t.startswith("type="):
            stype = t.split("=")[1]
        elif t.startswith("vol="):
            volume = float(t.split("=")[1])
        elif t.startswith("dist="):
            distance = _parse_dist(t.split("=")[1])
        elif t.startswith("dir="):
            direction = t.split("=")[1]
        elif t.startswith("occ="):
            occlusion = float(t.split("=")[1])

    snd = SoundData(
        source=source, type=stype, volume=volume,
        distance=distance, direction=direction, occlusion=occlusion,
    )
    p.physical.sounds.append(snd)


def _parse_comp(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    thirds = float(tokens[0].split("=")[1])
    # "3/3_visible"
    vis_str = tokens[1].replace("_visible", "")
    vis_parts = vis_str.split("/")
    visible = int(vis_parts[0])
    total = int(vis_parts[1])
    balance = float(tokens[2].split("=")[1])
    depth = tokens[3].split("=")[1]

    edge: List[str] = []
    for t in tokens[4:]:
        if t.startswith("edge:["):
            edge_str = t[len("edge:["):-1]
            edge = edge_str.split(",")

    comp = CompositionData(
        thirds=thirds, visible=visible, total=total,
        balance=balance, depth=depth, edge=edge,
    )
    p.visual.composition = comp


def _parse_ray(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    # "12x12"
    res = int(tokens[0].split("x")[0])
    coverage: Dict[str, float] = {}
    empty = 0.0

    for t in tokens[1:]:
        if "=" in t:
            k, v = t.split("=", 1)
            if k == "empty":
                empty = _parse_pct(v)
            else:
                coverage[k] = _parse_pct(v)

    rg = RayGridData(resolution=res, coverage=coverage, empty=empty)
    p.visual.ray_grid = rg


def _parse_mview(rest: str, p: ScenePerception) -> None:
    # "front: Cube=20% Sphere=12%"
    colon_idx = rest.find(":")
    view = rest[:colon_idx].strip()
    after = rest[colon_idx + 1:].strip()
    tokens = after.split()

    coverage: Dict[str, float] = {}
    for t in tokens:
        if "=" in t:
            k, v = t.split("=", 1)
            coverage[k] = _parse_pct(v)

    mv = MultiViewData(view=view, coverage=coverage)
    p.visual.multi_views.append(mv)


def _parse_hier(rest: str, p: ScenePerception) -> None:
    chain = [part.strip() for part in rest.split(" > ")]
    p.semantic.hierarchy.append(HierarchyEntry(chain=chain))


def _parse_grp(rest: str, p: ScenePerception) -> None:
    colon_idx = rest.find(":")
    name = rest[:colon_idx].strip()
    members_str = rest[colon_idx + 1:].strip()
    members = [m.strip() for m in members_str.split(",")]
    p.semantic.groups.append(GroupEntry(name=name, members=members))


def _parse_anim(rest: str, p: ScenePerception) -> None:
    tokens = rest.split()
    name = tokens[0]
    action = ""
    frame = 0
    total = 0
    playing = False

    for t in tokens[1:]:
        if t.startswith("action="):
            action = t.split("=")[1]
        elif t.startswith("frame="):
            ft = t.split("=")[1]
            parts = ft.split("/")
            frame = int(parts[0])
            total = int(parts[1])
        elif t == "playing":
            playing = True
        elif t == "stopped":
            playing = False

    anim = AnimationState(
        name=name, action=action, frame=frame,
        total=total, playing=playing,
    )
    p.temporal.animations.append(anim)


def _parse_focus(rest: str, p: ScenePerception) -> None:
    """Parse '[x,y,z] radius=Nm near=N mid=N far=N out=N'."""
    tokens = rest.split()
    pos_str, next_idx = _find_vec3_token(tokens, 0)
    pos = _parse_vec3(pos_str)
    radius = near = mid = far = out = 0
    for t in tokens[next_idx:]:
        if t.startswith("radius="):
            radius = float(t.split("=")[1].rstrip("m"))
        elif t.startswith("near="):
            near = int(t.split("=")[1])
        elif t.startswith("mid="):
            mid = int(t.split("=")[1])
        elif t.startswith("far="):
            far = int(t.split("=")[1])
        elif t.startswith("out="):
            out = int(t.split("=")[1])
    p.focus = FocusData(position=pos, radius=radius, near=near, mid=mid, far=far, out=out)
