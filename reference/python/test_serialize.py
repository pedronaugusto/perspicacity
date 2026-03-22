"""Perspicacity v1 — Round-trip serialization tests.

Run with: pytest test_serialize.py -v
"""
from __future__ import annotations

import sys
from pathlib import Path

# Ensure the reference python package is importable
sys.path.insert(0, str(Path(__file__).parent))

from perception import (
    AnimationState,
    AssemblyData,
    CameraData,
    CompositionData,
    ContactData,
    ContainmentData,
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
    SpatialTier,
    TemporalTier,
    Vec3,
    VerifyResult,
    VisualTier,
    WorldData,
)
from serialize import from_text, to_text

FIXTURES = Path(__file__).parent.parent.parent / "test-fixtures"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _normalize(text: str) -> str:
    """Normalize text for comparison: strip blank lines, normalize whitespace."""
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped:
            lines.append(stripped)
    return "\n".join(lines)


def _compare_lines(original: str, roundtripped: str) -> None:
    """Compare two .picacia texts line by line, ignoring comments and blank lines.

    We skip the header comment since to_text always writes '# Perspicacity v1'.
    """
    orig_lines = [l.strip() for l in original.splitlines() if l.strip() and not l.strip().startswith("#")]
    rt_lines = [l.strip() for l in roundtripped.splitlines() if l.strip() and not l.strip().startswith("#")]

    # Compare each line
    for i, (o, r) in enumerate(zip(orig_lines, rt_lines)):
        assert o == r, f"Line {i} differs:\n  orig: {o}\n  rt:   {r}"

    assert len(orig_lines) == len(rt_lines), (
        f"Line count differs: orig={len(orig_lines)} rt={len(rt_lines)}"
    )


# ---------------------------------------------------------------------------
# Round-trip tests
# ---------------------------------------------------------------------------

class TestMinimalFixture:
    """Round-trip tests on minimal.picacia."""

    def test_parse(self) -> None:
        text = (FIXTURES / "minimal.picacia").read_text()
        p = from_text(text)

        assert len(p.identity.cameras) == 1
        assert p.identity.cameras[0].name == "Camera"
        assert p.identity.cameras[0].focal_mm == 50.0

        assert len(p.identity.lights) == 1
        assert p.identity.lights[0].name == "Key"
        assert p.identity.lights[0].type == "POINT"
        assert p.identity.lights[0].energy_w == 500.0

        assert len(p.identity.objects) == 3
        assert p.identity.objects[0].name == "Cube"
        assert p.identity.objects[1].name == "Sphere"
        assert p.identity.objects[2].name == "Floor"
        assert p.identity.objects[0].coverage == 15.0
        assert p.identity.objects[0].depth == 5.0
        assert p.identity.objects[0].face == "+Z"
        assert p.identity.objects[2].face is None  # Floor has no face

        # New fields: dim=, rot=, facing=, has_uv/no_uv
        cube = p.identity.objects[0]
        assert cube.dimensions is not None
        assert cube.dimensions.x == 2.0
        assert cube.dimensions.y == 2.0
        assert cube.dimensions.z == 2.0
        assert cube.rotation is not None
        assert cube.rotation.z == 45.0
        assert cube.facing == "NE"
        assert cube.has_uv is True

        sphere = p.identity.objects[1]
        assert sphere.dimensions is not None
        assert sphere.dimensions.x == 1.0
        assert sphere.has_uv is True

        floor = p.identity.objects[2]
        assert floor.dimensions is not None
        assert floor.dimensions.x == 10.0
        assert floor.has_uv is False  # no_uv

        assert len(p.spatial.relationships) == 3
        assert p.spatial.relationships[0].from_obj == "Cube"
        assert p.spatial.relationships[0].to_obj == "Sphere"
        assert p.spatial.relationships[0].distance == 2.0
        assert p.spatial.relationships[0].direction == "left"
        assert p.spatial.relationships[0].vertical == "same_level"
        assert p.spatial.relationships[1].contact is True

        # SPATIAL facts
        assert len(p.spatial.spatial_facts) == 1
        assert p.spatial.spatial_facts[0].object == "Cube"
        assert p.spatial.spatial_facts[0].type == "scale_ratio"

        assert len(p.physical.light_analyses) == 3
        assert p.physical.light_analyses[0].angle == 42.0
        assert p.physical.light_analyses[0].intensity == 0.85

        assert len(p.physical.shadow_analyses) == 1
        assert p.physical.shadow_analyses[0].coverage == 12.0
        assert p.physical.shadow_analyses[0].casters == ["Cube", "Sphere"]
        assert p.physical.shadow_analyses[0].contact is True

        assert len(p.physical.materials) == 3
        assert p.physical.materials[1].needs == "env reflections"

        assert p.physical.world is not None
        assert p.physical.world.bg_color is not None
        assert p.physical.world.strength == 1.0

        assert p.visual.composition is not None
        assert p.visual.composition.thirds == 0.71
        assert p.visual.composition.visible == 3
        assert p.visual.composition.total == 3

        assert p.visual.ray_grid is not None
        assert p.visual.ray_grid.resolution == 12
        assert p.visual.ray_grid.coverage["Cube"] == 15.0
        assert p.visual.ray_grid.empty == 42.0

    def test_round_trip(self) -> None:
        text = (FIXTURES / "minimal.picacia").read_text()
        p = from_text(text)
        rt = to_text(p)
        _compare_lines(text, rt)


