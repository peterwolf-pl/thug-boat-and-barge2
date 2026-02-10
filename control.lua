
-- === Tagboat embark/disembark helpers (stable) ===
local function ensure_global_schema()
  if not global then global = {} end
  global.tagboat = global.tagboat or {}
  global.tagboat.decks = global.tagboat.decks or {} -- [surface_index][unit_number] = {tiles={}, center={}, radius=number}
end

local function get_decks(surface_index)
  ensure_global_schema()
  global.tagboat.decks[surface_index] = global.tagboat.decks[surface_index] or {}
  return global.tagboat.decks[surface_index]
end

local function is_water_tile(tile)
  if not (tile and tile.valid) then return false end
  local name = tile.name or ""
  if name:find("water", 1, true) or name:find("deep", 1, true) then return true end
  local proto = tile.prototype
  if proto and proto.collision_mask then
    for _, layer in pairs(proto.collision_mask) do
      if layer == "water-tile" then return true end
    end
  end
  return false
end

local function build_deck_ring(surface, center, radius, deck_tile_name)
  if not (surface and surface.valid) then return nil end
  local tiles_to_set, original_tiles = {}, {}
  local cx, cy = center.x, center.y
  local r = radius or 4

  for dx = -r, r do
    for dy = -r, r do
      local dist2 = dx*dx + dy*dy
      if dist2 <= (r*r + 0.25) and dist2 >= 4.0 then -- >=2 tiles away: DO NOT touch water under the boat
        -- also skip the immediate 3x3 around center to avoid touching boat footprint
        if not (math.abs(dx) <= 1 and math.abs(dy) <= 1) then
          local tile_pos = {x = math.floor(cx + dx), y = math.floor(cy + dy)}
          local tile = surface.get_tile(tile_pos)
          if is_water_tile(tile) then
            table.insert(original_tiles, {name = tile.name, position = {x = tile.position.x, y = tile.position.y}})
            table.insert(tiles_to_set, {name = deck_tile_name, position = {x = tile.position.x, y = tile.position.y}})
          end
        end
      end
    end
  end

  if #tiles_to_set == 0 then return nil end
  surface.set_tiles(tiles_to_set, true, true, true, true)
  return original_tiles
end

local function any_character_near(surface, center, radius)
  if not (surface and surface.valid and center) then return false end
  local r = (radius or 4) + 1
  local area = {{center.x - r, center.y - r}, {center.x + r, center.y + r}}
  local chars = surface.find_entities_filtered{area = area, type = "character"}
  return chars and #chars > 0
end

local function cleanup_decks()
  ensure_global_schema()
  if not game then return end
  for surface_index, per_surface in pairs(global.tagboat.decks) do
    local surface = game.surfaces[surface_index]
    if surface and surface.valid then
      for unit, rec in pairs(per_surface) do
        if not any_character_near(surface, rec.center, rec.radius) then
          local restore = {}
          for _, t in pairs(rec.tiles or {}) do
            if t and t.name and t.position then
              table.insert(restore, {name = t.name, position = t.position})
            end
          end
          if #restore > 0 then
            surface.set_tiles(restore, true, true, true, true)
          end
          per_surface[unit] = nil
        end
      end
    else
      global.tagboat.decks[surface_index] = nil
    end
  end
end

local function force_tagboat_disembark(player, boat)
  if not (player and player.valid and player.character) then return false end
  if not (boat and boat.valid) then return false end
  local surface = boat.surface
  if not (surface and surface.valid) then return false end

  -- 1) Try land first
  local land_pos = surface.find_non_colliding_position("character", boat.position, 160, 1, true)
  if land_pos then
    player.teleport(land_pos, surface)
    player.driving = false
    return true
  end

  -- 2) No land: create a small ring-deck (landfill tiles) AROUND the boat, not under it
  local decks = get_decks(surface.index)
  local unit = boat.unit_number or 0
  local rec = decks[unit]
  local deck_tile = "landfill"
  local radius = 4

  if not rec then
    local originals = build_deck_ring(surface, boat.position, radius, deck_tile)
    if not originals then return false end
    rec = {tiles = originals, center = {x = boat.position.x, y = boat.position.y}, radius = radius, created_tick = game.tick}
    decks[unit] = rec
  else
    rec.center = {x = boat.position.x, y = boat.position.y}
  end

  -- Place player on the ring (avoid colliding with the boat)
  local candidates = {
    {x = boat.position.x + 3.0, y = boat.position.y},
    {x = boat.position.x - 3.0, y = boat.position.y},
    {x = boat.position.x, y = boat.position.y + 3.0},
    {x = boat.position.x, y = boat.position.y - 3.0},
    {x = boat.position.x + 2.5, y = boat.position.y + 2.5},
    {x = boat.position.x - 2.5, y = boat.position.y - 2.5},
    {x = boat.position.x + 2.5, y = boat.position.y - 2.5},
    {x = boat.position.x - 2.5, y = boat.position.y + 2.5},
  }
  for _, p in pairs(candidates) do
    local pos = surface.find_non_colliding_position("character", p, 10, 0.5, true)
    if pos then
      player.teleport(pos, surface)
      player.driving = false
      return true
    end
  end

  return false
