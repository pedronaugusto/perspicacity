"""Perspicacity v1 — Pure Python dataclasses for scene perception.

Zero dependencies. No bpy, no numpy.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional


@dataclass
class Vec3:
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0


# ---------------------------------------------------------------------------
# Tier 0 — Identity
# ---------------------------------------------------------------------------

@dataclass
class SceneHeader:
    obj_count: int = 0
    light_count: int = 0
    energy: float = 0.0
    engine: str = ""
    ground_z: Optional[float] = None


@dataclass
class CameraData:
    name: str = ""
    position: Vec3 = field(default_factory=Vec3)
    focal_mm: float = 50.0


@dataclass
class LightData:
    name: str = ""
    type: str = "POINT"  # POINT | SUN | SPOT | AREA
    energy_w: float = 0.0
    color: Vec3 = field(default_factory=Vec3)
    position: Vec3 = field(default_factory=Vec3)


@dataclass
class ObjectData:
    name: str = ""
    position: Vec3 = field(default_factory=Vec3)
    coverage: float = 0.0
    quadrant: str = "mid-center"
    depth: float = 0.0
    material: str = ""
    dimensions: Optional[Vec3] = None
    top_z: Optional[float] = None  # AABB max Z — surface height for placement
    source: Optional[str] = None  # semantic name for hierarchy children
    rotation: Optional[Vec3] = None  # euler degrees, only when any component > 1°
    facing: Optional[str] = None  # compass: N/NE/E/SE/S/SW/W/NW
    zone: Optional[str] = None  # user-defined spatial zone
    face: Optional[str] = None
    lum: Optional[float] = None
    transparent: bool = False
    has_uv: Optional[bool] = None
    flipped_normals_pct: Optional[float] = None
    non_manifold_edges: Optional[int] = None
    inside: Optional[str] = None
    contains: List[str] = field(default_factory=list)


@dataclass
class SemanticGroupData:
    name: str = ""
    position: Vec3 = field(default_factory=Vec3)
    dimensions: Vec3 = field(default_factory=Vec3)
    top_z: float = 0.0
    material: str = ""
    facing: Optional[str] = None
    member_count: int = 0


@dataclass
class AssemblyData:
    name: str = ""
    members: List[str] = field(default_factory=list)
    center: Vec3 = field(default_factory=Vec3)
    types: str = ""


# ---------------------------------------------------------------------------
# Tier 1 — Spatial
# ---------------------------------------------------------------------------

@dataclass
class RelationshipData:
    from_obj: str = ""
    to_obj: str = ""
    distance: float = 0.0
    direction: str = ""
    vertical: Optional[str] = None
    overlap: bool = False
    overlap_pct: Optional[float] = None
    aabb_overlap_pct: Optional[float] = None
    contact: bool = False
    occludes: bool = False
    occ_pct: Optional[float] = None


@dataclass
class VerifyResult:
    """Post-transform verification — only emitted on failure."""
    object: str = ""
    message: str = ""


@dataclass
class ContainmentData:
    outer: str = ""
    inner: str = ""
    mode: str = "full"  # full | partial


@dataclass
class SpatialFact:
    object: str = ""
    type: str = ""  # bbox_below_surface, bbox_extends_into, scale_diagonal, etc.
    details: Dict[str, object] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Tier 2 — Visual
# ---------------------------------------------------------------------------

@dataclass
class CompositionData:
    thirds: float = 0.0
    visible: int = 0
    total: int = 0
    balance: float = 0.0
    depth: str = "1/3"
    edge: List[str] = field(default_factory=list)


@dataclass
class RayGridData:
    resolution: int = 0
    coverage: Dict[str, float] = field(default_factory=dict)
    empty: float = 0.0


@dataclass
class MultiViewData:
    view: str = ""
    coverage: Dict[str, float] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Tier 3 — Physical
# ---------------------------------------------------------------------------

@dataclass
class LightAnalysisData:
    light: str = ""
    surface: str = ""
    angle: float = 0.0
    intensity: float = 0.0
    effective: Optional[float] = None
    raw_intensity: Optional[float] = None
    shadow: List[str] = field(default_factory=list)


@dataclass
class ShadowAnalysisData:
    light: str = ""
    surface: str = ""
    coverage: float = 0.0
    casters: List[str] = field(default_factory=list)
    contact: bool = False
    gap: Optional[float] = None


@dataclass
class MaterialPrediction:
    name: str = ""
    appearance: str = ""
    needs: Optional[str] = None
    warning: Optional[str] = None


@dataclass
class HarmonyData:
    types: str = ""
    temperature: str = ""


@dataclass
class PaletteData:
    luminance: Optional[float] = None
    palette: List[str] = field(default_factory=list)


@dataclass
class WorldData:
    bg_color: Optional[Vec3] = None
    hdri: bool = False
    strength: float = 1.0


@dataclass
class PhysicsState:
    name: str = ""
    type: str = "static"  # static | dynamic | kinematic
    mass_kg: float = 0.0
    velocity: Optional[Vec3] = None
    sleeping: bool = False


@dataclass
class ContactData:
    obj_a: str = ""
    obj_b: str = ""
    normal: Vec3 = field(default_factory=Vec3)
    force_n: float = 0.0
    surface: str = ""


@dataclass
class SoundData:
    source: str = ""
    type: str = "point"  # ambient | point | directional
    volume: float = 0.0
    distance: float = 0.0
    direction: str = ""
    occlusion: float = 0.0


# ---------------------------------------------------------------------------
# Tier 4 — Semantic
# ---------------------------------------------------------------------------

@dataclass
class HierarchyEntry:
    chain: List[str] = field(default_factory=list)


@dataclass
class GroupEntry:
    name: str = ""
    members: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Tier 5 — Temporal
# ---------------------------------------------------------------------------

@dataclass
class AnimationState:
    name: str = ""
    action: str = ""
    frame: int = 0
    total: int = 0
    playing: bool = False


# ---------------------------------------------------------------------------
# Tier containers
# ---------------------------------------------------------------------------

@dataclass
class IdentityTier:
    scene_header: Optional[SceneHeader] = None
    cameras: List[CameraData] = field(default_factory=list)
    lights: List[LightData] = field(default_factory=list)
    objects: List[ObjectData] = field(default_factory=list)
    semantic_groups: List[SemanticGroupData] = field(default_factory=list)
    assemblies: List[AssemblyData] = field(default_factory=list)
    focus: Optional['FocusData'] = None


@dataclass
class SpatialTier:
    relationships: List[RelationshipData] = field(default_factory=list)
    verify: List[VerifyResult] = field(default_factory=list)
    containment: List[ContainmentData] = field(default_factory=list)
    spatial_facts: List[SpatialFact] = field(default_factory=list)


@dataclass
class VisualTier:
    composition: Optional[CompositionData] = None
    ray_grid: Optional[RayGridData] = None
    multi_views: List[MultiViewData] = field(default_factory=list)


@dataclass
class PhysicalTier:
    light_analyses: List[LightAnalysisData] = field(default_factory=list)
    shadow_analyses: List[ShadowAnalysisData] = field(default_factory=list)
    materials: List[MaterialPrediction] = field(default_factory=list)
    harmony: Optional[HarmonyData] = None
    palette: Optional[PaletteData] = None
    world: Optional[WorldData] = None
    physics_states: List[PhysicsState] = field(default_factory=list)
    contacts: List[ContactData] = field(default_factory=list)
    sounds: List[SoundData] = field(default_factory=list)


@dataclass
class SemanticTier:
    hierarchy: List[HierarchyEntry] = field(default_factory=list)
    groups: List[GroupEntry] = field(default_factory=list)


@dataclass
class TemporalTier:
    animations: List[AnimationState] = field(default_factory=list)
    deltas: List[str] = field(default_factory=list)


@dataclass
class FocusData:
    """Proximity-based perception query parameters."""
    position: Vec3 = field(default_factory=Vec3)
    radius: float = 0.0
    near: int = 0
    mid: int = 0
    far: int = 0
    out: int = 0


# ---------------------------------------------------------------------------
# Top-level struct
# ---------------------------------------------------------------------------

@dataclass
class ScenePerception:
    focus: Optional[FocusData] = None
    viewpoint: str = "Camera"
    viewpoint_position: Vec3 = field(default_factory=Vec3)
    viewpoint_forward: Vec3 = field(default_factory=lambda: Vec3(0, 0, -1))
    identity: IdentityTier = field(default_factory=IdentityTier)
    spatial: SpatialTier = field(default_factory=SpatialTier)
    visual: VisualTier = field(default_factory=VisualTier)
    physical: PhysicalTier = field(default_factory=PhysicalTier)
    semantic: SemanticTier = field(default_factory=SemanticTier)
    temporal: TemporalTier = field(default_factory=TemporalTier)
