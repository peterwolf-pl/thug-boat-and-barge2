-- tagboat_towship/data.lua
-- Factorio 2.0
local util = require("util")

local function deepcopy(x) return table.deepcopy(x) end

-- Keybinds:
data:extend({
  { type = "custom-input", name = "tagboat-attach-barge", key_sequence = "J", consuming = "none" },
  { type = "custom-input", name = "tagboat-detach-barge", key_sequence = "K", consuming = "none" }
})

local empty_sprite = {
  filename = "__core__/graphics/empty.png",
  priority = "extra-high",
  width = 1,
  height = 1,
  direction_count = 1
}

-- Barge animation using 256 directions, stored as 16 files (4x4 each)
local function make_barge_animation()
  local filenames = {}
  for i = 1, 16 do
    filenames[#filenames+1] = string.format("__tagboat_barge_graphics__/graphics/barge4/barge_%02d.png", i)
  end

  return {
    direction_count = 256,
    line_length = 4,
    lines_per_file = 4,
    filenames = filenames,
    width = 474,
    height = 458,
    shift = util.by_pixel(0, -6),
    priority = "high"
  }
end

-- 1) Towship-tagboat = clone of cargo-ships "indep-boat" (car)
  do
  local base = data.raw["car"] and data.raw["car"]["indep-boat"]
  local base_item = (data.raw["item-with-entity-data"] and data.raw["item-with-entity-data"]["boat"])
                 or (data.raw["item"] and data.raw["item"]["boat"])
  local base_recipe = data.raw["recipe"] and data.raw["recipe"]["boat"]

  if base and base_item and base_recipe then
    local tug = deepcopy(base)
    tug.name = "towship-tagboat"
    tug.flags = tug.flags or {}
    table.insert(tug.flags, "get-by-unit-number")
    tug.minable = tug.minable or {}
    tug.minable.result = "towship-tagboat"
    tug.allow_passengers = true
    local function make_tug_animation()
      local filenames = {}
      for i = 1, 16 do
        filenames[#filenames + 1] = string.format("__tagboat_barge_graphics__/graphics/tugboat/tug_%02d.png", i)
      end

      return {
        direction_count = 256,
        frame_count = 1,
        line_length = 4,
        lines_per_file = 4,
        filenames = filenames,
        width = 474,
        height = 458,
        shift = util.by_pixel(0, -6),
        priority = "high"
      }
    end

    tug.animation = make_tug_animation()
    tug.turret_animation = empty_sprite

    -- Use icon from graphics mod
    tug.icons = {
      {
        icon = "__tagboat_barge_graphics__/graphics/icons/tugboat.png",
        icon_size = 64
      }
    }
    tug.icon = nil
    tug.icon_size = nil
    tug.icon_mipmaps = nil

    local tug_item = deepcopy(base_item)
    tug_item.name = "towship-tagboat"
    tug_item.place_result = "towship-tagboat"
    tug_item.icons = {
      {
        icon = "__tagboat_barge_graphics__/graphics/icons/tugboat.png",
        icon_size = 64
      }
    }
    tug_item.icon = nil
    tug_item.icon_size = nil
    tug_item.icon_mipmaps = nil

    local tug_recipe = deepcopy(base_recipe)
    tug_recipe.name = "towship-tagboat"

    -- Make sure it is craftable without relying on upstream tech unlocks
    tug_recipe.enabled = true

    -- Ensure item is visible in crafting/inventory groups
    tug_item.subgroup = tug_item.subgroup or "transport"
    tug_item.order = tug_item.order or "b[towship-tagboat]"

    -- Ensure Factorio 2.0 (and the quality mod recycling pass) always sees concrete results.
    -- Some base recipes use normal/expensive variants; in that case top-level `result` is ignored.
    local function force_recipe_result(r, item_name)
      r.result = nil
      r.result_count = nil
      r.results = { { type = "item", name = item_name, amount = 1 } }
    end

    if tug_recipe.normal or tug_recipe.expensive then
      if tug_recipe.normal then force_recipe_result(tug_recipe.normal, "towship-tagboat") end
      if tug_recipe.expensive then force_recipe_result(tug_recipe.expensive, "towship-tagboat") end
      -- Keep variants, but also set a safe top-level results for mods that scan only root.
      force_recipe_result(tug_recipe, "towship-tagboat")
    else
      force_recipe_result(tug_recipe, "towship-tagboat")
    end


    data:extend({ tug, tug_item, tug_recipe })
  else
    log("[tagboat_towship] Missing prototypes: car.indep-boat or item/recipe boat (cargo-ships).")
  end
end

-- 2) Wooden platform -> floating barge entity (car) that paints wooden-platform tiles under itself
do
  local base = data.raw["car"] and data.raw["car"]["indep-boat"]
  local wp_item = data.raw["item"] and data.raw["item"]["wooden-platform"]
  local wp_recipe = data.raw["recipe"] and data.raw["recipe"]["wooden-platform"]

  if base and wp_item and wp_recipe then
    local barge = deepcopy(base)
    barge.name = "wooden-platform-barge"
    barge.minable = barge.minable or {}
    barge.minable.result = "wooden-platform"
    barge.allow_passengers = false

    -- Icon for barge entity (map, debug etc)
    barge.icons = {
      {
        icon = "__tagboat_barge_graphics__/graphics/icons/barge.png",
        icon_size = 64
      }
    }
    barge.icon = nil
    barge.icon_size = nil
    barge.icon_mipmaps = nil

    -- Make it feel like a heavy barge
    barge.weight = (barge.weight or 1000) * 3.0
    barge.friction_force = (barge.friction_force or 0.01) * 0.45
    barge.braking_force = (barge.braking_force or 0.1) * 0.45
    barge.max_speed = math.min(barge.max_speed or 0.2, 0.10)

    -- Replace graphics with barge prerendered animation
    barge.animation = make_barge_animation()
    barge.turret_animation = empty_sprite
    barge.working_sound = nil

    -- Barge is always towed, so it should never require fuel / energy
    barge.burner = nil
    barge.consumption = "0kW"
    barge.effectivity = 0

    data:extend({ barge })


    -- Provide a placeable item + recipe so the barge is available in build menus
    local barge_item = {
      type = "item-with-entity-data",
      name = "wooden-platform-barge",
      place_result = "wooden-platform-barge",
      stack_size = 444,
      subgroup = "transport",
      order = "b[wooden-platform-barge]",
      icons = {
        {
          icon = "__tagboat_barge_graphics__/graphics/icons/barge.png",
          icon_size = 64
        }
      }
    }

    local barge_recipe = {
      type = "recipe",
      name = "wooden-platform-barge",
      enabled = true,
      ingredients = { { type = "item", name = "wooden-platform", amount = 1 } },
      results = { { type = "item", name = "wooden-platform-barge", amount = 1 } }
    }

    data:extend({ barge_item, barge_recipe })
  else
    log("[tagboat_towship] Missing prototypes: car.indep-boat (cargo-ships) and item/recipe wooden-platform (wooden_platform).")
  end
