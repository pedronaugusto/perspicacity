# Perspicacity v1 Data Model

Field tables for every struct in the Perspicacity data model. Each field lists its name, type, whether it is required or optional, a description, and an example value.

---

## Vec3

| Field | Type  | Req/Opt  | Description       | Example |
|-------|-------|----------|-------------------|---------|
| x     | float | required | X component       | 0.0     |
| y     | float | required | Y component       | 0.0     |
| z     | float | required | Z component       | 5.0     |

---

## CAM — CameraData

| Field    | Type   | Req/Opt  | Description                  | Example      |
|----------|--------|----------|------------------------------|--------------|
| name     | string | required | Camera name                  | "Camera"     |
| position | Vec3   | required | World-space position         | [0,0,5]      |
| focal_mm | float  | required | Focal length in millimeters  | 50.0         |

---

## LIGHT — LightData

| Field     | Type   | Req/Opt  | Description                              | Example          |
|-----------|--------|----------|------------------------------------------|------------------|
| name       | string | required | Light name                               | "Key"            |
| type       | enum   | required | POINT, SUN, SPOT, AREA                   | "POINT"          |
| energy_w   | float  | required | Energy in watts (or unitless for SUN)    | 500.0            |
| color      | Vec3   | required | RGB color, each 0.0-1.0                  | [1.0,1.0,1.0]   |
| position   | Vec3   | required | World-space position                     | [3,2,4]          |
| spot_angle | float  | optional | Spot cone angle in degrees (SPOT only)   | 45.0             |
| spot_blend | float  | optional | Spot edge softness 0-1 (SPOT only)       | 0.15             |
| area_shape | string | optional | Area shape: square, rectangle, disk, ellipse (AREA only) | "rectangle" |
| area_size  | float  | optional | Area primary dimension in meters (AREA only) | 1.0          |
| area_size_y| float  | optional | Area secondary dimension in meters (RECTANGLE/ELLIPSE) | 0.5 |
| shadow     | bool   | optional | Whether shadow casting is enabled        | true             |

---

## OBJ — ObjectData

| Field       | Type   | Req/Opt  | Description                                        | Example                                  |
|-------------|--------|----------|----------------------------------------------------|------------------------------------------|
| name        | string | required | Object name                                        | "Cube"                                   |
| position    | Vec3   | required | World-space mesh AABB center `(min+max)/2`         | [0,0,0]                                  |
| coverage    | float  | required | Screen-space coverage percentage                   | 15.0                                     |
| quadrant    | string | required | Position in 3x3 frame grid                         | "mid-center"                             |
| depth       | float  | required | Distance from camera in meters                     | 5.0                                      |
| material    | string | required | Material description with properties               | "Default(rgb=0.80,0.80,0.80,rough=0.5)" |
| dimensions  | Vec3   | optional | World-space bounding box dimensions [w,h,d] in meters | [2.0,2.0,2.0]                       |
| top_z       | float  | optional | AABB max Z — the surface height for placing objects on  | 0.88                               |
| source      | string | optional | Semantic source name for hierarchy children              | "Cassidy Dinning Chair"            |
| rotation    | Vec3   | optional | Euler rotation in degrees. Only when any component > 1° | [0,0,45]                          |
| facing      | string | optional | Compass direction: N/NE/E/SE/S/SW/W/NW. Derived from Z-rotation | "NE"                    |
| zone        | string | optional | User-defined spatial zone (scene-specific, not hardcoded) | "kitchen"                         |
| face        | string | optional | Most visible face direction                        | "+Z"                                     |
| lum         | float  | optional | Rendered luminance (0.0-1.0)                   | 0.85 |
| transparent | bool   | optional | Material has transmission > 0.5 or Glass BSDF     | true                                     |
| has_uv      | bool   | optional | Object has UV layers                               | true                                     |
| flipped_normals_pct | float | optional | Percentage of sampled normals pointing inward (>2% coverage only) | 35.0          |
| non_manifold_edges | int | optional | Count of non-manifold edges (>2% coverage only)  | 12                                       |
| inside      | string | optional | Name of containing object                          | "Bottle"                                 |
| contains    | list[str] | optional | Names of contained objects                      | ["Bulb","Palace"]                        |

