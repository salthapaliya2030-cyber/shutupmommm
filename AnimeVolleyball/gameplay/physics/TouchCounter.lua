-- ============================================================
-- TouchCounter.lua  |  gameplay/physics/
-- Tracks per-rally touch state with strict double-touch
-- protection, 0.1s cooldown enforcement, and per-player stats.
-- ============================================================

local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)

local TouchCounter = {}
TouchCounter.__index = TouchCounter

function TouchCounter.new()
    local self = setmetatable({}, TouchCounter)

    self.touchCount    = 0            -- current rally touch count (0-3)
    self.lastToucherID = nil          -- UserId of last toucher
    self.lastTouchTeam = nil

    -- Cooldown registry: playerID → timestamp of last touch
    self.cooldowns = {}

    -- Per-player stats for reward calculation
    self.stats = {}  -- [UserId] = { spikes, blocks, perfReceives, sets, bumps }

    return self
end

-- ─────────────────────────────────────────────────────────────
-- REGISTER A TOUCH
-- Returns touch index (1, 2, 3) or nil if rejected
-- ─────────────────────────────────────────────────────────────
function TouchCounter:registerTouch(playerID, team, touchType)
    -- 0.1s cooldown gate (prevents single-frame multi-register)
    local now = os.clock()
    local lastTime = self.cooldowns[playerID]
    if lastTime and (now - lastTime) < GameConstants.Physics.TouchCooldown then
        return nil  -- silently reject duplicate frame event
    end
    self.cooldowns[playerID] = now

    -- Double-touch gate
    if playerID == self.lastToucherID and self.lastTouchTeam == team then
        return nil  -- caller should treat as double-foul
    end

    -- Net crossing resets touch counter
    -- (net crossing is detected externally; counter is reset by MatchFSM)

    self.touchCount    = self.touchCount + 1
    self.lastToucherID = playerID
    self.lastTouchTeam = team

    -- Accrue stats
    self:_accrueStats(playerID, touchType)

    return self.touchCount
end

-- ─────────────────────────────────────────────────────────────
-- DOUBLE-TOUCH PRE-CHECK  (call before registerTouch)
-- ─────────────────────────────────────────────────────────────
function TouchCounter:wouldCauseDoubleFoul(playerID)
    return playerID == self.lastToucherID
end

-- ─────────────────────────────────────────────────────────────
-- NET CROSSING RESET  (called by BallPhysics on valid net pass)
-- ─────────────────────────────────────────────────────────────
function TouchCounter:resetForNetCrossing()
    self.touchCount    = 0
    self.lastToucherID = nil
    -- lastTouchTeam flips because ball crossed to other side
    self.lastTouchTeam = self.lastTouchTeam == "A" and "B" or "A"
end

-- ─────────────────────────────────────────────────────────────
-- FULL FLUSH  (called on point award / round reset)
-- ─────────────────────────────────────────────────────────────
function TouchCounter:flush()
    self.touchCount    = 0
    self.lastToucherID = nil
    self.lastTouchTeam = nil
    self.cooldowns     = {}
    -- NOTE: stats are NOT flushed so reward totals accumulate per match
end

-- ─────────────────────────────────────────────────────────────
-- PLAYER DISCONNECT FLUSH  (prevents faulty tracking)
-- ─────────────────────────────────────────────────────────────
function TouchCounter:flushPlayer(playerID)
    self.cooldowns[playerID] = nil
    if self.lastToucherID == playerID then
        self.lastToucherID = nil
    end
    -- Keep stats for partial reward calculation if needed
end

-- ─────────────────────────────────────────────────────────────
-- GETTERS
-- ─────────────────────────────────────────────────────────────
function TouchCounter:getTouchCount()    return self.touchCount end
function TouchCounter:getLastToucherID() return self.lastToucherID end
function TouchCounter:getLastTouchTeam() return self.lastTouchTeam end

function TouchCounter:getStatsForPlayer(playerID)
    return self.stats[playerID] or {
        spikes = 0, blocks = 0, perfReceives = 0, sets = 0, bumps = 0
    }
end

-- ─────────────────────────────────────────────────────────────
-- INTERNAL STAT TRACKER
-- ─────────────────────────────────────────────────────────────
function TouchCounter:_accrueStats(playerID, touchType)
    if not self.stats[playerID] then
        self.stats[playerID] = {
            spikes = 0, blocks = 0, perfReceives = 0, sets = 0, bumps = 0
        }
    end
    local s = self.stats[playerID]
    if touchType == "Spike"      then s.spikes       = s.spikes + 1
    elseif touchType == "Block"  then s.blocks       = s.blocks + 1
    elseif touchType == "Set"    then s.sets         = s.sets + 1
    elseif touchType == "Bump"   then s.bumps        = s.bumps + 1
    elseif touchType == "PerfectReceive" then
        s.perfReceives = s.perfReceives + 1
        s.bumps        = s.bumps + 1
    end
end

return TouchCounter