class TestFullFixture:
    """Round-trip tests on full.picacia."""

    def test_parse(self) -> None:
        text = (FIXTURES / "full.picacia").read_text()
        p = from_text(text)

        # SCENE header
        assert p.identity.scene_header is not None
        assert p.identity.scene_header.obj_count == 11
        assert p.identity.scene_header.light_count == 2
        assert p.identity.scene_header.energy == 1100.0
        assert p.identity.scene_header.engine == "BLENDER_EEVEE"
        assert p.identity.scene_header.ground_z == 0

        assert len(p.identity.cameras) == 1
        assert p.identity.cameras[0].name == "PlayerCam"
        assert len(p.identity.lights) == 2
        assert len(p.identity.objects) == 11  # +GlassCase, +Artifact

        # dim=, rot=, facing=, zone= on objects
        crate_a = p.identity.objects[0]
        assert crate_a.name == "Crate_A"
        assert crate_a.dimensions is not None
        assert crate_a.dimensions.x == 1.0
        assert crate_a.rotation is not None
        assert crate_a.rotation.z == 15.0
        assert crate_a.facing == "NE"
        assert crate_a.zone == "storage"
        assert crate_a.has_uv is True
        assert crate_a.lum == 0.7

        forklift = p.identity.objects[3]
        assert forklift.name == "Forklift"
        assert forklift.rotation is not None
        assert forklift.rotation.z == 90.0
        assert forklift.facing == "E"
        assert forklift.zone == "dock"

        # transparent + contains/inside
        glass_case = p.identity.objects[6]
        assert glass_case.name == "GlassCase"
        assert glass_case.transparent is True
        assert glass_case.contains == ["Artifact"]

        artifact = p.identity.objects[7]
        assert artifact.name == "Artifact"
        assert artifact.inside == "GlassCase"
        assert artifact.lum == 0.8

        # no_uv on Floor
        floor = p.identity.objects[8]
        assert floor.name == "Floor"
        assert floor.has_uv is False

        # SGROUP
        assert len(p.identity.semantic_groups) == 1
        assert p.identity.semantic_groups[0].name == "Crates"
        assert p.identity.semantic_groups[0].member_count == 2
        assert p.identity.semantic_groups[0].facing == "NE"

        # ASSEMBLY
        assert len(p.identity.assemblies) == 1
        assert p.identity.assemblies[0].name == "Display"
        assert p.identity.assemblies[0].members == ["GlassCase", "Artifact"]
        assert p.identity.assemblies[0].types == "MESH"

        assert len(p.spatial.relationships) == 11  # +GlassCase->Floor, Artifact->GlassCase

        # aabb_overlap= on REL
        assert p.spatial.relationships[0].aabb_overlap_pct == 8.0

        # Artifact->GlassCase overlap= with pct
        artifact_rel = p.spatial.relationships[10]
        assert artifact_rel.from_obj == "Artifact"
        assert artifact_rel.to_obj == "GlassCase"
        assert artifact_rel.overlap is True
        assert artifact_rel.overlap_pct == 80.0
        assert artifact_rel.aabb_overlap_pct == 95.0

        # VERIFY
        assert len(p.spatial.verify) == 1
        assert p.spatial.verify[0].object == "Wall_N"
        assert "subdivide" in p.spatial.verify[0].message

        # CONTAIN
        assert len(p.spatial.containment) == 1
        assert p.spatial.containment[0].outer == "GlassCase"
        assert p.spatial.containment[0].inner == "Artifact"
        assert p.spatial.containment[0].mode == "full"

        # SPATIAL facts
        assert len(p.spatial.spatial_facts) == 2
        assert p.spatial.spatial_facts[0].object == "Barrel"
        assert p.spatial.spatial_facts[0].type == "bbox_below_surface"
        assert p.spatial.spatial_facts[1].object == "Wall_N"
        assert p.spatial.spatial_facts[1].type == "scale_ratio"

        assert len(p.physical.light_analyses) == 6
        assert len(p.physical.shadow_analyses) == 3
        assert len(p.physical.materials) == 8  # +Glass, +Gold
        assert p.physical.world is not None

        # HARMONY
        assert p.physical.harmony is not None
        assert "wood" in p.physical.harmony.types
        assert p.physical.harmony.temperature == "warm"

        # PALETTE
        assert p.physical.palette is not None
        assert p.physical.palette.luminance == 0.45
        assert "warm_brown" in p.physical.palette.palette

        assert len(p.physical.physics_states) == 6
        assert p.physical.physics_states[0].name == "Crate_A"
        assert p.physical.physics_states[0].type == "dynamic"
        assert p.physical.physics_states[0].mass_kg == 25.0
        assert p.physical.physics_states[0].sleeping is True

        assert len(p.physical.contacts) == 4
        assert p.physical.contacts[0].obj_a == "Crate_A"
        assert p.physical.contacts[0].obj_b == "Floor"
        assert p.physical.contacts[0].force_n == 245.3

        assert len(p.physical.sounds) == 3
        assert p.physical.sounds[0].source == "Forklift"
        assert p.physical.sounds[0].type == "point"
        assert p.physical.sounds[0].distance == 8.2

        assert p.visual.composition is not None
        assert p.visual.composition.edge == ["Floor", "Ceiling"]
        assert p.visual.composition.visible == 11
        assert p.visual.composition.total == 11
        assert p.visual.ray_grid is not None
        assert len(p.visual.multi_views) == 2

        assert len(p.semantic.hierarchy) == 3  # +Artifact > GlassCase
        assert p.semantic.hierarchy[0].chain == ["Crate_B", "Crate_A"]
        assert p.semantic.hierarchy[1].chain == ["Rifle", "Guard"]
        assert p.semantic.hierarchy[2].chain == ["Artifact", "GlassCase"]

        assert len(p.semantic.groups) == 4
        assert p.semantic.groups[0].name == "Storage"
        assert p.semantic.groups[0].members == ["Crate_A", "Crate_B", "Barrel", "GlassCase", "Artifact"]

        assert len(p.temporal.animations) == 2
        assert p.temporal.animations[0].name == "Guard"
        assert p.temporal.animations[0].action == "Patrol"
        assert p.temporal.animations[0].frame == 45
        assert p.temporal.animations[0].total == 120
        assert p.temporal.animations[0].playing is True

    def test_round_trip(self) -> None:
        text = (FIXTURES / "full.picacia").read_text()
        p = from_text(text)
        rt = to_text(p)
        _compare_lines(text, rt)