---

## REL — RelationshipData

| Field     | Type   | Req/Opt  | Description                                  | Example      |
|-----------|--------|----------|----------------------------------------------|--------------|
| from_obj  | string | required | Source object name                           | "Cube"       |
| to_obj    | string | required | Target object name                           | "Sphere"     |
| distance  | float  | required | Distance in meters                           | 2.0          |
| direction | string | required | Camera-relative direction (left, right, etc) | "left"       |
| vertical  | string | optional | Vertical relationship (same_level, above, below) | "same_level" |
| overlap   | bool   | optional | Objects overlap in screen space (camera-dependent) | false    |
| overlap_pct | float | optional | Screen-space overlap % (intersection / smaller AABB) | 65.2   |
| aabb_overlap_pct | float | optional | World-space AABB volume overlap as % of smaller object (camera-independent) | 12.0 |
| contact   | bool   | optional | Objects are in physical contact               | true         |
| occludes  | bool   | optional | Source occludes target                        | false        |
| occ_pct   | float  | optional | Occlusion percentage                          | 25.0         |

---

## LIT — LightAnalysisData

| Field     | Type       | Req/Opt  | Description                        | Example          |
|-----------|------------|----------|------------------------------------|------------------|
| light         | string     | required | Light name                                    | "Key"            |
| surface       | string     | required | Receiving surface name                        | "Cube"           |
| angle         | float      | required | Incidence angle in degrees                    | 42.0             |
| intensity     | float      | required | Normalized intensity (0.0-1.0, scene-relative)| 0.85            |
| raw_intensity | float      | optional | Absolute intensity (energy × cos / dist²)     | 372.5           |
| effective     | float      | optional | Effective brightness on absolute perceptual scale | 6.7           |
| shadow        | list[str]  | optional | Shadow caster names                           | ["Cube","Sphere"]|

---

## SHAD — ShadowAnalysisData

| Field      | Type       | Req/Opt  | Description                        | Example            |
|------------|------------|----------|------------------------------------|--------------------|
| light      | string     | required | Light name                         | "Key"              |
| surface    | string     | required | Receiving surface name             | "Floor"            |
| coverage   | float      | required | Shadow coverage percentage         | 12.0               |
| casters    | list[str]  | optional | Shadow caster names                | ["Cube","Sphere"]  |
| contact    | bool       | optional | Shadow is contact shadow (touching)| true               |
| gap        | float      | optional | Gap between caster and surface (m) | 0.3                |

---

## MAT — MaterialPrediction

| Field      | Type   | Req/Opt  | Description                              | Example                        |
|------------|--------|----------|------------------------------------------|--------------------------------|
| name       | string | required | Material name                            | "Metal"                        |
| appearance | string | required | Visual description                       | "polished metal"               |
| needs      | string | optional | What the material needs to look correct  | "env reflections"              |
| warning    | string | optional | Warning or issue description             | "tiling visible"               |

---

## WORLD — WorldData

| Field    | Type   | Req/Opt  | Description                          | Example            |
|----------|--------|----------|--------------------------------------|--------------------|
| bg_color | Vec3   | optional | Background RGB color (0.0-1.0 each) | [0.05,0.05,0.05]  |
| hdri     | bool   | optional | Whether HDRI is used                 | false              |
| strength | float  | required | Environment strength                 | 1.0                |


---

## CONTAIN — ContainmentData

| Field | Type   | Req/Opt  | Description                          | Example  |
|-------|--------|----------|--------------------------------------|----------|
| outer | string | required | Container object name                | "Bottle" |
| inner | string | required | Contained object name                | "Bulb"   |
| mode  | string | required | "full" (6/6 rays) or "partial" (4-5/6) | "full" |

---

## SPATIAL — SpatialFact

