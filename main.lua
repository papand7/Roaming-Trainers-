-- roaming_trainers: milestone 1.
-- Spawn one visible, walkable NPC on Route 1 and confirm talking to it
-- works. Nothing persistent yet, no team, no battle - just proving the
-- spawn -> place -> interact loop end to end before building on it.
-- The 10-minute loop: edit, save, F5 in a POKEPORT_DEV=1 game, repeat.
--
-- No voice audio here: there's no mod-facing sound API in this engine,
-- and more fundamentally Game Boy-era Pokemon never had spoken dialogue
-- at all (only music/SFX blips) - there's nothing to hook even for the
-- vanilla NPCs. Text-only replies below; flagged rather than faked.

-- Real overworld trainer-class sprite ids, confirmed against the engine's
-- own ROM manifest (tools/rom_manifest.json -> sprites.order) rather than
-- guessed. GENDER is our own flavor tag (not from the manifest) used only
-- to pick a gender-appropriate line below.
local TRAINER_SPRITES = {
  { id = "SPRITE_YOUNGSTER",     gender = "m" },
  { id = "SPRITE_HIKER",         gender = "m" },
  { id = "SPRITE_FISHER",        gender = "m" },
  { id = "SPRITE_SWIMMER",       gender = "m" },
  { id = "SPRITE_BIKER",         gender = "m" },
  { id = "SPRITE_COOLTRAINER_M", gender = "m" },
  { id = "SPRITE_GAMBLER",       gender = "m" },
  { id = "SPRITE_SAILOR",        gender = "m" },
  { id = "SPRITE_SCIENTIST",     gender = "m" },
  { id = "SPRITE_ROCKER",        gender = "m" },
  { id = "SPRITE_GENTLEMAN",     gender = "m" },
  { id = "SPRITE_COOLTRAINER_F", gender = "f" },
  { id = "SPRITE_BEAUTY",        gender = "f" },
  { id = "SPRITE_CHANNELER",     gender = "f" },
}

-- "Current task" flavor, split by gender only in pronoun/phrasing.
-- {NAME} is a live substitution token (real engine syntax - the "subs"
-- table passed to show_text does text:gsub("{NAME:?...}", value)) so one
-- translated id serves every NPC regardless of which name lands on it,
-- rather than needing a translated line per name/line combination.
local TASK_LINES = {
  m = {
    "{NAME}:\nI've been training my team\nall morning!",
    "{NAME}:\nJust caught a new Pokemon\nnearby - lucky find!",
    "{NAME}:\nHeading to the next town to\ntest my skills.",
    "{NAME}:\nTaking a break to let my\nPokemon rest up.",
    "{NAME}:\nLooking for a strong\nopponent to battle!",
  },
  f = {
    "{NAME}:\nI've been training my team\nall morning!",
    "{NAME}:\nJust caught a new Pokemon\nnearby - lucky find!",
    "{NAME}:\nI'm heading to the next town\nto test my skills.",
    "{NAME}:\nTaking a break to let my\nPokemon rest up.",
    "{NAME}:\nLooking for a strong\nopponent to battle!",
  },
}

-- Generic Pokemon trivia, written in our own words - not reproduced from
-- any game or guidebook text. Split by gender (identical content, just
-- duplicated under separate ids) so every dialogue id maps to exactly one
-- voice - voice lines are pre-generated per id, not per NPC instance, so
-- a fact line shared across genders could only ever have one fixed voice
-- regardless of which gender NPC actually says it.
local FACT_LINES = {
  m = {
    "{NAME}:\nDid you know? Every save file\ngives your Pokemon a unique\nID number.",
    "{NAME}:\nFun fact: some Pokemon only\nevolve by trading, not just\nleveling up!",
    "{NAME}:\nI heard Ditto can transform\ninto almost any Pokemon\nit sees!",
    "{NAME}:\nMagikarp might be weak, but\nGyarados sure isn't!",
    "{NAME}:\nThey say some Pokemon only\nshow up at certain times\nof day.",
  },
  f = {
    "{NAME}:\nDid you know? Every save file\ngives your Pokemon a unique\nID number.",
    "{NAME}:\nFun fact: some Pokemon only\nevolve by trading, not just\nleveling up!",
    "{NAME}:\nI heard Ditto can transform\ninto almost any Pokemon\nit sees!",
    "{NAME}:\nMagikarp might be weak, but\nGyarados sure isn't!",
    "{NAME}:\nThey say some Pokemon only\nshow up at certain times\nof day.",
  },
}