end

local function try_tagboat_embark(player)
  if not (player and player.valid and player.character) then return false end
  local surface = player.surface
  if not (surface and surface.valid) then return false end
  if player.vehicle and player.vehicle.valid then return true end

  local pos = player.position
  local boats = surface.find_entities_filtered{name = "towship-tagboat", position = pos, radius = 8}
  if not boats or #boats == 0 then
    return false
  end

  -- pick nearest free boat
  local best, best_d2 = nil, nil
  for _, b in pairs(boats) do
    if b and b.valid and (not b.get_driver()) then
      local dx = (b.position.x - pos.x)
      local dy = (b.position.y - pos.y)
      local d2 = dx*dx + dy*dy
      if not best_d2 or d2 < best_d2 then
        best, best_d2 = b, d2
      end
    end
  end
  if not (best and best.valid) then return false end

  -- put the player in as driver
  best.set_driver(player)
  return player.vehicle and player.vehicle.valid
end



-- === Deck disembark support ===
local function ensure_tagboat_deck_schema()
  if not global then global = {} end
  global.tagboat_decks = global.tagboat_decks or {} -- [surface_index][boat_unit_number] = {tiles={}, center={}, radius=number}
end

local function is_valid_entity(ent) return ent and ent.valid end
local function is_valid_player(p) return p and p.valid end

local function get_surface_decks(surface_index)
  ensure_tagboat_deck_schema()
  global.tagboat_decks[surface_index] = global.tagboat_decks[surface_index] or {}
  return global.tagboat_decks[surface_index]
end

local function build_deck_tiles(surface, center, radius, deck_tile_name)
  if not surface then return nil end
  local tiles_to_set, original_tiles = {}, {}
  local cx, cy = center.x, center.y
  local r = radius or 2
  for dx = -r, r do
    for dy = -r, r do
      if (dx*dx + dy*dy) <= (r*r + 0.25) then
        local tile_pos = {x = math.floor(cx + dx), y = math.floor(cy + dy)}
        local tile = surface.get_tile(tile_pos)
        if tile and tile.valid then
          if tile.collides_with("water-tile") or (tile.name and (tile.name:find("water") or tile.name:find("deep"))) then
            table.insert(original_tiles, {name = tile.name, position = {x = tile.position.x, y = tile.position.y}})
            table.insert(tiles_to_set, {name = deck_tile_name, position = {x = tile.position.x, y = tile.position.y}})
          end
        end
      end
    end
  end
  if #tiles_to_set == 0 then return nil end
  surface.set_tiles(tiles_to_set, true, true, true, true)
  return original_tiles
end

local function any_character_on_deck(surface, rec)
  if not surface or not rec or not rec.center then return false end
  local c = rec.center
  local r = (rec.radius or 2) + 1
  local area = {{c.x - r, c.y - r}, {c.x + r, c.y + r}}
  local chars = surface.find_entities_filtered{area = area, type = "character"}
  return chars and #chars > 0
end

local function try_disembark_to_land_or_deck(player, vehicle)
  if not is_valid_player(player) or not is_valid_entity(vehicle) then return false end
  local surface = vehicle.surface
  if not (surface and surface.valid) then return false end

  local land_pos = surface.find_non_colliding_position("character", vehicle.position, 64, 1, true)
  if land_pos then
    player.driving = false
    player.teleport(land_pos, surface)
    return true
  end

  local decks = get_surface_decks(surface.index)
  local unit = vehicle.unit_number or 0
  local rec = decks[unit]
  local deck_tile = "landfill"

  if not rec then
    local radius = 2
    local originals = build_deck_tiles(surface, vehicle.position, radius, deck_tile)
    if not originals then return false end
    rec = {tiles = originals, center = {x = vehicle.position.x, y = vehicle.position.y}, radius = radius, created_tick = game.tick}
    decks[unit] = rec
  else
    rec.center = {x = vehicle.position.x, y = vehicle.position.y}
  end

  local deck_pos = surface.find_non_colliding_position("character", vehicle.position, 6, 0.5, true)
  if deck_pos then
    player.driving = false
    player.teleport(deck_pos, surface)
    return true
  end
  return false
end

local function cleanup_unused_decks()
  ensure_tagboat_deck_schema()
  if not game then return end
  for surface_index, per_surface in pairs(global.tagboat_decks) do
    local surface = game.surfaces[surface_index]
    if surface and surface.valid then
      for unit, rec in pairs(per_surface) do
        if not any_character_on_deck(surface, rec) then
          local restore = {}
          for _, t in pairs(rec.tiles or {}) do
            if t and t.name and t.position then
              table.insert(restore, {name = t.name, position = t.position})
            end
          end
          if #restore > 0 then
            surface.set_tiles(restore, true, true, true, true)
          end
          per_surface[unit] = nil
        end
      end
    else
      global.tagboat_decks[surface_index] = nil
    end
  end
