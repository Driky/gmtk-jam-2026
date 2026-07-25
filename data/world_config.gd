## World dimensions & buffer ranges shared by Terrain and world generation.
## Owning doc: docs/systems/world-gen.md
class_name WorldConfig

const WORLD_WIDTH := 200 ## Includes both buffer zones.
const WORLD_HEIGHT := 1200
const BUFFER_WIDTH := 50
const PLAYABLE_X_BEGIN := BUFFER_WIDTH
const PLAYABLE_X_END := WORLD_WIDTH - BUFFER_WIDTH ## Exclusive.


static func is_in_world(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < WORLD_WIDTH and pos.y >= 0 and pos.y < WORLD_HEIGHT


static func is_in_buffer(pos: Vector2i) -> bool:
	return pos.x < PLAYABLE_X_BEGIN or pos.x >= PLAYABLE_X_END
