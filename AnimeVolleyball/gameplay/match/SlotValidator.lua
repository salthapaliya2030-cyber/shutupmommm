-- ============================================================
-- SlotValidator.lua  |  gameplay/match/
-- Server-side matchmaking slot table manager.
-- Validates team and position availability, enforces capacity,
-- prevents duplicate role assignments, and broadcasts updates.
-- ============================================================

local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local SlotValidator = {}
SlotValidator.__index = SlotValidator

-- ─────────────────────────────────────────────────────────────
-- CONSTRUCTION
-- ─────────────────────────────────────────────────────────────
function SlotValidator.new()
    local self = setmetatable({}, SlotValidator)

    -- Slot registry: [team][position] = userId | nil
    self.slots = {
        A = { Spiker = nil, Setter = nil, Libero = nil },
        B = { Spiker = nil, Setter = nil, Libero = nil },
    }

    -- Reverse lookup: [userId] = { team, position }
    self.assignments = {}

    -- Pending players (in setup zone, selecting)
    self.pendingPlayers = {}   -- [userId] = true

    return self
end

-- ─────────────────────────────────────────────────────────────
-- PLAYER ENTERS SETUP ZONE
-- ─────────────────────────────────────────────────────────────
function SlotValidator:enterSetupZone(player)
    self.pendingPlayers[player.UserId] = true
end

function SlotValidator:leaveSetupZone(player)
    self.pendingPlayers[player.UserId] = nil
end

-- ─────────────────────────────────────────────────────────────
-- VALIDATE AND CLAIM SLOT
-- Returns { success, errorMsg }
-- ─────────────────────────────────────────────────────────────
function SlotValidator:claimSlot(player, team, position)
    local userId = player.UserId
    local C      = GameConstants.Match

    -- ── Valid team check
    if team ~= "A" and team ~= "B" then
        return { success = false, errorMsg = "Invalid team selection." }
    end

    -- ── Valid position check
    if not table.find(C.RolesPerTeam, position) then
        return { success = false, errorMsg = "Invalid position." }
    end

    -- ── Slot already taken
    if self.slots[team][position] ~= nil then
        return { success = false, errorMsg = "Position Filled" }
    end

    -- ── Team capacity check
    local count = self:_teamCount(team)
    if count >= C.MaxPlayersPerTeam then
        return { success = false, errorMsg = "Team Full" }
    end

    -- ── Release previous slot if player was already assigned
    if self.assignments[userId] then
        local prev = self.assignments[userId]
        self.slots[prev.team][prev.position] = nil
    end

    -- ── Assign slot
    self.slots[team][position]    = userId
    self.assignments[userId]      = { team = team, position = position }

    -- ── Broadcast updated availability to ALL clients
    Remotes.Events.SlotStatusUpdate:FireAllClients({
        slotTable = self:getPublicSlotTable(),
    })

    return { success = true }
end

-- ─────────────────────────────────────────────────────────────
-- RELEASE SLOT (player disconnects or leaves zone)
-- ─────────────────────────────────────────────────────────────
function SlotValidator:releaseSlot(player)
    local userId    = player.UserId
    local assignment = self.assignments[userId]
    if not assignment then return end

    self.slots[assignment.team][assignment.position] = nil
    self.assignments[userId] = nil
    self.pendingPlayers[userId] = nil

    Remotes.Events.SlotStatusUpdate:FireAllClients({
        slotTable = self:getPublicSlotTable(),
    })
end

-- ─────────────────────────────────────────────────────────────
-- GET ASSIGNMENT for a player
-- ─────────────────────────────────────────────────────────────
function SlotValidator:getAssignment(player)
    return self.assignments[player.UserId]
end

-- ─────────────────────────────────────────────────────────────
-- PUBLIC SLOT TABLE  (safe to send to clients – no UserIDs)
-- Returns { A = { Spiker=true/false, ... }, B = { ... } }
-- ─────────────────────────────────────────────────────────────
function SlotValidator:getPublicSlotTable()
    local out = { A = {}, B = {} }
    for team, positions in pairs(self.slots) do
        for pos, uid in pairs(positions) do
            out[team][pos] = (uid ~= nil)  -- boolean: slot occupied?
        end
    end
    return out
end

-- ─────────────────────────────────────────────────────────────
-- INTERNAL: count claimed slots for a team
-- ─────────────────────────────────────────────────────────────
function SlotValidator:_teamCount(team)
    local n = 0
    for _, uid in pairs(self.slots[team]) do
        if uid then n = n + 1 end
    end
    return n
end

-- ─────────────────────────────────────────────────────────────
-- CHECK IF MATCH CAN START
-- Returns true if at least one human slot is filled
-- ─────────────────────────────────────────────────────────────
function SlotValidator:canStartMatch()
    for _, positions in pairs(self.slots) do
        for _, uid in pairs(positions) do
            if uid then return true end
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- FULL RESET (between matches)
-- ─────────────────────────────────────────────────────────────
function SlotValidator:reset()
    self.slots = {
        A = { Spiker = nil, Setter = nil, Libero = nil },
        B = { Spiker = nil, Setter = nil, Libero = nil },
    }
    self.assignments   = {}
    self.pendingPlayers = {}

    Remotes.Events.SlotStatusUpdate:FireAllClients({
        slotTable = self:getPublicSlotTable(),
    })
end

return SlotValidator
