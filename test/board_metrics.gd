class_name BoardMetrics
extends Object

const SQUARE_SIZE := 48.0
const PLACEMENT_GAP := 0.5
const ROUTE_CELL_SIZE := 14.0
const ROUTE_CLEARANCE := 12.0
const ROUTE_SEARCH_MARGIN := 180.0
const ROUTE_MAX_NODES := 12_000
const DOT_SPACING := 13.0
const DOT_RADIUS := 2.2
const DOT_EDGE_GAP := 3.0
const RIVER_HALF_WIDTH := 11.0
const ROUTE_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]

static func square_rect(center: Vector2) -> Rect2:
	var top_left := center - Vector2.ONE * (SQUARE_SIZE / 2.0)
	return Rect2(top_left, Vector2.ONE * SQUARE_SIZE)

static func world_to_cell(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / ROUTE_CELL_SIZE),
		floori(position.y / ROUTE_CELL_SIZE)
	)

static func cell_to_world(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * ROUTE_CELL_SIZE