# ---------------------------------------------------------------------------
# Individual line type parsing tests
# ---------------------------------------------------------------------------

class TestLineParsing:
    """Test parsing individual line types."""

    def test_cam(self) -> None:
        p = from_text("CAM MyCam [1,2,3] 35mm")
        assert p.identity.cameras[0].name == "MyCam"
        assert p.identity.cameras[0].position.x == 1.0
        assert p.identity.cameras[0].focal_mm == 35.0

    def test_light(self) -> None:
        p = from_text("LIGHT Sun SUN 2.5W [1.0,0.95,0.9] [0,0,10]")
        assert p.identity.lights[0].name == "Sun"
        assert p.identity.lights[0].type == "SUN"
        assert p.identity.lights[0].energy_w == 2.5

    def test_obj_minimal(self) -> None:
        p = from_text("OBJ Box [0,0,0] 10% mid-center d=3.0m Default(textured)")
        obj = p.identity.objects[0]
        assert obj.name == "Box"
        assert obj.coverage == 10.0
        assert obj.depth == 3.0
        assert obj.face is None

    def test_obj_full(self) -> None:
        p = from_text(
            "OBJ Box [0,0,0] 10% mid-center d=3.0m Default(rgb=0.5,0.5,0.5) face=+X"
        )
        obj = p.identity.objects[0]
        assert obj.face == "+X"

    def test_obj_lum(self) -> None:
        p = from_text("OBJ Box [0,0,0] 10% mid-center d=3.0m Default(textured) lum=0.85")
        obj = p.identity.objects[0]
        assert obj.lum == 0.85

    def test_scene_header(self) -> None:
        p = from_text("SCENE 42 objects 3 lights 1200W BLENDER_EEVEE ground_z=0.0")
        sh = p.identity.scene_header
        assert sh is not None
        assert sh.obj_count == 42
        assert sh.light_count == 3
        assert sh.energy == 1200.0
        assert sh.engine == "BLENDER_EEVEE"
        assert sh.ground_z == 0.0

    def test_sgroup(self) -> None:
        p = from_text('SGROUP "Dining Chairs" [2,1,0.4] dim=[3,2,0.8] top=0.8 wood facing=N members=4')
        sg = p.identity.semantic_groups[0]
        assert sg.name == "Dining Chairs"
        assert sg.position.x == 2.0
        assert sg.dimensions.x == 3.0
        assert sg.top_z == 0.8
        assert sg.material == "wood"
        assert sg.facing == "N"
        assert sg.member_count == 4

    def test_assembly(self) -> None:
        p = from_text('ASSEMBLY "Desk Lamp" members=[Lamp_Base,Lamp_Arm,Shade,Bulb] center=[2,1,0.8] types=MESH+LIGHT')
        asm = p.identity.assemblies[0]
        assert asm.name == "Desk Lamp"
        assert asm.members == ["Lamp_Base", "Lamp_Arm", "Shade", "Bulb"]
        assert asm.center.x == 2.0
        assert asm.types == "MESH+LIGHT"

    def test_harmony(self) -> None:
        p = from_text("HARMONY types=wood+metal+concrete temp=warm")
        h = p.physical.harmony
        assert h is not None
        assert h.types == "wood+metal+concrete"
        assert h.temperature == "warm"

    def test_palette(self) -> None:
        p = from_text("PALETTE lum=0.45 warm_brown near_black amber")
        pal = p.physical.palette
        assert pal is not None
        assert pal.luminance == 0.45
        assert pal.palette == ["warm_brown", "near_black", "amber"]

    def test_palette_no_lum(self) -> None:
        p = from_text("PALETTE warm_brown near_black amber")
        pal = p.physical.palette
        assert pal is not None
        assert pal.luminance is None
        assert pal.palette == ["warm_brown", "near_black", "amber"]

    def test_verify(self) -> None:
        p = from_text("VERIFY FAIL Chair_01 parent moved but mesh AABB unchanged")
        v = p.spatial.verify[0]
        assert v.object == "Chair_01"
        assert "parent moved" in v.message

    def test_rel_basic(self) -> None:
        p = from_text("REL A->B 2.0m left same_level")
        rel = p.spatial.relationships[0]
        assert rel.from_obj == "A"
        assert rel.to_obj == "B"
        assert rel.distance == 2.0
        assert rel.direction == "left"
        assert rel.vertical == "same_level"
        assert rel.contact is False

    def test_rel_contact(self) -> None:
        p = from_text("REL A->B 0.0m below contact")
        rel = p.spatial.relationships[0]
        assert rel.direction == "below"
        assert rel.contact is True

    def test_rel_unicode_arrow(self) -> None:
        p = from_text("REL A\u2192B 2.0m left same_level")
        rel = p.spatial.relationships[0]
        assert rel.from_obj == "A"
        assert rel.to_obj == "B"

    def test_lit(self) -> None:
        p = from_text("LIT Key->Cube @42\u00b0 i=0.85")
        la = p.physical.light_analyses[0]
        assert la.light == "Key"
        assert la.surface == "Cube"
        assert la.angle == 42.0
        assert la.intensity == 0.85

    def test_lit_with_shadow(self) -> None:
        p = from_text("LIT Key->Floor @65\u00b0 i=0.45 shadow:Cube,Sphere")
        la = p.physical.light_analyses[0]
        assert la.shadow == ["Cube", "Sphere"]

    def test_shad(self) -> None:
        p = from_text("SHAD Key->Floor 12% casters:Cube,Sphere contact")
        sa = p.physical.shadow_analyses[0]
        assert sa.coverage == 12.0
        assert sa.casters == ["Cube", "Sphere"]
        assert sa.contact is True
        assert sa.gap is None

    def test_shad_gap(self) -> None:
        p = from_text("SHAD Sun->Wall 5% casters:Tree gap=0.3m")
        sa = p.physical.shadow_analyses[0]
        assert sa.gap == 0.3
        assert sa.contact is False

    def test_mat_simple(self) -> None:
        p = from_text("MAT Default: light grey matte")
        mat = p.physical.materials[0]
        assert mat.name == "Default"
        assert mat.appearance == "light grey matte"
        assert mat.needs is None

    def test_mat_needs(self) -> None:
        p = from_text("MAT Metal: polished metal -- needs env reflections")
        mat = p.physical.materials[0]
        assert mat.appearance == "polished metal"
        assert mat.needs == "env reflections"

    def test_world_bg(self) -> None:
        p = from_text("WORLD bg=[0.05,0.05,0.05] strength=1.0")
        w = p.physical.world
        assert w is not None
        assert w.bg_color is not None
        assert w.bg_color.x == 0.05
        assert w.strength == 1.0
        assert w.hdri is False

    def test_world_hdri(self) -> None:
        p = from_text("WORLD hdri strength=2.0")
        w = p.physical.world
        assert w is not None
        assert w.hdri is True
        assert w.strength == 2.0

    def test_phys(self) -> None:
        p = from_text("PHYS Crate dynamic mass=25.0kg sleeping")
        ps = p.physical.physics_states[0]
        assert ps.name == "Crate"
        assert ps.type == "dynamic"
        assert ps.mass_kg == 25.0
        assert ps.sleeping is True
        assert ps.velocity is None

    def test_phys_with_vel(self) -> None:
        p = from_text("PHYS Ball dynamic mass=1.0kg vel=[0.0,0.0,-9.8]")
        ps = p.physical.physics_states[0]
        assert ps.velocity is not None
        assert ps.velocity.z == -9.8

    def test_contact(self) -> None:
        p = from_text("CONTACT A<>B normal=[0,1,0] force=147.1N surface=concrete")
        ct = p.physical.contacts[0]
        assert ct.obj_a == "A"
        assert ct.obj_b == "B"
        assert ct.normal.y == 1.0
        assert ct.force_n == 147.1
        assert ct.surface == "concrete"

    def test_snd(self) -> None:
        p = from_text("SND Radio type=point vol=0.6 dist=3.2m dir=left occ=0.4")
        snd = p.physical.sounds[0]
        assert snd.source == "Radio"
        assert snd.type == "point"
        assert snd.volume == 0.6
        assert snd.distance == 3.2
        assert snd.direction == "left"
        assert snd.occlusion == 0.4

    def test_comp(self) -> None:
        p = from_text("COMP thirds=0.71 3/3_visible balance=0.62 depth=1/3")
        c = p.visual.composition
        assert c is not None
        assert c.thirds == 0.71
        assert c.visible == 3
        assert c.total == 3
        assert c.balance == 0.62
        assert c.depth == "1/3"
        assert c.edge == []

    def test_comp_with_edge(self) -> None:
        p = from_text("COMP thirds=0.65 9/9_visible balance=0.55 depth=3/3 edge:[Floor,Ceiling]")
        c = p.visual.composition
        assert c is not None
        assert c.edge == ["Floor", "Ceiling"]

    def test_ray(self) -> None:
        p = from_text("RAY 12x12 Cube=15% Floor=35% empty=42%")
        rg = p.visual.ray_grid
        assert rg is not None
        assert rg.resolution == 12
        assert rg.coverage["Cube"] == 15.0
        assert rg.coverage["Floor"] == 35.0
        assert rg.empty == 42.0

    def test_mview(self) -> None:
        p = from_text("MVIEW front: Cube=20% Sphere=12%")
        mv = p.visual.multi_views[0]
        assert mv.view == "front"
        assert mv.coverage["Cube"] == 20.0

    def test_hier(self) -> None:
        p = from_text("HIER Wheel > Axle > Car")
        h = p.semantic.hierarchy[0]
        assert h.chain == ["Wheel", "Axle", "Car"]

    def test_grp(self) -> None:
        p = from_text("GRP Vehicles: Car, Truck, Bike")
        g = p.semantic.groups[0]
        assert g.name == "Vehicles"
        assert g.members == ["Car", "Truck", "Bike"]

    def test_anim_playing(self) -> None:
        p = from_text("ANIM Guard action=Patrol frame=45/120 playing")
        a = p.temporal.animations[0]
        assert a.name == "Guard"
        assert a.action == "Patrol"
        assert a.frame == 45
        assert a.total == 120
        assert a.playing is True

    def test_anim_stopped(self) -> None:
        p = from_text("ANIM Door action=Open frame=24/24 stopped")
        a = p.temporal.animations[0]
        assert a.playing is False

    # REL flags ----------------------------------------------------------

    def test_rel_overlap(self) -> None:
        p = from_text("REL A->B 1.5m right same_level overlap")
        rel = p.spatial.relationships[0]
        assert rel.overlap is True
        assert rel.occludes is False
        assert rel.contact is False

    def test_rel_occludes(self) -> None:
        p = from_text("REL A->B 3.0m behind above occludes occ=55.6%")
        rel = p.spatial.relationships[0]
        assert rel.occludes is True
        assert rel.occ_pct == 55.6
        assert rel.vertical == "above"

    def test_rel_all_flags(self) -> None:
        p = from_text("REL A->B 0.0m left below overlap contact occludes occ=100%")
        rel = p.spatial.relationships[0]
        assert rel.overlap is True
        assert rel.contact is True
        assert rel.occludes is True
        assert rel.occ_pct == 100.0
        assert rel.vertical == "below"

    def test_rel_occ_without_occludes(self) -> None:
        """occ= can appear without the occludes flag (partial occlusion below threshold)."""
        p = from_text("REL A->B 2.0m right same_level occ=11.1%")
        rel = p.spatial.relationships[0]
        assert rel.occ_pct == 11.1

    # DELTA --------------------------------------------------------------

    def test_delta(self) -> None:
        p = from_text("DELTA Crate moved [0.5,0,0] (+X)")
        assert len(p.temporal.deltas) == 1
        assert p.temporal.deltas[0] == "Crate moved [0.5,0,0] (+X)"

    def test_delta_multiple(self) -> None:
        text = "DELTA Key light energy 500→800W\nDELTA Guard.base_color changed"
        p = from_text(text)
        assert len(p.temporal.deltas) == 2
        assert p.temporal.deltas[0] == "Key light energy 500→800W"
        assert p.temporal.deltas[1] == "Guard.base_color changed"

    def test_delta_round_trip(self) -> None:
        text = "# Perspicacity v1\nDELTA Crate moved [0.5,0,0] (+X)\nDELTA Key light energy changed\n"
        p = from_text(text)
        rt = to_text(p)
        assert "DELTA Crate moved [0.5,0,0] (+X)" in rt
        assert "DELTA Key light energy changed" in rt

    # MAT variants -------------------------------------------------------

    def test_mat_warning(self) -> None:
        p = from_text("MAT Brick: red brick wall -- tiling visible at close range")
        mat = p.physical.materials[0]
        assert mat.name == "Brick"
        assert mat.appearance == "red brick wall"

    # v1 feature tests ---------------------------------------------------

    def test_obj_containment(self) -> None:
        p = from_text("OBJ Bottle [0,0,0] 22% mid-center d=3.0m glass(ior=1.45) contains:[Bulb,Base]")
        obj = p.identity.objects[0]
        assert obj.contains == ["Bulb", "Base"]

    def test_obj_inside(self) -> None:
        p = from_text("OBJ Bulb [0,0,0] 0.5% mid-center d=3.1m gold(emit=5) inside=Bottle")
        obj = p.identity.objects[0]
        assert obj.inside == "Bottle"

    def test_lit_emissive(self) -> None:
        p = from_text("LIT EMIT:Bulb->Table @25\u00b0 i=0.45")
        la = p.physical.light_analyses[0]
        assert la.light == "EMIT:Bulb"
        assert la.intensity == 0.45

    def test_contain(self) -> None:
        p = from_text("CONTAIN Bottle contains Bulb full")
        assert len(p.spatial.containment) == 1
        assert p.spatial.containment[0].outer == "Bottle"
        assert p.spatial.containment[0].inner == "Bulb"
        assert p.spatial.containment[0].mode == "full"

    def test_contain_partial(self) -> None:
        p = from_text("CONTAIN Box contains Ball partial")
        assert p.spatial.containment[0].mode == "partial"

    def test_v1_round_trip(self) -> None:
        text = "\n".join([
            "CAM Cam [0,0,5] 50mm",
            "OBJ Bottle [0,0,0] 22% mid-center d=3m glass(ior=1.45) lum=0.35 contains:[Bulb]",
            "OBJ Bulb [0,0,0] 0.5% mid-center d=3.1m gold(emit=5) inside=Bottle",
            "CONTAIN Bottle contains Bulb full",
            "LIT EMIT:Bulb->Bottle @25\u00b0 i=0.45",
            "HARMONY types=glass+gold temp=warm",
            "PALETTE lum=0.15 warm_brown near_black amber",
            "WORLD bg=[1,0.7,0.4] strength=0.05",
        ])
        p = from_text(text)
        rt = to_text(p)
        p2 = from_text(rt)
        assert p2.identity.objects[0].contains == ["Bulb"]
        assert p2.identity.objects[1].inside == "Bottle"
        assert p2.physical.light_analyses[0].intensity == 0.45
        assert p2.spatial.containment[0].outer == "Bottle"
        assert p2.physical.harmony.types == "glass+gold"
        assert p2.physical.palette.luminance == 0.15
        assert p2.physical.palette.palette == ["warm_brown", "near_black", "amber"]

    # Multi-line integration ---------------------------------------------

    def test_full_scene_mini(self) -> None:
        """A small but complete scene with all tiers represented."""
        text = "\n".join([
            "SCENE 2 objects 1 lights 500W BLENDER_EEVEE ground_z=-1.0",
            "CAM Cam [0,0,5] 50mm",
            "LIGHT Key POINT 500W [1,1,1] [3,2,4]",
            "OBJ Cube [0,0,0] 15% mid-center d=5m Default(textured) face=+Z lum=0.8",
            "OBJ Floor [0,0,-1] 35% bot-center d=5.8m Concrete(textured)",
            "REL Cube->Floor 1m below contact",
            "VERIFY FAIL Cube parent moved but mesh didn't",
            "LIT Key->Cube @42° i=0.85",
            "SHAD Key->Floor 12% casters:Cube contact",
            "MAT Default: light grey matte",
            "MAT Concrete: textured concrete -- needs normal map",
            "HARMONY types=matte+concrete temp=neutral",
            "PALETTE lum=0.6 light_grey dark_grey",
            "WORLD bg=[0.05,0.05,0.05] strength=1",
            "PHYS Cube dynamic mass=10kg",
            "CONTACT Cube<>Floor normal=[0,1,0] force=98.1N surface=concrete",
            "COMP thirds=0.71 2/2_visible balance=0.5 depth=1/3",
            "RAY 12x12 Cube=15% Floor=35% empty=50%",
            "MVIEW top: Floor=60% Cube=10%",
            "HIER Cube > Scene",
            "GRP Props: Cube",
            "ANIM Cube action=Spin frame=5/60 playing",
            "DELTA Cube moved [0.1,0,0] (+X)",
        ])
        p = from_text(text)

        # SCENE header
        assert p.identity.scene_header is not None
        assert p.identity.scene_header.obj_count == 2
        assert p.identity.scene_header.ground_z == -1.0

        # Identity
        assert len(p.identity.cameras) == 1
        assert len(p.identity.lights) == 1
        assert len(p.identity.objects) == 2
        assert p.identity.objects[0].face == "+Z"
        assert p.identity.objects[0].lum == 0.8

        # Spatial
        assert p.spatial.relationships[0].contact is True
        assert len(p.spatial.verify) == 1
        assert p.spatial.verify[0].object == "Cube"

        # Visual
        assert p.visual.composition.visible == 2
        assert p.visual.ray_grid.resolution == 12
        assert len(p.visual.multi_views) == 1

        # Physical
        assert p.physical.light_analyses[0].angle == 42.0
        assert p.physical.shadow_analyses[0].contact is True
        assert p.physical.materials[1].needs == "normal map"
        assert p.physical.physics_states[0].type == "dynamic"
        assert p.physical.contacts[0].force_n == 98.1
        assert p.physical.harmony.types == "matte+concrete"
        assert p.physical.palette.luminance == 0.6

        # Semantic
        assert p.semantic.hierarchy[0].chain == ["Cube", "Scene"]
        assert p.semantic.groups[0].members == ["Cube"]

        # Temporal
        assert p.temporal.animations[0].playing is True
        assert p.temporal.deltas[0] == "Cube moved [0.1,0,0] (+X)"

        # Round-trip
        rt = to_text(p)
        p2 = from_text(rt)
        assert len(p2.identity.objects) == 2
        assert len(p2.temporal.deltas) == 1


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