| Field   | Type   | Req/Opt  | Description                          | Example                |
|---------|--------|----------|--------------------------------------|------------------------|
| object  | string | required | Object name (or "scene" for global)  | "Chair_0"              |
| type    | string | required | Fact type identifier                 | "bbox_below_surface"   |
| details | dict   | required | Key-value pairs specific to fact type| {"surface": "Floor", "pct": 35} |

**Fact types:** `bbox_below_surface`, `bbox_extends_into`, `scale_diagonal`, `scale_ratio`, `no_material_slots`, `near_plane`, `inside_bbox`, `no_ground_below`, `no_light_sources`, `energy_zero`, `off_camera`, `zero_dimensions`

---

## VERIFY — VerifyResult

| Field   | Type   | Req/Opt  | Description                           | Example                                    |
|---------|--------|----------|---------------------------------------|--------------------------------------------|
| result  | string | required | "FAIL"                               | "FAIL"                                     |
| object  | string | required | Object name                           | "Chair_0"                                  |
| message | string | required | Human-readable failure description    | "parent moved but mesh AABB unchanged"     |

Only emitted on failure. Silent on success. Appears after modifying tool calls only.

---

## PALETTE — PaletteData

| Field      | Type       | Req/Opt  | Description                                    | Example                           |
|------------|------------|----------|------------------------------------------------|-----------------------------------|
| luminance  | float      | optional | Overall rendered luminance (0.0-1.0)          | 0.45                              |
| palette    | list[str]  | required | Dominant color names                          | ["warm_brown","dark_grey"]        |

---

## SCENE — SceneHeader

| Field       | Type   | Req/Opt  | Description                    | Example          |
|-------------|--------|----------|--------------------------------|------------------|
| obj_count   | int    | required | Total visible object count     | 42               |
| light_count | int    | required | Total light count              | 3                |
| energy      | float  | required | Total light energy in watts    | 1200.0           |
| engine      | string | required | Render engine name             | "BLENDER_EEVEE"  |
| ground_z    | float  | optional | Detected ground plane Z level  | 0.0              |

---

## SGROUP — SemanticGroupData

| Field        | Type   | Req/Opt  | Description                    | Example          |
|--------------|--------|----------|--------------------------------|------------------|
| name         | string | required | Group display name             | "Dining Chairs"  |
| position     | Vec3   | required | Group center position          | [2,1,0.4]        |
| dimensions   | Vec3   | required | Group bounding box             | [3,2,0.8]        |
| top_z        | float  | required | Top Z coordinate               | 0.8              |
| material     | string | optional | Representative material        | "wood"           |
| facing       | string | optional | Common facing direction        | "N"              |
| member_count | int    | required | Number of member objects        | 4                |

---

## ASSEMBLY — AssemblyData

| Field   | Type       | Req/Opt  | Description                    | Example                    |
|---------|------------|----------|--------------------------------|----------------------------|
| name    | string     | required | Assembly name                  | "Desk Lamp"               |
| members | list[str]  | required | Member object names            | ["Base","Arm","Shade"]     |
| center  | Vec3       | required | Assembly center position       | [2,1,0.8]                 |
| types   | string     | required | Member types joined with +     | "MESH+LIGHT"              |

---

## HARMONY — HarmonyData

| Field       | Type   | Req/Opt  | Description                    | Example          |
|-------------|--------|----------|--------------------------------|------------------|
| types       | string | required | Material type distribution     | "wood+metal+concrete" |
| temperature | string | required | Color temperature              | "warm"           |

---

## COMP — CompositionData

| Field      | Type       | Req/Opt  | Description                                   | Example    |
|------------|------------|----------|-----------------------------------------------|------------|
| thirds     | float      | required | Rule-of-thirds alignment score (0.0-1.0)     | 0.71       |
| visible    | int        | required | Number of visible objects                      | 3          |
| total      | int        | required | Total objects in scene                         | 3          |
| balance    | float      | required | Visual weight balance (0.0-1.0)               | 0.62       |
| depth      | string     | required | Depth layers used (e.g. "1/3", "2/3", "3/3") | "1/3"      |
| edge       | list[str]  | optional | Objects touching frame edge                    | ["Floor"]  |

---

## RAY — RayGridData

