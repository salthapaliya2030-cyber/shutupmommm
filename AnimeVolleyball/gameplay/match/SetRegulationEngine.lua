-- ============================================================
-- SetRegulationEngine.lua  |  gameplay/match/
-- Volleyball Set Regulation Engine.
-- Handles point ceiling, Deuce mode activation/resolution,
-- best-of-three set series, and algebraic reward calculation.
-- Works in tandem with MatchStateMachine – call its methods
-- from _awardPoint() and _checkSetWin().
-- ============================================================

local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local SetRegulationEngine = {}
SetRegulationEngine.__index = SetRegulationEngine

-- ─────────────────────────────────────────────────────────────
-- CONSTRUCTION
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine.new()
    local self = setmetatable({}, SetRegulationEngine)

    self.points     = { A = 0, B = 0 }   -- current set scores
    self.sets       = { A = 0, B = 0 }   -- sets won per team
    self.deuceActive = false
    self.deuceHistory = {}               -- track deuce exchanges for analytics

    self.setHistory = {}                 -- [setIndex] = { winner, finalScore }
    self.currentSet = 1

    -- Persistent stat accumulator for reward calc
    self.matchStats = {}  -- [userId] = { spikes, blocks, perfReceives }

    return self
end

-- ─────────────────────────────────────────────────────────────
-- AWARD POINT  – main entry from MatchFSM
-- Returns: "continue" | "setWon:<team>" | "matchWon:<team>"
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine:awardPoint(scoringTeam, cause)
    self.points[scoringTeam] = self.points[scoringTeam] + 1

    local pA     = self.points.A
    local pB     = self.points.B
    local target = GameConstants.Match.SetWinPoints
    local gap    = GameConstants.Match.DeuceGap

    -- ── CHECK DEUCE ACTIVATION
    -- Deuce activates when BOTH teams reach (target - 1) or higher
    -- and score is tied, OR when score ties at any point past the ceiling
    if (pA >= target - 1 and pB >= target - 1) then
        if math.abs(pA - pB) < gap then
            if not self.deuceActive then
                self.deuceActive = true
                table.insert(self.deuceHistory, {
                    set       = self.currentSet,
                    activatedAt = { A = pA, B = pB },
                })
                print(string.format("[SetEngine] DEUCE activated at %d-%d (Set %d)",
                    pA, pB, self.currentSet))
            end
        end
    end

    -- ── CHECK SET WIN
    local aWins, bWins = self:_checkSetWinCondition()

    if aWins or bWins then
        local winner = aWins and "A" or "B"
        return self:_processSetWin(winner)
    end

    return "continue"
end

-- ─────────────────────────────────────────────────────────────
-- INTERNAL SET WIN CONDITION
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine:_checkSetWinCondition()
    local pA     = self.points.A
    local pB     = self.points.B
    local target = GameConstants.Match.SetWinPoints
    local gap    = GameConstants.Match.DeuceGap

    if self.deuceActive then
        -- In deuce: win ONLY when leading by exactly gap (2)
        local aWins = (pA - pB) >= gap
        local bWins = (pB - pA) >= gap
        return aWins, bWins
    else
        -- Standard: first to target
        local aWins = pA >= target
        local bWins = pB >= target
        return aWins, bWins
    end
end

-- ─────────────────────────────────────────────────────────────
-- PROCESS SET WIN
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine:_processSetWin(winner)
    self.sets[winner] = self.sets[winner] + 1

    -- Record set history
    table.insert(self.setHistory, {
        setNumber  = self.currentSet,
        winner     = winner,
        finalScore = { A = self.points.A, B = self.points.B },
        hadDeuce   = self.deuceActive,
    })

    print(string.format("[SetEngine] Set %d won by Team %s (%d-%d)%s",
        self.currentSet, winner, self.points.A, self.points.B,
        self.deuceActive and " [DEUCE]" or ""))

    -- Broadcast
    Remotes.Events.SetWon:FireAllClients({
        winningTeam = winner,
        setScores   = { A = self.sets.A, B = self.sets.B },
        pointScores = { A = self.points.A, B = self.points.B },
        setNumber   = self.currentSet,
    })

    -- Reset for next set
    self.deuceActive  = false
    self.points.A     = 0
    self.points.B     = 0
    self.currentSet   = self.currentSet + 1

    -- Check match win
    local matchGoal   = GameConstants.Match.SetsToWinMatch
    if self.sets.A >= matchGoal or self.sets.B >= matchGoal then
        local matchWinner = self.sets.A >= matchGoal and "A" or "B"
        return "matchWon:" .. matchWinner
    end

    return "setWon:" .. winner
end

-- ─────────────────────────────────────────────────────────────
-- SCORE GETTERS
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine:getPointScores() return self.points end
function SetRegulationEngine:getSetScores()   return self.sets   end
function SetRegulationEngine:isDeuceActive()   return self.deuceActive end
function SetRegulationEngine:getCurrentSet()   return self.currentSet end

function SetRegulationEngine:getFullScoreString()
    return string.format("Set %d | %d-%d (Sets: A=%d B=%d)%s",
        self.currentSet,
        self.points.A, self.points.B,
        self.sets.A, self.sets.B,
        self.deuceActive and " [DEUCE]" or "")
end

-- ─────────────────────────────────────────────────────────────
-- STAT ACCUMULATION (feeds into reward calculation)
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine:recordStat(userId, statType)
    if not self.matchStats[userId] then
        self.matchStats[userId] = { spikes = 0, blocks = 0, perfReceives = 0 }
    end
    local s = self.matchStats[userId]
    if statType == "Spike"         then s.spikes       = s.spikes + 1
    elseif statType == "Block"     then s.blocks       = s.blocks + 1
    elseif statType == "PerfectReceive" then s.perfReceives = s.perfReceives + 1
    end
end

-- ─────────────────────────────────────────────────────────────
-- REWARD CALCULATION  (called on match end)
-- Uses algebraic formula from GameConstants
-- Yen = (SpikesLanded × 10) + (Blocks × 15) + (PerfReceives × 8) + BaseWin/Loss
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine:calculateRewards(winningTeam, playerTeamMap)
    local R   = GameConstants.Rewards
    local out = {}  -- [userId] = yenAmount

    for userId, stats in pairs(self.matchStats) do
        local team    = playerTeamMap[userId]
        local isWinner = team == winningTeam
        local base    = isWinner and R.BaseWin or R.BaseLoss

        local yen = base
            + (stats.spikes       * R.PerSpike)
            + (stats.blocks       * R.PerBlock)
            + (stats.perfReceives * R.PerPerfectReceive)

        out[userId] = yen

        print(string.format("[SetEngine] Reward for %s: %d Yen (Spikes:%d Blocks:%d Perf:%d %s)",
            tostring(userId), yen,
            stats.spikes, stats.blocks, stats.perfReceives,
            isWinner and "WIN" or "LOSS"))
    end

    return out
end

-- ─────────────────────────────────────────────────────────────
-- FULL RESET (between matches, not between sets)
-- ─────────────────────────────────────────────────────────────
function SetRegulationEngine:fullReset()
    self.points       = { A = 0, B = 0 }
    self.sets         = { A = 0, B = 0 }
    self.deuceActive  = false
    self.deuceHistory = {}
    self.setHistory   = {}
    self.currentSet   = 1
    self.matchStats   = {}
    print("[SetEngine] Full reset complete.")
end

return SetRegulationEngine