end

-- tagboat_towship/control.lua
-- Factorio 2.0: persistent data table is `storage` (not `global`).

-- This version:
--  - does NOT paint any wooden platform tiles to "connect" tug and barge
--  - tows the barge 15 tiles behind the tug
--  - draws only a WHITE towing line (rendering line); no electric/copper wire connections

local TAU = 2 * math.pi
local ATTACH_RADIUS = 12
local TOW_DISTANCE = 15.0

-- NOTE: Vehicles can't have wires, so we spawn 2 hidden electric-pole anchors and connect them with copper wire.
local WIRE_ANCHOR_NAME = "tow-wire-anchor"
local WIRE_ANCHOR_MAX_SEARCH_RADIUS = 2.0 -- for cleanup sanity

-- =========================
-- Required defensive helpers
-- =========================

local function ensure_global()
  storage.tows = storage.tows or {}             -- [towship_unit_number] = barge_unit_number
  storage.wire_anchors = storage.wire_anchors or {} -- [towship_unit_number] = {a=<unit>, b=<unit>}
  storage.render_lines = storage.render_lines or {} -- [towship_unit_number] = {a=id,b=id,c=id,phase=num} (rope segments)
  storage.last_orientation = storage.last_orientation or {}

end

local function safe_entity(ent, expected_name)
  if not (ent and ent.valid) then return nil end
  if expected_name and ent.name ~= expected_name then return nil end
  return ent
end

local function safe_player(index)
  if not (index and game and game.get_player) then return nil end
  local p = game.get_player(index)
  if not (p and p.valid) then return nil end
  return p
end

local function safe_gui(element)
  if element and element.valid then return element end
  return nil
end

-- =========================
-- Geometry helpers
-- =========================

local function clamp(x, lo, hi)
  x = tonumber(x) or 0
  lo = tonumber(lo) or 0
  hi = tonumber(hi) or lo
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function angle_wrap(a)
  a = tonumber(a) or 0
  -- wrap to (-pi, pi]
  a = (a + math.pi) % (TAU) - math.pi
  return a
end

local function angle_diff(a, b)
  -- shortest signed difference a-b in radians
  return angle_wrap((tonumber(a) or 0) - (tonumber(b) or 0))
end

local function lerp(a, b, t)
  t = clamp(t, 0, 1)
  return (tonumber(a) or 0) + ((tonumber(b) or 0) - (tonumber(a) or 0)) * t
end

local function v_lerp(a, b, t)
  return { x = lerp(a.x, b.x, t), y = lerp(a.y, b.y, t) }
end

local function vec_angle(v)
  return math.atan2(v.y or 0, v.x or 0)
end

local function perp(v)
  return { x = -(v.y or 0), y = (v.x or 0) }
end

local function orientation_to_vec(ori)
  ori = tonumber(ori) or 0
  -- Factorio: 0=N, 0.25=E, 0.5=S, 0.75=W
  local a = ori * TAU
  return { x = math.sin(a), y = -math.cos(a) }
end

local function vec_to_orientation(dx, dy)
  -- dx,dy = vector pointing to "front" direction in world coords
  -- 0=N; use atan2(x, -y)
  local a = math.atan2(dx, -dy)
  local o = a / TAU
  if o < 0 then o = o + 1 end
  return o
end

local function v_len(v) return math.sqrt((v.x or 0)^2 + (v.y or 0)^2) end

local function v_norm(v)
  local l = v_len(v)
  if l <= 1e-9 then return {x=0,y=0}, 0 end
  return { x = v.x / l, y = v.y / l }, l
end

local function add(a, b) return { x = (a.x or 0) + (b.x or 0), y = (a.y or 0) + (b.y or 0) } end
local function sub(a, b) return { x = (a.x or 0) - (b.x or 0), y = (a.y or 0) - (b.y or 0) } end
local function mul(v, s) return { x = (v.x or 0) * s, y = (v.y or 0) * s } end

local function entity_radius(ent)
  -- LuaEntityPrototype::radius is defined from the collision box.
  local proto = ent and ent.valid and ent.prototype
  if proto and proto.radius then return proto.radius end
  return 0.7
end

-- =========================
-- Tow helpers
-- =========================

local function get_towship(player)
  local v = player and player.vehicle
  return safe_entity(v, "towship-tagboat")
end