| Field      | Type            | Req/Opt  | Description                          | Example                |
|------------|-----------------|----------|--------------------------------------|------------------------|
| resolution | int             | required | Grid resolution (NxN)                | 12                     |
| coverage   | dict[str,float] | required | Object name to coverage percentage   | {"Cube":15.0}          |
| empty      | float           | required | Percentage of rays hitting nothing   | 42.0                   |

---

## MVIEW — MultiViewData

| Field    | Type            | Req/Opt  | Description                        | Example              |
|----------|-----------------|----------|------------------------------------|----------------------|
| view     | string          | required | View name                          | "front"              |
| coverage | dict[str,float] | required | Object name to coverage percentage | {"Cube":20.0}        |

---

## HIER — HierarchyEntry

| Field | Type       | Req/Opt  | Description                              | Example                          |
|-------|------------|----------|------------------------------------------|----------------------------------|
| chain | list[str]  | required | Hierarchy chain, child first, root last  | ["Wheel_FL","Axle_Front","Car"]  |

---

## GRP — GroupEntry

| Field   | Type       | Req/Opt  | Description              | Example                    |
|---------|------------|----------|--------------------------|----------------------------|
| name    | string     | required | Collection/group name    | "Vehicles"                 |
| members | list[str]  | required | Member object names      | ["Car_Body","Truck"]       |

---

## PHYS — PhysicsState

| Field    | Type   | Req/Opt  | Description                            | Example          |
|----------|--------|----------|----------------------------------------|------------------|
| name     | string | required | Object name                            | "Crate"          |
| type     | enum   | required | static, dynamic, kinematic             | "dynamic"        |
| mass_kg  | float  | required | Mass in kilograms                      | 15.0             |
| velocity | Vec3   | optional | Linear velocity                        | [0.0,0.0,-1.2]  |
| sleeping | bool   | optional | Whether the physics body is sleeping   | false            |

---

## ANIM — AnimationState

| Field   | Type   | Req/Opt  | Description                  | Example    |
|---------|--------|----------|------------------------------|------------|
| name    | string | required | Object name                  | "Character"|
| action  | string | required | Action/clip name             | "Walk"     |
| frame   | int    | required | Current frame number         | 12         |
| total   | int    | required | Total frames in action       | 30         |
| playing | bool   | required | Whether animation is playing | true       |

---

## CONTACT — ContactData

| Field   | Type   | Req/Opt  | Description                     | Example      |
|---------|--------|----------|---------------------------------|--------------|
| obj_a   | string | required | First object name               | "Crate"      |
| obj_b   | string | required | Second object name              | "Floor"      |
| normal  | Vec3   | required | Contact normal direction        | [0,0,1]      |
| force_n | float  | required | Contact force in Newtons        | 147.1        |
| surface | string | required | Surface material at contact     | "concrete"   |

---

## SND — SoundData

| Field     | Type   | Req/Opt  | Description                               | Example   |
|-----------|--------|----------|-------------------------------------------|-----------|
| source    | string | required | Sound source name                         | "Radio"   |
| type      | enum   | required | ambient, point, directional               | "point"   |
| volume    | float  | required | Perceived volume (0.0-1.0)               | 0.6       |
| distance  | float  | required | Distance from listener in meters          | 3.2       |
| direction | string | required | Camera-relative direction                 | "left"    |
| occlusion | float  | required | Occlusion factor (0.0 clear, 1.0 blocked)| 0.4       |

---

## FOCUS — FocusData

| Field  | Type  | Req/Opt  | Description                          | Example |
|--------|-------|----------|--------------------------------------|---------|
| position | Vec3 | required | Focus center position               | [0,0,1.5] |
| radius | float | required | Perception radius in meters          | 8.0     |
| near   | int   | required | Objects in near zone                 | 5       |
| mid    | int   | required | Objects in mid zone                  | 12      |
| far    | int   | required | Objects in far zone                  | 3       |
| out    | int   | required | Objects outside perception radius    | 2       |

---

## DELTA