-- Names + class prefix (matches vanilla battle-name style, e.g. "YOUTH
-- SAM"), split by gender. Invented names, not tied to any real character.
local NAMES = {
  m = { "SAM", "MIKE", "TOM", "CHAD", "LEO", "OSCAR" },
  f = { "ELLA", "MIA", "ZOE", "AMY", "IRIS", "LUNA" },
}
local CLASS_PREFIX = { m = "YOUTH", f = "LASS" }

-- Odds that any given roaming NPC is battle-capable rather than just
-- flavor text. Not every trainer should fight - matches how vanilla
-- Pokemon has plenty of NPCs who just talk.
local BATTLE_CHANCE = 0.5

-- How many NPCs to spawn, and how they wander.
local WANDER_MIN_TICKS, WANDER_MAX_TICKS = 60, 180  -- ~1-3s at 60fps between steps
local DIRS = { "up", "down", "left", "right" }

-- Real early-Kanto map ids, confirmed against the engine's own ROM
-- manifest (tools/rom_manifest.json -> maps) rather than guessed - one
-- NPC per entry, spread across towns and routes instead of clustered near
-- the player. Coordinates are a best-effort starting guess, not verified
-- walkable tiles for each specific map (we don't have per-map collision
-- data to check against) - if one lands on a wall it'll just sit there
-- unable to wander until the coordinate is nudged, not break anything.
local SPAWN_LOCATIONS = {
  { map = "PALLET_TOWN",     x = 8,  y = 10 },
  { map = "ROUTE_1",         x = 8,  y = 8  },
  { map = "VIRIDIAN_CITY",   x = 20, y = 18 },
  { map = "ROUTE_2",         x = 8,  y = 20 },
  { map = "VIRIDIAN_FOREST", x = 10, y = 15 },
  { map = "ROUTE_22",        x = 6,  y = 10 },
  { map = "PEWTER_CITY",     x = 12, y = 14 },
  { map = "ROUTE_3",         x = 10, y = 10 },
}

return function(mod)
  -- Register every dialogue line as a stable TEXT_* id instead of passing
  -- literal strings to show_text - this is the engine's real localization
  -- hook (Commands.show_text looks up ctx.game.data.text[textId] first,
  -- literal strings are only a fallback). A translation mod overriding
  -- mod.content.text for these exact ids translates our dialogue the same
  -- way it would translate any vanilla line.
  local taskTextIds = { m = {}, f = {} }
  for gender, lines in pairs(TASK_LINES) do
    for i, line in ipairs(lines) do
      local id = "TEXT_ROAMING_TASK_" .. gender:upper() .. "_" .. i
      mod.content.text:register(id, line)
      taskTextIds[gender][i] = id
    end
  end
  local factTextIds = { m = {}, f = {} }
  for gender, lines in pairs(FACT_LINES) do
    for i, line in ipairs(lines) do
      local id = "TEXT_ROAMING_FACT_" .. gender:upper() .. "_" .. i
      mod.content.text:register(id, line)
      factTextIds[gender][i] = id
    end
  end

  local function randomTextId(gender)
    local pool = {}
    for _, id in ipairs(taskTextIds[gender] or taskTextIds.m) do pool[#pool + 1] = id end
    for _, id in ipairs(factTextIds[gender] or factTextIds.m) do pool[#pool + 1] = id end
    return pool[math.random(1, #pool)]
  end

  -- One registered trainer class per name (both genders), each with its
  -- own display name, so battlers don't all share "Youth Sam". Same party
  -- for now across all of them - worth varying once we're placing many
  -- distinct teams instead of one shared pattern.
  local trainerIds = {}
  for gender, names in pairs(NAMES) do
    for _, shortName in ipairs(names) do
      local id = "MOD_ROAMING_TRAINER_" .. shortName
      mod.content.trainers:register(id, {
        id = id,
        name = CLASS_PREFIX[gender] .. " " .. shortName,
        parties = {
          { { level = 8, species = "RATTATA" }, { level = 8, species = "PIDGEY" } },
        },
      })
      trainerIds[#trainerIds + 1] = id
    end
  end

  -- Exposed for other mods (a translation mod, for instance) to discover
  -- what to override rather than guessing our ids. Trainer *names* here
  -- are proper nouns (Sam, Ella, ...) - typically left untranslated like
  -- any other name, but the class prefixes (YOUTH/LASS) baked into each
  -- trainer's `name` field could be patched via mod.content.trainers:patch
  -- on these same ids if a translation mod wants that level of polish.
  mod.exports.dialogueTextIds = { task = taskTextIds, fact = factTextIds }
  mod.exports.trainerIds = trainerIds
  mod.exports.classPrefixes = CLASS_PREFIX

  local locationsByMap = {}
  for _, loc in ipairs(SPAWN_LOCATIONS) do locationsByMap[loc.map] = loc end

  -- Spawned once per map, remembered for the rest of the session -
  -- spawnNpc is meant to be called on map.entered (per WorldAPI's own
  -- comment above spawnNpc), but calling it again on every re-entry would
  -- stack duplicate objects onto that map's def.objects each visit. We
  -- spawn once and just re-resolve a fresh handle on later visits.
  local npcIdByMap = {}
  local metaByMap = {}   -- mapId -> { gender, name, canBattle }

  -- Only the CURRENTLY active map's NPC(s) get a live, wanderable handle -
  -- a handle is only valid while its map is loaded, so this list gets
  -- rebuilt fresh every time the player changes map.
  local npcs = {}
  local npcByRawNpc = {}  -- keyed by the raw npc table, matching world.talk's
                          -- target - NOT the Handle wrapper, which is a
                          -- different Lua table from the same underlying npc.

  local function ensureSpawned(mapId)
    local loc = locationsByMap[mapId]
    if not loc or npcIdByMap[mapId] then return end
    local choice = TRAINER_SPRITES[math.random(1, #TRAINER_SPRITES)]
    local namePool = NAMES[choice.gender]
    local shortName = namePool[math.random(1, #namePool)]
    -- Real two-argument form confirmed against tests/mod_world_tests.lua:
    -- spawnNpc(mapId, objDef) - objDef has no "map" field, and this
    -- returns a bare string id, not a handle.
    local npcId, err = mod.world:spawnNpc(mapId, { x = loc.x, y = loc.y, sprite = choice.id })
    if not npcId then
      mod.log:warn("roaming_trainers: spawnNpc failed on %s: %s", mapId, tostring(err))
      return
    end
    npcIdByMap[mapId] = npcId
    local canBattle = math.random() < BATTLE_CHANCE
    metaByMap[mapId] = { gender = choice.gender, name = shortName, canBattle = canBattle }
    mod.log:info("roaming_trainers: spawned %s (%s, battler=%s) on %s at (%d,%d)",
      shortName, choice.id, tostring(canBattle), mapId, loc.x, loc.y)
  end

  local function activateForMap(mapId)
    npcs, npcByRawNpc = {}, {}
    local npcId = npcIdByMap[mapId]
    if not npcId then return end
    -- npc() resolves a live handle by id - only succeeds while mapId is
    -- the actually-active map, which map.entered guarantees here.
    local handle, err = mod.world:npc(mapId, npcId)
    if not handle then
      mod.log:warn("roaming_trainers: could not resolve handle on %s: %s", mapId, tostring(err))
      return
    end
    local meta = metaByMap[mapId]
    local entry = {
      handle = handle,
      gender = meta.gender,
      name = meta.name,
      canBattle = meta.canBattle,
      wanderAt = math.random(WANDER_MIN_TICKS, WANDER_MAX_TICKS),
    }
    npcs[#npcs + 1] = entry
    npcByRawNpc[handle.npc] = entry
  end

  -- Handle the map the player is already standing on at boot - map.entered
  -- fires for later transitions, but not retroactively for wherever the
  -- save already starts.
  mod.events:on("game.ready", function(ev)
    local pos = mod.world:current()
    if pos and pos.mapId then
      ensureSpawned(pos.mapId)
      activateForMap(pos.mapId)
    end
  end)

  mod.events:on("map.entered", function(ev)
    ensureSpawned(ev.mapId)
    activateForMap(ev.mapId)
  end)

  -- Ambient wandering: runs every frame regardless of what the player is
  -- doing (not gated on the player's own input/movement), and steps each
  -- NPC independently on its own random timer. canStep first since
  -- stepNow deliberately skips collision checking.
  mod.hooks:wrap("input.step", function(next, ...)
    for _, entry in ipairs(npcs) do
      if not entry.handle:isMoving() then
        entry.wanderAt = entry.wanderAt - 1
        if entry.wanderAt <= 0 then
          entry.wanderAt = math.random(WANDER_MIN_TICKS, WANDER_MAX_TICKS)
          local dir = DIRS[math.random(1, #DIRS)]
          if entry.handle:canStep(dir) then
            entry.handle:stepNow(dir)
          end
        end
      end
    end
    return next(...)
  end)

  mod.hooks:wrap("world.talk", function(next, ow, target)
    local entry = npcByRawNpc[target]
    if entry then
      if entry.canBattle then
        -- Real script verb the base game itself uses for trainer fights -
        -- confirmed against src/script/Commands.lua, not guessed. Trainer
        -- id matches the per-name registration above, so the battle intro
        -- shows this same NPC's actual name.
        ow:queueScript({
          { "start_battle", "trainer", "MOD_ROAMING_TRAINER_" .. entry.name, 1 },
        })
      else
        ow:queueScript({
          { "show_text", randomTextId(entry.gender), { NAME = entry.name } },
        })
      end
      return
    end
    return next(ow, target)
  end)
end
