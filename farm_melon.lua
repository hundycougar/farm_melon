-- farm_melon.lua
-- CC:Tweaked turtle melon harvester with:
--  - width/length from CLI args
--  - auto-refuel from SAME chest behind home
--  - mid-run inventory dump when full
--  - returns to exact location + direction after dumping
--
-- Assumes:
--  - Turtle starts 1 block ABOVE farm surface
--  - At the NW corner of the rectangle (conceptually)
--  - Facing INTO the farm
--  - Chest is directly BEHIND the turtle at start/home

local args = { ... }
local WIDTH  = tonumber(args[1]) or 5
local LENGTH = tonumber(args[2]) or 5

if WIDTH < 1 or LENGTH < 1 then
  print("Usage: farm_melon.lua <width> <length>")
  return
end

-- Position tracking relative to home
-- dir: 0=E, 1=S, 2=W, 3=N
local posX, posZ, dir = 0, 0, 0

-- ----------------------------
-- Movement + orientation
-- ----------------------------
local function turnLeft()
  turtle.turnLeft()
  dir = (dir + 3) % 4
end

local function turnRight()
  turtle.turnRight()
  dir = (dir + 1) % 4
end

local function turnAround()
  turnLeft(); turnLeft()
end

local function face(targetDir)
  while dir ~= targetDir do
    turnRight()
  end
end

local function forward()
  while not turtle.forward() do
    turtle.dig()
    turtle.attack()
    sleep(0.15)
  end

  if dir == 0 then
    posX = posX + 1
  elseif dir == 2 then
    posX = posX - 1
  elseif dir == 1 then
    posZ = posZ + 1
  else
    posZ = posZ - 1
  end
end

local function moveTo(targetX, targetZ)
  -- Move X axis
  if posX < targetX then
    face(0) -- East
    for _ = 1, (targetX - posX) do forward() end
  elseif posX > targetX then
    face(2) -- West
    for _ = 1, (posX - targetX) do forward() end
  end

  -- Move Z axis
  if posZ < targetZ then
    face(1) -- South
    for _ = 1, (targetZ - posZ) do forward() end
  elseif posZ > targetZ then
    face(3) -- North
    for _ = 1, (posZ - targetZ) do forward() end
  end
end

local function goHome()
  moveTo(0, 0)
  face(0) -- Face into farm orientation at home
end

-- ----------------------------
-- Inventory helpers
-- ----------------------------
local function hasEmptySlot()
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then
      return true
    end
  end
  return false
end

local function dumpAllToChest()
  -- Chest is behind home, so turn around and drop forward
  turnAround()
  for i = 1, 16 do
    turtle.select(i)
    if turtle.getItemCount(i) > 0 then
      turtle.drop()
    end
  end
  turtle.select(1)
  turnAround()
end

-- ----------------------------
-- Auto-refuel from same chest
-- Strategy:
--  - Only suck 1 item at a time into an empty slot
--  - If it's fuel, consume it
--  - If not, drop it back
-- This avoids accidentally pulling melons out of the output chest.
-- ----------------------------
local function tryRefuelFromChest(maxAttempts)
  maxAttempts = maxAttempts or 64

  -- Must be at home for simplest behavior
  -- Face chest
  turnAround()

  for _ = 1, maxAttempts do
    -- Find empty slot
    local emptySlot = nil
    for i = 1, 16 do
      if turtle.getItemCount(i) == 0 then
        emptySlot = i
        break
      end
    end
    if not emptySlot then
      break
    end

    turtle.select(emptySlot)

    -- Suck 1 item from chest
    if not turtle.suck(1) then
      break -- chest empty or no access
    end

    -- Try to refuel that 1 item
    if not turtle.refuel(1) then
      -- Not fuel, put it back
      turtle.drop(1)
    end
  end

  turtle.select(1)
  turnAround()
end

local function estimateFuelNeeded()
  -- Rough estimate:
  -- Traversal across WIDTH*LENGTH tiles with serpentine moves
  -- plus some buffer for mid-run return trips
  local tiles = WIDTH * LENGTH
  local pathMoves = tiles - 1
  local rowShifts = (LENGTH - 1)
  local approxFarmMoves = pathMoves + rowShifts

  -- Worst-case dump trip:
  -- from far corner back home and back again
  local worstOneWay = (WIDTH - 1) + (LENGTH - 1)
  local worstRoundTrip = worstOneWay * 2

  -- Add generous buffer
  return approxFarmMoves + worstRoundTrip + 50
end

local function ensureFuel()
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return true end

  local needed = estimateFuelNeeded()
  if fuel >= needed then return true end

  -- Try to refuel from the output chest behind home
  -- If we are not home, caller should bring us home first
  tryRefuelFromChest(128)

  fuel = turtle.getFuelLevel()
  return (fuel == "unlimited") or (fuel >= needed)
end

-- ----------------------------
-- Melon harvest logic
-- ----------------------------
local function isMelonBlock(name)
  if not name then return false end
  -- Vanilla block id is typically minecraft:melon
  -- Some contexts may expose minecraft:melon_block
  if name == "minecraft:melon" or name == "minecraft:melon_block" then
    return true
  end
  -- Safe-ish fallback:
  if string.find(name, "melon") and not string.find(name, "stem") then
    return true
  end
  return false
end

local function harvestTile()
  local ok, data = turtle.inspectDown()
  if not ok or not data then return end

  if isMelonBlock(data.name) then
    turtle.digDown()
  end
end

-- ----------------------------
-- Mid-run dump + resume
-- ----------------------------
local function dumpIfFull()
  if hasEmptySlot() then return end

  -- Save state
  local savedX, savedZ, savedDir = posX, posZ, dir

  -- Go home, dump, refuel if needed, then return
  goHome()
  dumpAllToChest()

  -- Refuel at home if low
  ensureFuel()

  -- Return to saved location + direction
  moveTo(savedX, savedZ)
  face(savedDir)
end

-- ----------------------------
-- Main farm routine
-- ----------------------------
local function farmArea()
  for row = 1, LENGTH do
    for col = 1, WIDTH do
      harvestTile()
      dumpIfFull()

      if col < WIDTH then
        forward()
      end
    end

    if row < LENGTH then
      if row % 2 == 1 then
        turnRight()
        forward()
        turnRight()
      else
        turnLeft()
        forward()
        turnLeft()
      end
    end
  end
end

-- ----------------------------
-- Execution
-- ----------------------------
-- Ensure initial fuel from home chest
if turtle.getFuelLevel() ~= "unlimited" then
  -- We assume we're at home at program start
  ensureFuel()
end

farmArea()

-- Final return + unload
goHome()
dumpAllToChest()

print(("Melon harvest complete (%dx%d)."):format(WIDTH, LENGTH))