class TestEdgeCases:
    """Edge case tests."""

    def test_empty_scene(self) -> None:
        p = from_text("")
        assert len(p.identity.cameras) == 0
        assert len(p.identity.objects) == 0

    def test_comments_only(self) -> None:
        p = from_text("# just a comment\n# another comment\n")
        assert len(p.identity.cameras) == 0

    def test_no_lights(self) -> None:
        text = "CAM Cam [0,0,5] 50mm\nOBJ Cube [0,0,0] 10% mid-center d=5.0m Default(textured)"
        p = from_text(text)
        assert len(p.identity.cameras) == 1
        assert len(p.identity.lights) == 0
        assert len(p.identity.objects) == 1

    def test_viewpoint_from_camera(self) -> None:
        p = from_text("CAM MyCam [1,2,3] 50mm")
        assert p.viewpoint == "MyCam"
        assert p.viewpoint_position.x == 1.0
        assert p.viewpoint_position.y == 2.0
        assert p.viewpoint_position.z == 3.0

    def test_blank_lines_ignored(self) -> None:
        text = "CAM Cam [0,0,5] 50mm\n\n\nOBJ Cube [0,0,0] 10% mid-center d=5.0m Default(textured)\n\n"
        p = from_text(text)
        assert len(p.identity.cameras) == 1
        assert len(p.identity.objects) == 1

    def test_unknown_prefix_ignored(self) -> None:
        text = "CAM Cam [0,0,5] 50mm\nFOO bar baz\nOBJ Cube [0,0,0] 10% mid-center d=5.0m Default(textured)"
        p = from_text(text)
        assert len(p.identity.cameras) == 1
        assert len(p.identity.objects) == 1