end

-- 3) Hidden tow wire anchors (electric-pole) to render a real copper wire between tug and barge
do
  local base = data.raw["electric-pole"] and data.raw["electric-pole"]["small-electric-pole"]
  if base then
    local anchor = deepcopy(base)
    anchor.name = "tow-wire-anchor"

    anchor.icon = base.icon
    anchor.icon_size = base.icon_size
    anchor.icon_mipmaps = base.icon_mipmaps

    anchor.flags = anchor.flags or {}
    table.insert(anchor.flags, "placeable-off-grid")
    table.insert(anchor.flags, "not-on-map")
    table.insert(anchor.flags, "not-blueprintable")
    table.insert(anchor.flags, "not-deconstructable")
    table.insert(anchor.flags, "not-selectable-in-game")

    anchor.minable = nil
    anchor.destructible = false

    anchor.collision_box = {{-0.05, -0.05}, {0.05, 0.05}}
    anchor.selection_box = {{-0.05, -0.05}, {0.05, 0.05}}
    anchor.collision_mask = { layers = {} }

    anchor.maximum_wire_distance = 32
    anchor.supply_area_distance = 0

    if anchor.pictures then
      local function _shrink(pic)
        if type(pic) ~= "table" then return end
        if pic.layers then
          for _, layer in pairs(pic.layers) do _shrink(layer) end
        else
          pic.scale = (pic.scale or 1) * 0.01
          pic.tint = {1, 1, 1, 0}
        end
      end
      _shrink(anchor.pictures)
    end
    anchor.radius_visualisation_picture = empty_sprite

    anchor.fast_replaceable_group = nil
    anchor.next_upgrade = nil
    anchor.working_sound = nil

    data:extend({ anchor })
  else
    log("[tagboat_towship] small-electric-pole prototype not found; tow wire will fall back to rendering line.")
  end
end

-- Custom input for safe disembark (runtime handler in control.lua)
if not (data.raw["custom-input"] and data.raw["custom-input"]["tagboat-disembark"]) then
  data:extend({
    {
      type = "custom-input",
      name = "tagboat-disembark",
      key_sequence = "L",
      consuming = "game-only",
      order = "z[tagboat]-a[disembark]"
    }
  })
end

-- Custom input for embark (runtime handler in control.lua)
if not (data.raw["custom-input"] and data.raw["custom-input"]["tagboat-embark"]) then
  data:extend({
    {
      type = "custom-input",
      name = "tagboat-embark",
      key_sequence = "K",
      consuming = "game-only",
      order = "z[tagboat]-b[embark]"
    }
  })
end
