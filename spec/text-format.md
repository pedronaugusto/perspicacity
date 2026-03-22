# Perspicacity v1 Text Format

Formal grammar for the `.picacia` text DSL.

---

## File Conventions

- **Encoding:** UTF-8
- **Line endings:** LF (`\n`) or CRLF (`\r\n`)
- **File extension:** `.picacia`
- **Comment lines:** lines starting with `#` (optional whitespace before `#`)
- **Empty lines:** ignored, may be used to separate sections
- **Empty sections:** may be omitted entirely

---

## Line Ordering

Lines should appear in this order. Note: Tier 3 (Physical) lines appear before Tier 2 (Visual) in the text format because LIT/SHAD/MAT/WORLD describe individual object/light properties (useful context while reading), while COMP/RAY/MVIEW are aggregate summaries best read last before issues:

1. Comments / header (`#`)
2. `SCENE` (tier 0 — identity, scene summary)
3. `CAM` (tier 0 — identity)
4. `LIGHT` (tier 0 — identity)
5. `OBJ` (tier 0 — identity, sorted front-to-back by depth)
6. `SGROUP` (tier 0 — identity, semantic groups)
7. `ASSEMBLY` (tier 0 — identity, functional units)
8. `REL` (tier 1 — spatial)
9. `VERIFY` (tier 1 — spatial, only after modifying tool calls, only on failure)
10. `CONTAIN` (tier 1 — spatial, containment)
11. `SPATIAL` (tier 1 — spatial, objective facts)
12. `LIT` (tier 3 — physical, light analysis)
13. `SHAD` (tier 3 — physical, shadows)
14. `MAT` (tier 3 — physical, materials)
15. `WORLD` (tier 3 — physical, environment)
16. `HARMONY` (tier 3 — physical, material distribution)
17. `PALETTE` (tier 3 — physical, color palette)
18. `PHYS` (tier 3 — physical, physics state)
19. `CONTACT` (tier 3 — physical, contacts)
20. `SND` (tier 3 — physical, sound)
21. `COMP` (tier 2 — visual, composition)
22. `RAY` (tier 2 — visual, ray grid)
23. `MVIEW` (tier 2 — visual, multi-view)
24. `HIER` (tier 4 — semantic, hierarchy)
25. `GRP` (tier 4 — semantic, groups)
26. `ANIM` (tier 5 — temporal)
27. `DELTA` (tier 5 — temporal, only when diffing)

---

## Number Formatting

- Decimal notation only, no scientific notation
- Floats: use `.` as decimal separator
- Percentages: integer or float followed by `%` with no space (e.g. `15%`, `12.5%`)
- Distances: float followed by `m` with no space (e.g. `5.0m`, `2.0m`)
- Angles: float or int followed by `°` with no space (e.g. `42°`, `38.5°`)
- Energy: float or int followed by `W` with no space (e.g. `500W`, `2.5W`)
- Focal length: float or int followed by `mm` with no space (e.g. `50mm`)
- Mass: float followed by `kg` with no space (e.g. `15.0kg`)
- Force: float followed by `N` with no space (e.g. `147.1N`)

---

## Vec3 Format

```
[x,y,z]
```

- Square brackets, three comma-separated numbers, no spaces
- Numbers are floats or integers
- Examples: `[0,0,5]`, `[1.0,0.95,0.9]`, `[-2,0,0]`

---

## Name Escaping

- Names are single tokens (no spaces) by default
- Names containing spaces must be enclosed in double quotes: `"My Object"`
- Names must not contain newlines, `[`, `]`, or `→`
- Quotes within names are not supported in v1

---

## Direction Enum Values

Camera-relative directions used in REL, SND, and other line types:

```
left, right, behind, in_front, above, below
```

Compound directions (optional):

```
left_above, left_below, right_above, right_below
in_front_left, in_front_right, behind_left, behind_right
```

---

## Quadrant Values

3x3 frame grid positions used in OBJ:

```
top-left, top-center, top-right
mid-left, mid-center, mid-right
bot-left, bot-center, bot-right
```

