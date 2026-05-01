## map_setup.gd
## Программная расстановка тайлов для level_1.
##
## Логика по гайду Tiny Swords:
##   1. BG_Color      — заливка всего экрана водой (source 0, tile (0,0))
##   2. Water_Foam    — пена по периметру земли, разные стартовые кадры
##   3. Flat_Ground   — основная земля (ряды 4-5 атласа = тайлы с коллизиями)
##   4. Shadow_1      — копия Elevated_Ground_1 смещённая на тайл вниз
##   5. Elevated_Ground_1 — первый уровень возвышения
##   6. Shadow_2 / Elevated_Ground_2 — второй уровень (аналогично)
##   7. Stairs        — лестницы между уровнями
##
## Использование: прикрепи к node level_1 или вызови generate_map() вручную.

class_name MapSetup
extends Node

# --- Ссылки на слои (заполняются через @export или @onready) ---
@export var bg_color_layer: TileMapLayer
@export var water_foam_layer: TileMapLayer
@export var flat_ground_layer: TileMapLayer
@export var shadow_1_layer: TileMapLayer
@export var elevated_ground_1_layer: TileMapLayer
@export var shadow_2_layer: TileMapLayer
@export var elevated_ground_2_layer: TileMapLayer
@export var stairs_layer: TileMapLayer

# --- Параметры карты ---
## Размер в тайлах
@export var map_width: int = 20
@export var map_height: int = 15
## Отступ от края для воды (тайлов)
@export var water_border: int = 2

# Константы атласа Tilemap_color (ряды 4-5 = тайлы с коллизиями)
const SOURCE_ID := 0

# Тайлы flat ground (ряд 4 атласа color1)
# col: 0=corner_tl, 1=edge_l/cliff, 2=top_mid, 3=edge_r/cliff,
#      4=inner_mid, 5,6,7=fill, 8=corner_tr
# (конкретные координаты подбираются по визуальному атласу в редакторе)
const FILL_TILE     := Vector2i(4, 4)  # Центральный заполняющий тайл
const TOP_TILE      := Vector2i(4, 3)  # Верхний декоративный тайл
const CLIFF_L_TILE  := Vector2i(1, 4)  # Левая стена (с cliff-коллизией)
const CLIFF_R_TILE  := Vector2i(3, 4)  # Правая стена (с cliff-коллизией)

# Тайлы Shadow (3x3 grid из Shadow.png)
const SHADOW_FILL   := Vector2i(1, 1)  # Центр тени
const SHADOW_CORNER := Vector2i(0, 0)  # Угол тени

func _ready() -> void:
generate_map()

## Генерирует базовую карту программно.
## Вызывай повторно после изменения параметров.
func generate_map() -> void:
_fill_bg()
_place_flat_ground()
_place_water_foam()
_place_elevation_1()
_place_elevation_2()

# --- Приватные методы ---

func _fill_bg() -> void:
if not bg_color_layer:
return
# Заливаем весь экран + border тайлом воды
for x in range(-water_border, map_width + water_border):
for y in range(-water_border, map_height + water_border):
bg_color_layer.set_cell(Vector2i(x, y), SOURCE_ID, Vector2i(0, 0))

func _place_flat_ground() -> void:
if not flat_ground_layer:
return
# Центральный прямоугольник земли
var ground_rect := Rect2i(2, 3, map_width - 4, map_height - 6)
for x in range(ground_rect.position.x, ground_rect.end.x):
for y in range(ground_rect.position.y, ground_rect.end.y):
flat_ground_layer.set_cell(Vector2i(x, y), SOURCE_ID, FILL_TILE)

func _place_water_foam() -> void:
if not water_foam_layer:
return
# Пена по верхнему краю земли с разными стартовыми кадрами анимации.
# Water_Foam атлас: animation_frames_count = 4, поэтому кадры 0-3.
var ground_top_y := 3
var foam_source_id := 0
var foam_tile := Vector2i(0, 0)
for x in range(2, map_width - 2):
var cell := Vector2i(x, ground_top_y - 1)
water_foam_layer.set_cell(cell, foam_source_id, foam_tile)
# Разные стартовые кадры по X для разброса анимации
var alt_tile := (x % 4)
water_foam_layer.set_cell(cell, foam_source_id, Vector2i(0, 0), alt_tile)

func _place_elevation_1() -> void:
if not elevated_ground_1_layer or not shadow_1_layer:
return
# Возвышение 1: прямоугольник внутри flat_ground
var elev_rect := Rect2i(4, 1, map_width - 8, 3)
for x in range(elev_rect.position.x, elev_rect.end.x):
for y in range(elev_rect.position.y, elev_rect.end.y):
elevated_ground_1_layer.set_cell(Vector2i(x, y), SOURCE_ID, FILL_TILE)
# Shadow: на 1 тайл ниже (слой уже смещён +64px, поэтому
# tile координата та же, что и у elevated)
shadow_1_layer.set_cell(Vector2i(x, y), SOURCE_ID, SHADOW_FILL)

func _place_elevation_2() -> void:
if not elevated_ground_2_layer or not shadow_2_layer:
return
# Возвышение 2: ещё выше и уже
var elev_rect := Rect2i(6, -1, map_width - 12, 2)
for x in range(elev_rect.position.x, elev_rect.end.x):
for y in range(elev_rect.position.y, elev_rect.end.y):
elevated_ground_2_layer.set_cell(Vector2i(x, y), SOURCE_ID, FILL_TILE)
shadow_2_layer.set_cell(Vector2i(x, y), SOURCE_ID, SHADOW_FILL)
