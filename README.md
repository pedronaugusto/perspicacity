# Perspicacity

A compact format for representing 3D scenes to LLMs. Organizes scene data into typed structs — object identity, spatial relationships, lighting, materials, and change tracking — serialized as a token-efficient text DSL (`.picacia`).

Built for LLMs controlling 3D editors over MCP. Currently implemented in [BlenderWeave](https://github.com/pedronaugusto/blender-weave).

## The Problem

An LLM controlling a 3D editor needs to know *what's in the scene, where things are, how they're lit, and what changed*. Screenshots are expensive, lossy, and can't be queried. JSON scene dumps are bloated. Raw geometry is useless for reasoning.

## The Format

Perspicacity defines a typed struct (`ScenePerception`) that captures what an observer perceives, organized into tiers from basic identity to temporal changes. It serializes to a **text DSL** (`.picacia`) — compact, line-oriented, one prefix per line type.

A typical 20-object scene is ~40 lines / ~1500 tokens.

## Tiers

| Tier | Name | What It Answers | Line Types |
|------|------|----------------|------------|
| 0 | Identity | What exists | `CAM` `LIGHT` `OBJ` `SGROUP` `ASSEMBLY` `FOCUS` `SCENE` |
| 1 | Spatial | Where things are | `REL` `VERIFY` `CONTAIN` `SPATIAL` |
| 2 | Visual | What the camera sees | `COMP` `RAY` `MVIEW` |
| 3 | Physical | Light, materials, physics | `LIT` `SHAD` `MAT` `HARMONY` `PALETTE` `WORLD` `PHYS` `CONTACT` |
| 4 | Semantic | What things mean | `HIER` `GRP` |
| 5 | Temporal | What's changing | `ANIM` `DELTA` |

Each tier builds on the previous. A tier-0 perception is valid on its own. Higher tiers add richer detail. Consumers request the tiers they need.

## Example

```
SCENE 5 objects 1 lights 500W BLENDER_EEVEE ground_z=-1.0
CAM Camera [0,0,5] 50mm
WORLD bg=[0.05,0.05,0.05] strength=1

LIGHT Key POINT 500W [1,1,1] [3,2,4]

OBJ Cube [0,0,0] 15% mid-center d=5m Default(textured) dim=[1,1,1]m facing=N face=+Z lum=0.7
OBJ Floor [0,0,-1] 35% bot-center d=5.8m Concrete(textured) dim=[10,10,0.1]m

REL Cube→Floor 1m below contact
LIT Key→Cube @42° i=0.85
SHAD Key→Floor 12% casters:Cube contact
MAT Default: light grey matte
MAT Concrete: textured concrete
HARMONY types=matte(50%)+concrete(50%) temp=neutral

SPATIAL Cube no_ground_below

HIER Cube > Scene
GRP Props: Cube
PHYS Cube dynamic mass=10kg

RAY 12x12 Cube=15% Floor=35% empty=50%
```

Every line starts with a prefix tag. Objects are depth-sorted front-to-back. Directions are camera-relative.

## Spec

| Document | What's in it |
|----------|-------------|
| [spec/v1.md](spec/v1.md) | Full v1 spec: tiers, struct definitions, all line types, design rationale |
| [spec/data-model.md](spec/data-model.md) | Field tables for every struct with types and examples |
| [spec/text-format.md](spec/text-format.md) | Formal grammar (EBNF), encoding rules, line ordering |

## Skills

`skills/perspicacity/SKILL.md` is the DSL reference for AI consumption — designed to be loaded as a Claude Code skill for real-time scene reasoning.

## Reference Implementations

### Python

Zero-dependency Python in `reference/python/`:

| File | What it does |
|------|-------------|
| `perception.py` | Dataclasses for all structs |
| `serialize.py` | `to_text()` and `from_text()` — round-trip between structs and `.picacia` |
| `test_serialize.py` | 60 tests: fixture round-trips, individual line parsing, edge cases |

```
cd reference/python && pytest test_serialize.py -v
```

### Zig

Zero-dependency Zig (0.13+) in `reference/zig/`:

| File | What it does |
|------|-------------|
| `perception.zig` | Struct definitions |
| `serialize.zig` | `toText()` — struct to `.picacia` |
| `parse.zig` | `fromText()` — `.picacia` to struct |
| `test_serialize.zig` | Round-trip tests against shared fixtures |

```
cd reference/zig && zig build test
```

## Test Fixtures

Shared by all reference implementations:

| File | Purpose |
|------|---------|
| `test-fixtures/minimal.picacia` | 3 objects, 1 light — tiers 0-3 |
| `test-fixtures/full.picacia` | 11 objects, 2 lights — all tiers |

## Implementations

| Project | Role |
|---------|------|
| [BlenderWeave](https://github.com/pedronaugusto/blender-weave) | Blender MCP server — auto-attaches perception to every command |

## License

CC0-1.0 (public domain dedication)
