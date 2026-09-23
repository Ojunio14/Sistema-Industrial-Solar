class_name PlanetTerrainSample
extends RefCounted
## Caller-owned reusable output, one per mesh job. Never mutable query state in
## the terrain/geology authorities; no object allocation per vertex.
var terrain := Vector4.ZERO
var geology := Vector4.ZERO