---

## Face Direction Values

Axis-aligned face directions used in OBJ `face=` field:

```
+X, -X, +Y, -Y, +Z, -Z
```

---

## Compass Direction Values

Objective compass labels used in OBJ `facing=` field, derived deterministically from world-space Y-axis rotation:

```
N, NE, E, SE, S, SW, W, NW
```

Compass mapping (from Z-rotation angle):
- **N**: -Y forward (337.5°-22.5°)
- **NE**: (-Y+X) (22.5°-67.5°)
- **E**: +X forward (67.5°-112.5°)
- **SE**: (+X+Y) (112.5°-157.5°)
- **S**: +Y forward (157.5°-202.5°)
- **SW**: (+Y-X) (202.5°-247.5°)
- **W**: -X forward (247.5°-292.5°)
- **NW**: (-X-Y) (292.5°-337.5°)

---

## Line Grammar (EBNF-like)

```ebnf
file          = { line LF } ;
line          = comment | scene | cam | light | obj | sgroup | assembly
              | rel | verify | contain | spatial | lit | shad | mat
              | world | harmony | palette | comp | ray | mview
              | hier | grp | phys | anim | delta | contact | snd | empty ;

comment       = "#" { any_char } ;
empty         = "" ;

(* Focus — proximity-based perception *)
focus         = "FOCUS" SP vec3 SP "radius=" float "m"
                SP "near=" int SP "mid=" int SP "far=" int SP "out=" int ;

(* Tier 0 — Identity *)
scene         = "SCENE" SP int SP "objects" SP int SP "lights" SP energy SP name
                { SP "ground_z=" float } ;
cam           = "CAM" SP name SP vec3 SP focal ;
light         = "LIGHT" SP name SP light_type SP energy SP color_vec3 SP position_vec3
                { SP light_extras } ;  (* first vec3 = [r,g,b] color, second = [x,y,z] position *)
light_extras  = spot_props | area_props | "noshadow" ;
spot_props    = "cone=" angle "°" SP "blend=" float ;
area_props    = area_shape SP dist { "x" dist } ;
obj           = "OBJ" SP name SP vec3 SP pct SP quadrant SP depth SP material
                { SP dim } { SP top } { SP src }
                { SP rot } { SP facing } { SP zone }
                { SP face } { SP lum }
                { SP "transparent" } { SP ( "has_uv" | "no_uv" ) }
                { SP flipped_normals } { SP non_manifold }
                { SP inside } { SP contains_list } ;
sgroup        = "SGROUP" SP name SP vec3 SP dim SP "top=" float SP name
                { SP facing } SP "members=" int ;
assembly      = "ASSEMBLY" SP name SP "members=[" name_list "]"
                SP "center=" vec3 SP "types=" name ;

contain       = "CONTAIN" SP name SP "contains" SP name SP ( "full" | "partial" ) ;

(* Tier 1 — Spatial *)
verify        = "VERIFY" SP "FAIL" SP name SP free_text ;
rel           = "REL" SP name arrow name SP dist SP direction
                { SP vertical } { SP ( "overlap" | "overlap=" pct ) }
                { SP "aabb_overlap=" pct } { SP "contact" }
                { SP "occludes" } { SP occ } ;
spatial       = "SPATIAL" SP name SP spatial_fact_type { SP kv_pair } ;
spatial_fact_type = "bbox_below_surface" | "bbox_extends_into" | "scale_diagonal"
                  | "scale_ratio" | "no_material_slots" | "near_plane"
                  | "inside_bbox" | "no_ground_below" | "no_light_sources"
                  | "energy_zero" | "off_camera" | "zero_dimensions" ;
kv_pair       = identifier "=" ( number | name | vec3 | "true" | "false" ) ;

(* Tier 2 — Visual *)
comp          = "COMP" SP "thirds=" float SP vis_total SP "balance=" float
                SP "depth=" depth_str { SP "edge:[" name_list "]" } ;
ray           = "RAY" SP int "x" int SP coverage_list ;
mview         = "MVIEW" SP name ":" SP coverage_list ;

(* Tier 3 — Physical *)
lit           = "LIT" SP name arrow name SP "@" angle "°" SP "i=" float
                { SP "eff=" float } { SP "raw=" float } { SP "shadow:" name_list } ;
shad          = "SHAD" SP name arrow name SP pct
                { SP "casters:" name_list } { SP contact_or_gap } ;
mat           = "MAT" SP name ":" SP appearance { SP "--" SP note } ;
world         = "WORLD" SP ( "bg=" vec3 SP "strength=" float
              | "hdri" SP "strength=" float ) ;
harmony       = "HARMONY" SP "types=" name SP "temp=" harmony_temp ;
harmony_temp  = "warm" | "cool" | "neutral" | "mixed" ;
palette       = "PALETTE" SP { "lum=" float SP } name { SP name } ;
phys          = "PHYS" SP name SP phys_type SP "mass=" float "kg"
                { SP "vel=" vec3 } { SP "sleeping" } ;
contact       = "CONTACT" SP name "<>" name SP "normal=" vec3
                SP "force=" float "N" SP "surface=" name ;
snd           = "SND" SP name SP "type=" snd_type SP "vol=" float
                SP "dist=" float "m" SP "dir=" direction SP "occ=" float ;

(* Tier 4 — Semantic *)
hier          = "HIER" SP name { SP ">" SP name } ;
grp           = "GRP" SP name ":" SP name_csv ;

(* Tier 5 — Temporal *)
anim          = "ANIM" SP name SP "action=" name SP "frame=" int "/" int
                SP ( "playing" | "stopped" ) ;
delta         = "DELTA" SP free_text ;      (* only emitted when diffing two perceptions *)

(* Primitives *)
free_text     = { any_char } ;
name          = identifier | quoted_string ;
identifier    = ( letter | digit | "_" | "-" | "." ) { letter | digit | "_" | "-" | "." } ;
quoted_string = '"' { any_char - '"' } '"' ;
vec3          = "[" number "," number "," number "]" ;
float         = [ "-" ] digit { digit } [ "." digit { digit } ] ;
int           = [ "-" ] digit { digit } ;
number        = float ;
pct           = ( float | int ) "%" ;
dist          = float "m" ;
focal         = ( float | int ) "mm" ;
energy        = ( float | int ) "W" ;
angle         = float | int ;
depth         = float "m" ;

arrow         = "->" | "\u2192" ;
light_type    = "POINT" | "SUN" | "SPOT" | "AREA" ;
area_shape    = "square" | "rectangle" | "disk" | "ellipse" ;
phys_type     = "static" | "dynamic" | "kinematic" ;
snd_type      = "ambient" | "point" | "directional" ;
quadrant      = "top-left" | "top-center" | "top-right"
              | "mid-left" | "mid-center" | "mid-right"
              | "bot-left" | "bot-center" | "bot-right" ;
direction     = "left" | "right" | "behind" | "in_front"
              | "above" | "below" | compound_dir ;
vertical      = "same_level" | "above" | "below" ;
face          = "face=" ( "+X" | "-X" | "+Y" | "-Y" | "+Z" | "-Z" ) ;
occ           = "occ=" pct ;
lum           = "lum=" float ;
dim           = "dim=" vec3 ;
top           = "top=" float ;   (* AABB max Z — the surface you'd place things ON *)
src           = "src=" name ;    (* semantic source name for hierarchy children, e.g. Sketchfab model name *)
rot           = "rot=" vec3 ;    (* euler degrees, only emitted when any component > 1° *)
facing        = "facing=" compass_dir ;
zone          = "zone=" identifier ;
compass_dir   = "N" | "NE" | "E" | "SE" | "S" | "SW" | "W" | "NW" ;
flipped_normals = "flipped_normals=" pct ;
non_manifold  = "non_manifold=" int ;
inside        = "inside=" name ;
contains_list = "contains:[" name_list "]" ;
contact_or_gap = "contact" | "gap=" float "m" ;
depth_str     = int "/" int ;
vis_total     = int "/" int "_visible" ;
name_list     = name { "," name } ;
name_csv      = name { "," SP name } ;
coverage_list = { name "=" pct SP } [ "empty=" pct ] ;
appearance    = { any_char - "--" - LF } ;
note          = { any_char - LF } ;
description   = { any_char - LF } ;
SP            = " " { " " } ;
LF            = "\n" | "\r\n" ;
```