local function find_nearest_barge(surface, position)
  if not (surface and position) then return nil end
  local list = surface.find_entities_filtered{
    name = "wooden-platform-barge",
    position = position,
    radius = ATTACH_RADIUS
  }
  if not (list and #list > 0) then return nil end
  local best, best_d2 = nil, nil
  for _, e in pairs(list) do
    if e and e.valid then
      local dx = e.position.x - position.x
      local dy = e.position.y - position.y
      local d2 = dx*dx + dy*dy
      if (not best_d2) or d2 < best_d2 then best, best_d2 = e, d2 end
    end
  end
  return best
end

local function destroy_anchor(unit_number)
  if not unit_number then return end
  local ent = game.get_entity_by_unit_number(unit_number)
  if ent and ent.valid and ent.name == WIRE_ANCHOR_NAME then
    ent.destroy()
  end
end


local function ensure_render_line(towship, barge)
  ensure_global()
  towship = safe_entity(towship, "towship-tagboat")
  barge = safe_entity(barge, "wooden-platform-barge")
  if not (towship and barge) then return end
  local key = towship.unit_number
  if not key then return end

  -- Migration safety: older versions stored a single render id (number). Convert to table.
  local rec = storage.render_lines[key]
  if type(rec) == "number" then
    local old_obj = rendering.get_object_by_id(rec)
    if old_obj then old_obj.destroy() end
    rec = nil
    storage.render_lines[key] = nil
  end

  local function valid_id(id)
    return id and rendering.get_object_by_id(id) ~= nil
  end

  if type(rec) ~= "table" or not (valid_id(rec.a) and valid_id(rec.b) and valid_id(rec.c)) then
    -- Recreate all 3 segments to represent a flexible rope with two main joints:
    --  stern -> joint_near_tug -> joint_near_barge -> bow
    if type(rec) == "table" then
      local o1 = valid_id(rec.a) and rendering.get_object_by_id(rec.a) or nil
      local o2 = valid_id(rec.b) and rendering.get_object_by_id(rec.b) or nil
      local o3 = valid_id(rec.c) and rendering.get_object_by_id(rec.c) or nil
      if o1 then o1.destroy() end
      if o2 then o2.destroy() end
      if o3 then o3.destroy() end
    end

    local surface = towship.surface
    local common = {
      surface = surface,
      color = {0.55, 0.36, 0.18}, -- rope brown
      width = 3,
      draw_on_ground = false,
      time_to_live = 0
    }

    local o1 = rendering.draw_line{from = towship.position, to = towship.position, surface = common.surface, color = common.color, width = common.width, draw_on_ground = common.draw_on_ground, time_to_live = common.time_to_live}
    local o2 = rendering.draw_line{from = towship.position, to = towship.position, surface = common.surface, color = common.color, width = common.width, draw_on_ground = common.draw_on_ground, time_to_live = common.time_to_live}
    local o3 = rendering.draw_line{from = towship.position, to = towship.position, surface = common.surface, color = common.color, width = common.width, draw_on_ground = common.draw_on_ground, time_to_live = common.time_to_live}

    storage.render_lines[key] = {
      a = o1 and o1.id or nil,
      b = o2 and o2.id or nil,
      c = o3 and o3.id or nil,
      phase = (key % 360) * (TAU / 360) -- stable per-tow randomization
    }
  end
end

local function update_render_line(towship, barge)
  ensure_global()
  towship = safe_entity(towship, "towship-tagboat")
  barge = safe_entity(barge, "wooden-platform-barge")
  if not (towship and barge) then return end

  local key = towship.unit_number
  if not key then return end

  local rec = storage.render_lines[key]
  if type(rec) ~= "table" then return end

  local o1 = rec.a and rendering.get_object_by_id(rec.a) or nil
  local o2 = rec.b and rendering.get_object_by_id(rec.b) or nil
  local o3 = rec.c and rendering.get_object_by_id(rec.c) or nil
  if not (o1 and o2 and o3) then return end

  
-- Attachment points (slightly outside the entities).
-- Endpoints are fixed to tug stern and barge bow; joints are "control points" that respond to steering.
local tug_fwd = orientation_to_vec(towship.orientation or 0)
local stern_pos = sub(towship.position, mul(tug_fwd, entity_radius(towship) + 0.05))

local to_tug = sub(towship.position, barge.position)
local dir_to_tug = v_norm(to_tug)
local bow_pos = add(barge.position, mul(dir_to_tug, entity_radius(barge) + 0.25))

local rope_vec = sub(bow_pos, stern_pos)
local rope_dir, rope_len = v_norm(rope_vec)
if not rope_dir or rope_len <= 0 then return end

-- Angles (requested): barge<->line and line<->tug (both in radians, signed, wrapped).
-- Tug reference: its BACK direction (rope is behind the tug).
local tug_back = mul(tug_fwd, -1)
local a_rope = vec_angle(rope_dir)
local a_tug  = vec_angle(tug_back)
local a_barge = vec_angle(orientation_to_vec(barge.orientation or 0))

rec.angle_tug_rope = angle_diff(a_rope, a_tug)
rec.angle_barge_rope = angle_diff(a_rope, a_barge)

-- Turn rate drives the first joint more strongly than the second.
local tug_ori = (towship.orientation or 0) * TAU
local last_tug_ori = tonumber(rec.last_tug_ori) or tug_ori
local turn = angle_diff(tug_ori, last_tug_ori) -- + = clockwise, - = counter-clockwise (left)
rec.last_tug_ori = tug_ori

-- Estimate tug speed (tiles/tick) to add "slack" under load.
local tug_pos = towship.position
local last_pos = rec.last_tug_pos
local speed = 0
if type(last_pos) == "table" then
  local dp = sub(tug_pos, last_pos)
  speed = v_len(dp) or 0
end
rec.last_tug_pos = { x = tug_pos.x, y = tug_pos.y }

-- Slack + wobble (keeps it from looking like a rigid rod).
local tick = (game and game.tick) or 0
local phase = tonumber(rec.phase) or 0
-- More slack at higher speed, and a bit more with longer ropes.
local base_slack = clamp(rope_len * 0.12 + speed * 0.40, 0.9, 4.5)
local wobble  = math.sin((tick * 0.060) + phase)
local wobble2 = math.sin((tick * 0.049) + phase * 1.7)

-- Steering side factor (scaled small per-tick orientation deltas).
local steer = clamp(turn * 22.0, -1.0, 1.0)

-- Joint distances from endpoints along the rope.
-- joint1 is intentionally VERY close to the tug so the rope bends immediately at the stern.
-- joint2 stays moderately close to the barge so the rope doesn't look like a rigid rod.
local j1_dist = clamp(rope_len * 0.10, 0.35, 2.20)
local j2_dist = clamp(rope_len * 0.22, 1.20, 6.50)

local side_tug = perp(tug_back)
local side_rope = perp(rope_dir)

-- Targets:
--  joint1 is dominated by tug steering (it reacts FIRST).
local j1_target = add(
  add(stern_pos, mul(tug_back, j1_dist)),
  mul(side_tug, base_slack * (1.55 * steer + 0.40 * wobble))
)

--  joint2 follows joint1 and the barge bow (it reacts SECOND).
--  Use the direction from bow to joint1 (chain-following) rather than the instantaneous rope direction.
local dir_bow_to_j1 = v_norm(sub((rec.j1 and rec.j1.x and rec.j1) or j1_target, bow_pos))
if not dir_bow_to_j1 then dir_bow_to_j1 = mul(rope_dir, -1) end
local side_chain = perp(dir_bow_to_j1)

local j2_target = add(
  add(bow_pos, mul(dir_bow_to_j1, j2_dist)),
  mul(side_chain, base_slack * (-0.95 * steer + 0.32 * wobble2))
)

-- Springy follow (adds visible "give" instead of rigid lerp).
local function spring_step(pos, vel, target, k, damp)
  if type(pos) ~= "table" then pos = { x = target.x, y = target.y } end
  if type(vel) ~= "table" then vel = { x = 0, y = 0 } end
  -- acceleration toward target
  local ax = (target.x - pos.x) * k
  local ay = (target.y - pos.y) * k
  vel.x = (vel.x + ax) * damp
  vel.y = (vel.y + ay) * damp
  pos.x = pos.x + vel.x
  pos.y = pos.y + vel.y
  return pos, vel
end

-- Update joints with different stiffness/damping so joint1 leads and joint2 lags.
local j1, j1v = spring_step(rec.j1, rec.j1v, j1_target, 0.22, 0.78)
-- joint2 is slower and heavier.
local j2, j2v = spring_step(rec.j2, rec.j2v, j2_target, 0.12, 0.72)

-- Extra "swing" impulse on joint1 when turning (makes the first hinge visibly articulate).
j1v.x = j1v.x + side_tug.x * (steer * 0.055 * base_slack)
j1v.y = j1v.y + side_tug.y * (steer * 0.055 * base_slack)

-- Store velocities and positions back.
rec.j1 = j1
rec.j2 = j2
rec.j1v = j1v
rec.j2v = j2v

local joint1 = j1
local joint2 = j2


  -- Update the 3 rope segments.
  o1.from = stern_pos
  o1.to   = joint1

  o2.from = joint1
  o2.to   = joint2

  o3.from = joint2
  o3.to   = bow_pos
end

local function destroy_render_line(towship_unit)
  ensure_global()
  local rec = storage.render_lines[towship_unit]
  if type(rec) == "number" then
    local obj = rendering.get_object_by_id(rec)
    if obj then obj.destroy() end
  elseif type(rec) == "table" then
    local o1 = rec.a and rendering.get_object_by_id(rec.a) or nil
    local o2 = rec.b and rendering.get_object_by_id(rec.b) or nil
    local o3 = rec.c and rendering.get_object_by_id(rec.c) or nil
    if o1 then o1.destroy() end
    if o2 then o2.destroy() end
    if o3 then o3.destroy() end
  end
  storage.render_lines[towship_unit] = nil
end

local function ensure_wire_anchors(towship, barge)
  -- NOTE: Legacy name kept for save compatibility.
  -- We no longer create/connect any electric wire anchors; only a white rendering line is used.
  ensure_global()
  towship = safe_entity(towship, "towship-tagboat")
  barge = safe_entity(barge, "wooden-platform-barge")
  if not (towship and barge) then return end

  local key = towship.unit_number
  if not key then return end

  -- If older saves had anchors, destroy them defensively and clear record.
  local rec = storage.wire_anchors and storage.wire_anchors[key] or nil
  if rec then
    destroy_anchor(rec.a)
    destroy_anchor(rec.b)
  end
  if storage.wire_anchors then storage.wire_anchors[key] = nil end

  ensure_render_line(towship, barge)
end

local function update_wire_positions(towship, barge)
  -- Legacy name kept for callers; updates the white rendering line endpoints.
  ensure_global()
  towship = safe_entity(towship, "towship-tagboat")
  barge = safe_entity(barge, "wooden-platform-barge")
  if not (towship and barge) then return end

  ensure_render_line(towship, barge)
  update_render_line(towship, barge)
end

local function detach_pair(towship_unit)
  ensure_global()
  if not towship_unit then return end

  -- Kill wire anchors
  local rec = storage.wire_anchors[towship_unit]
  if rec then
    destroy_anchor(rec.a)
    destroy_anchor(rec.b)
  end
  destroy_render_line(towship_unit)
  storage.wire_anchors[towship_unit] = nil
  storage.tows[towship_unit] = nil
end

-- =========================
-- Init / migration
-- =========================

script.on_init(function()
  ensure_global()
end)

script.on_configuration_changed(function()
  ensure_global()
-- Cleanup legacy tow-wire-anchor entities from older versions (no longer used).
for towship_unit, rec in pairs(storage.wire_anchors or {}) do
  if rec then
    destroy_anchor(rec.a)
    destroy_anchor(rec.b)
  end
  storage.wire_anchors[towship_unit] = nil
end

  -- Defensive cleanup: remove broken entries
  for towship_unit, barge_unit in pairs(storage.tows or {}) do
    local towship = game.get_entity_by_unit_number(towship_unit)
    local barge = game.get_entity_by_unit_number(barge_unit)
    if not (safe_entity(towship, "towship-tagboat") and safe_entity(barge, "wooden-platform-barge")) then
      detach_pair(towship_unit)
    end
  end
end)

-- Prevent entering barge as a vehicle
script.on_event(defines.events.on_player_driving_changed_state, function(event)
  ensure_global()
  local player = safe_player(event.player_index)
  if not player then return end
  local veh = player.vehicle
  if veh and veh.valid and veh.name == "wooden-platform-barge" then
    player.driving = false
    player.print({"", "[Tagboat] Nie można wsiadać do barki."})
  end
end)

-- L: forced disembark (boats are on water; vanilla exit may fail if no solid tile nearby)
script.on_event("tagboat-disembark", function(event)
  ensure_global()
  local player = safe_player(event.player_index)
  if not player then return end
  local veh = player.vehicle
  if not (veh and veh.valid and veh.name == "towship-tagboat") then
    player.print({"", "[Tagboat] Musisz być w towship-tagboat, żeby wysiąść."})
    return
  end

  local surface = veh.surface
  if not (surface and surface.valid) then return end

  -- try to find a nearby valid position for the character
  local char_name = "character"
  if player.character and player.character.valid then
    char_name = player.character.name or "character"
  end

  local pos = surface.find_non_colliding_position(char_name, veh.position, 64, 0.5)
  if not pos then
    player.print({"", "[Tagboat] Brak miejsca do wysiadania w pobliżu. Podpłyń bliżej lądu."})
    return
  end

  -- teleport out and ensure driving is false
  player.teleport(pos, surface)
  player.driving = false
end)

-- J: attach (tow)
script.on_event("tagboat-attach-barge", function(event)
  ensure_global()
  local player = safe_player(event.player_index)
  if not player then return end

  local towship = get_towship(player)
  if not towship then
    player.print({"", "[Tagboat] Musisz być w towship-tagboat, żeby podpiąć barkę."})
    return
  end

  local key = towship.unit_number
  if not key then return end
  if storage.tows[key] then
    player.print({"", "[Tagboat] Już holujesz barkę. Użyj K aby odpiąć."})
    return
  end

  local barge = find_nearest_barge(towship.surface, towship.position)
  if not safe_entity(barge, "wooden-platform-barge") then
    player.print({"", "[Tagboat] Brak barki w zasięgu ", ATTACH_RADIUS, "."})
    return
  end

  storage.tows[key] = barge.unit_number
  ensure_wire_anchors(towship, barge)
  player.print({"", "[Tagboat] Podpięto barkę (J=podłącz, K=odłącz)."})
end)

-- K: detach
script.on_event("tagboat-detach-barge", function(event)
  ensure_global()
  local player = safe_player(event.player_index)
  if not player then return end

  local towship = get_towship(player)
  if not towship then
    player.print({"", "[Tagboat] Musisz być w towship-tagboat, żeby odpiąć barkę."})
    return
  end

  local key = towship.unit_number
  if not key then return end

  if storage.tows[key] then
    detach_pair(key)
    player.print({"", "[Tagboat] Odpięto barkę."})
  else
    player.print({"", "[Tagboat] Nie holujesz żadnej barki."})
  end
end)

-- Main tow loop
script.on_event(defines.events.on_tick, function(_)
  ensure_global()

  local MAX_TOW_ANGLE = math.rad(145)

  local function vec_len(v)
    return math.sqrt(v.x*v.x + v.y*v.y)
  end

  local function vec_norm(v)
    local l = vec_len(v)
    if l < 0.0001 then return {x=0,y=0}, 0 end
    return {x=v.x/l, y=v.y/l}, l
  end

  local function dot(a,b) return a.x*b.x + a.y*b.y end
  local function cross(a,b) return a.x*b.y - a.y*b.x end

  local function angle_between(a,b)
    local na, la = vec_norm(a)
    local nb, lb = vec_norm(b)
    if la < 0.0001 or lb < 0.0001 then return 0 end
    local c = math.max(-1, math.min(1, dot(na, nb)))
    return math.acos(c)
  end

  local function rotate(v, ang)
    local ca = math.cos(ang)
    local sa = math.sin(ang)
    return {x = v.x*ca - v.y*sa, y = v.x*sa + v.y*ca}
  end

  -- Clamp rope direction relative to tug's backward direction (stern joint).
  local function clamp_rope_dir(back_dir, rope_dir)
    local ang = angle_between(back_dir, rope_dir)
    if ang <= MAX_TOW_ANGLE then return rope_dir end
    local s = cross(back_dir, rope_dir)
    local sign = (s >= 0) and 1 or -1
    return rotate(back_dir, sign * MAX_TOW_ANGLE)
  end

  for towship_unit, barge_unit in pairs(storage.tows) do
    local towship = game.get_entity_by_unit_number(towship_unit)
    local barge = game.get_entity_by_unit_number(barge_unit)

    towship = safe_entity(towship, "towship-tagboat")
    barge = safe_entity(barge, "wooden-platform-barge")

    if not (towship and barge) then
      detach_pair(towship_unit)
    else
      local tug_speed = towship.speed or 0
      -- LuaEntity has no angular_velocity; estimate from orientation delta per tick
      local last_o = storage.last_orientation and storage.last_orientation[towship.unit_number] or nil
      local o = towship.orientation or 0
      local d_o = 0
      if last_o ~= nil then
        local diff = o - last_o
        -- wrap to [-0.5, 0.5]
        if diff > 0.5 then diff = diff - 1 end
        if diff < -0.5 then diff = diff + 1 end
        d_o = diff
      end
      if storage.last_orientation then storage.last_orientation[towship.unit_number] = o end
      local turning_in_place = (math.abs(d_o) > 0.002) and (math.abs(tug_speed) < 0.01)


      if not turning_in_place then
        local fwd = orientation_to_vec(towship.orientation or 0)
        local back = {x = -fwd.x, y = -fwd.y}

        local rope_vec = sub(barge.position, towship.position) -- tug -> barge
        local rope_dir, rope_len = vec_norm(rope_vec)

        -- keep rope from swinging past the bow; allow up to ~145° at the stern joint
        rope_dir = clamp_rope_dir(back, rope_dir)

        -- Pull only when taut (slack does nothing)
        if rope_len > (TOW_DISTANCE + 0.05) then
                    -- Compute desired attachment point behind the tug along the rope.
          local desired = add(towship.position, mul(rope_dir, TOW_DISTANCE))
          -- Prevent rope-side pull from instantly yawing the barge:
          -- move the barge mainly along its own forward axis when the rope is at a big angle.
          local b_fwd = orientation_to_vec(barge.orientation or 0)
          local to_desired = sub(desired, barge.position)
          local along = dot(to_desired, b_fwd)
          local move = {x = b_fwd.x * along, y = b_fwd.y * along}
          -- If rope is roughly aligned with barge (<~45°), allow full correction.
          local rope_vs_barge_ang = angle_between(b_fwd, rope_dir)
          local target = desired
          if rope_vs_barge_ang > math.rad(45) then
            target = add(barge.position, move)
          end
          local ok = barge.teleport(target)
          -- Allow the barge to yaw FOLLOWING the tow direction (not rigidly), only when being pulled forward.
          -- This prevents orbiting when the tug turns in place, but lets the barge align while under tension.
          if ok then
            local desired_ang = vec_angle(rope_dir)
            local cur_ang = vec_angle(orientation_to_vec(barge.orientation or 0))
            local diff = angle_diff(desired_ang, cur_ang)
            -- limit rotation per tick (gentle)
            local step = clamp(diff, -0.030, 0.030)
            barge.orientation = ((barge.orientation or 0) + (step / TAU)) % 1
          end

          if not ok then
            detach_pair(towship_unit)
            local driver = towship.get_driver()
            if driver and driver.is_player() then
              driver.print({"", "[Tagboat] Kolizja podczas holowania — wypięto barkę."})
            end
          end
        end
      end

      -- Always update rope visuals
      ensure_wire_anchors(towship, barge)
      update_wire_positions(towship, barge)
    end
  end
end)


-- Cleanup when entities are removed
local function on_removed(event)
  ensure_global()
  local ent = safe_entity(event.entity, nil)
  if not ent then return end

  if ent.name == "towship-tagboat" then
    if ent.unit_number then detach_pair(ent.unit_number) end
  elseif ent.name == "wooden-platform-barge" then
    local dead = ent.unit_number
    if dead and storage.tows then
      for k, v in pairs(storage.tows) do
        if v == dead then detach_pair(k) end
      end
    end
  elseif ent.name == WIRE_ANCHOR_NAME then
    -- If someone manages to remove an anchor, clean any references.
    local dead = ent.unit_number
    if dead and storage.wire_anchors then
      for k, rec in pairs(storage.wire_anchors) do
        if rec and (rec.a == dead or rec.b == dead) then
          detach_pair(k)
        end
      end
    end
  end
end

script.on_event(defines.events.on_entity_died, on_removed)
script.on_event(defines.events.on_player_mined_entity, on_removed)
script.on_event(defines.events.on_robot_mined_entity, on_removed)


-- ===============================
-- TOWING PHYSICS PATCH (SAFE)
-- allows rope bending up to ~145 degrees
-- prevents barge spinning when tug turns in place
-- ===============================

local MAX_TOW_ANGLE = math.rad(145)

local function _vec_len(v)
  return math.sqrt(v.x * v.x + v.y * v.y)
end

local function _angle_between(v1, v2)
  local dot = v1.x * v2.x + v1.y * v2.y
  local l1 = _vec_len(v1)
  local l2 = _vec_len(v2)
  if l1 < 0.0001 or l2 < 0.0001 then return 0 end
  local c = math.max(-1, math.min(1, dot / (l1 * l2)))
  return math.acos(c)
end

local function apply_safe_tow(tug, barge)
  if not (tug and tug.valid and barge and barge.valid) then return end

  local tug_speed = tug.speed or 0
  local ang_vel = tug.angular_velocity or 0

  local tug_dir = {
    x = math.cos(tug.orientation * 2 * math.pi),
    y = math.sin(tug.orientation * 2 * math.pi)
  }

  local rope_vec = {
    x = barge.position.x - tug.position.x,
    y = barge.position.y - tug.position.y
  }

  local rope_angle = _angle_between(tug_dir, rope_vec)

  -- allow rope to bend freely, do not rotate barge
  if rope_angle > MAX_TOW_ANGLE then
    return
  end

  -- turning in place -> no force transfer
  if math.abs(ang_vel) > 0.01 and math.abs(tug_speed) < 0.01 then
    return
  end

  -- linear pull only
  if tug_speed > 0 then
    barge.teleport({
      barge.position.x + rope_vec.x * 0.001 * tug_speed,
      barge.position.y + rope_vec.y * 0.001 * tug_speed
    })
  end
end

script.on_nth_tick(120, function()
  cleanup_unused_decks()
end)

-- K: quick embark into nearest tagboat (helps when vanilla hop-in is finicky)
script.on_event("tagboat-embark", function(event)
  if not event or not event.player_index then return end
  ensure_global()
  local player = safe_player(event.player_index)
  if not player then return end
  if player.vehicle and player.vehicle.valid then return end
  local ok = try_tagboat_embark(player)
  if not ok then
    player.print({"", "[Tagboat] ", "Brak wolnej tagboat w zasięgu 8 (K)."})
  end
end)


script.on_event(defines.events.on_player_driving_changed_state, function(event)
  ensure_global()
  if not event or not event.player_index then return end
  local player = safe_player(event.player_index)
  if not player then return end

  local veh = player.vehicle
  if not (veh and veh.valid) then return end

  -- Block entering the barge as a vehicle (but NEVER interfere with tagboat / other vehicles)
  if veh.name == "wooden-platform-barge" then
    player.driving = false
    player.print({"", "[Tagboat] ", "Nie można wsiadać do barki."})
    return
  end
end)