DELTA is not a struct — it is a free-form string describing a change between two consecutive perception snapshots. Delta lines are computed on-the-fly by comparing the current `ScenePerception` to the previous one. They are only present when diffing; standalone `.picacia` files will not contain DELTA lines.

| Field       | Type   | Req/Opt  | Description                    | Example                      |
|-------------|--------|----------|--------------------------------|------------------------------|
| description | string | required | Human-readable change summary  | "Crate moved [0.5,0,0] (+X)" |

---

## Tier Containers

### IdentityTier

| Field           | Type                     | Req/Opt  | Description                        |
|-----------------|--------------------------|----------|------------------------------------|
| scene_header    | Optional[SceneHeader]    | optional | Scene-level summary                |
| cameras         | list[CameraData]         | required | All cameras in scene               |
| lights          | list[LightData]          | required | All lights in scene                |
| objects         | list[ObjectData]         | required | All visible objects (depth-sorted) |
| semantic_groups | list[SemanticGroupData]  | optional | Semantic object groups             |
| assemblies      | list[AssemblyData]       | optional | Multi-object assemblies            |
| focus           | Optional[FocusData]      | optional | Proximity-based perception focus   |

### SpatialTier

| Field         | Type                    | Req/Opt  | Description                        |
|---------------|-------------------------|----------|------------------------------------|
| relationships | list[RelationshipData]  | required | Pairwise object relations          |
| verify        | list[VerifyResult]      | optional | Post-modify verification results   |
| containment   | list[ContainmentData]   | optional | Containment relationships          |
| spatial_facts | list[SpatialFact]       | optional | Objective spatial facts            |

### VisualTier

| Field       | Type                      | Req/Opt  | Description                     |
|-------------|---------------------------|----------|---------------------------------|
| composition | Optional[CompositionData] | optional | Composition analysis            |
| ray_grid    | Optional[RayGridData]     | optional | Camera ray grid coverage map    |
| multi_views | list[MultiViewData]       | required | Synthetic viewpoint coverage    |

### PhysicalTier

| Field           | Type                      | Req/Opt  | Description                  |
|-----------------|---------------------------|----------|------------------------------|
| light_analyses  | list[LightAnalysisData]   | required | Per-light-surface analysis   |
| shadow_analyses | list[ShadowAnalysisData]  | required | Per-light shadow footprints  |
| materials       | list[MaterialPrediction]  | required | Material appearance + issues |
| harmony         | Optional[HarmonyData]     | optional | Material harmony analysis    |
| world           | Optional[WorldData]       | optional | Environment/background       |
| palette         | Optional[PaletteData]     | optional | Palette and luminance        |
| physics_states  | list[PhysicsState]        | required | Rigid body state             |
| contacts        | list[ContactData]         | required | Active physics contacts      |
| sounds          | list[SoundData]           | required | Audio sources                |

### SemanticTier

| Field     | Type                 | Req/Opt  | Description              |
|-----------|----------------------|----------|--------------------------|
| hierarchy | list[HierarchyEntry] | required | Parent chains            |
| groups    | list[GroupEntry]     | required | Collection/group members |

### TemporalTier

| Field      | Type                  | Req/Opt  | Description                     |
|------------|-----------------------|----------|---------------------------------|
| animations | list[AnimationState]  | required | Active animation state          |
| deltas     | list[str]             | required | Change descriptions (from diff) |

---

## ScenePerception (top-level)

| Field              | Type          | Req/Opt  | Description                        |
|--------------------|---------------|----------|------------------------------------|
| viewpoint          | string        | required | Who is perceiving (camera name, agent ID, "synthetic") |
| viewpoint_position | Vec3          | required | Observer world-space position      |
| viewpoint_forward  | Vec3          | required | Observer forward direction (unit)  |
| identity           | IdentityTier  | required | Tier 0 data                        |
| spatial            | SpatialTier   | required | Tier 1 data                        |
| visual             | VisualTier    | required | Tier 2 data                        |
| physical           | PhysicalTier  | required | Tier 3 data                        |
| semantic           | SemanticTier  | required | Tier 4 data                        |
| temporal           | TemporalTier  | required | Tier 5 data                        |