---

## Parsing Notes

- Line type is determined by the first token (prefix). Unknown prefixes should be ignored (forward compatibility).
- The arrow in REL, LIT, and SHAD can be either `->` or `→` (U+2192). Parsers must accept both.
- Optional fields in OBJ, REL, SHAD lines are identified by their prefix (`face=`, `lum=`, `casters:`, etc.).
- Material properties in OBJ use parentheses: `MaterialName(key=val,key=val)` or `MaterialName(textured)`.
- The `--` separator in MAT lines separates appearance from notes. Only the first `--` is significant.
- RAY coverage entries are space-separated `Name=N%` pairs. The `empty=N%` entry is always last if present.
- MVIEW lines use a colon after the view name, followed by coverage pairs.
- HIER chains use ` > ` (space-angle bracket-space) as separator.
- GRP uses `: ` (colon-space) after the group name, then comma-space-separated member names.
- CONTACT uses `<>` (no spaces) between the two object names.
- LIT source name can be prefixed with `EMIT:` for emissive mesh objects acting as light sources (e.g., `EMIT:LightBulb`).
- CONTAIN lines use ` contains ` (with spaces) as separator between outer and inner object names.
- Material on OBJ lines uses RGB-derived color names for solid-color materials: `warm_brown(rough=0.75)`. Color names are lowercase with underscores.
- `lum=` on OBJ lines is the rendered luminance on a 0.0-1.0 scale.
- `PALETTE` colors are space-separated lowercase color names with underscores.
- `SPATIAL` lines use space-separated `key=value` pairs after the fact type. Values can be numbers, strings, Vec3, or booleans.
- `dim=` on OBJ lines uses Vec3 format `[w,h,d]` for world-space bounding box dimensions in meters.
- `aabb_overlap=` on REL lines is world-space AABB intersection volume as % of smaller object. Camera-independent.
- `transparent` on OBJ lines is a bare flag (no value). Indicates material transmission > 0.5.
- `has_uv` and `no_uv` on OBJ lines are bare flags indicating UV layer presence.
- `flipped_normals=` and `non_manifold=` on OBJ lines are mesh quality metrics, only emitted for objects with >2% screen coverage.
- `top=` on OBJ lines is the AABB max Z in world space — the height you'd place objects ON. Eliminates the need to compute `position.z + dim.z/2`.
- `src=` on OBJ lines is the semantic source name for hierarchy children (e.g. Sketchfab model name). Helps identify "Object_4.002" as part of "Cassidy Dinning Chair". Only emitted for objects with a meaningful parent name.
- `rot=` on OBJ lines uses Vec3 format `[rx,ry,rz]` for euler rotation in degrees. Only emitted when any rotation component exceeds 1°.
- `facing=` on OBJ lines is an objective compass label (N/NE/E/SE/S/SW/W/NW) derived deterministically from the object's Z-rotation. Only emitted when `rot=` is present.
- `zone=` on OBJ lines is a user-defined spatial zone tag. Zones are scene-specific (not hardcoded) and defined via custom properties or scene metadata. Absent when no zones are defined.
- `VERIFY` lines are only emitted after modifying tool calls, and only on failure. They report mechanical failures where a tool reported success but the mesh didn't actually change. Format: `VERIFY FAIL ObjName reason`.
- OBJ positions always use mesh AABB center `(aabb_min + aabb_max) / 2` in world space, never the parent empty's origin. This ensures correct positions for Sketchfab imports and other deep hierarchies.
