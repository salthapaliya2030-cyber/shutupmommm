# Anime Volleyball – Complete Engine Framework
## Project Architecture & Setup Guide

---

## Directory Structure

```
AnimeVolleyball/
├── README.md
│
├── graphics/                       ← CLIENT-SIDE rendering domain
│   ├── materials/
│   │   └── GraphicsEngine.lua      ← Lighting, cel-shading, edge bevel, motion blur
│   ├── particles/
│   │   └── ParticleSystem.lua      ← Ball trails, impact debris, head text pops
│   ├── ui/
│   │   ├── UIController.lua        ← Main menu, HUD, gacha modal, team selector
│   │   └── ClientMain.lua          ← LocalScript entry point; input → RemoteEvent relay
│   └── viewport/
│       └── CameraEngine.lua        ← Orbital / Shiftlock / Cinematic camera modes
│
├── animations/                     ← ANIMATION domain (client + reference)
│   ├── bones/
│   │   └── BoneData.lua            ← Skeleton hierarchy, bind poses, key pose offsets
│   ├── joints/
│   │   └── AnimationEngine.lua     ← Motor6D manipulation, track playback, stretch IK
│   └── tracks/
│       └── TrackMarkers.lua        ← Animation timeline marker definitions & keyframes
│
├── gameplay/                       ← SERVER-SIDE authoritative domain
│   ├── fsm/
│   │   ├── CharacterStateMachine.lua  ← 5-state character FSM (Idle/Run/Air/Recover/Stun)
│   │   └── MatchStateMachine.lua      ← Match lifecycle FSM (Lobby→Serve→Rally→Point…)
│   ├── physics/
│   │   ├── BallPhysics.lua         ← Bump/Set/Spike vectors, net plane validator, shadow loop
│   │   └── TouchCounter.lua        ← Touch tracking, double-touch protection, cooldown
│   ├── gacha/
│   │   └── GachaEngine.lua         ← Drop table, level gate lock, pity system, DataStore
│   ├── bot/
│   │   └── BotAI.lua               ← Easy/Medium/Godly AI profiles, target lock, WASD tilt
│   └── match/
│       ├── ServerMain.lua          ← Script entry; player join, match init, input handler
│       └── ServeController.lua     ← Serve weld, toss mechanic, power window, fault
│
└── shared/                         ← SHARED domain (required by both server and client)
    ├── constants/
    │   └── GameConstants.lua       ← ALL numeric constants, coordinates, formulas
    └── remotes/
        └── RemoteRegistry.lua      ← Every RemoteEvent and RemoteFunction definition
```

---

## Server-Client Architecture

```
CLIENT                              SERVER
  │                                   │
  │  PlayerInput (minimal signal)      │
  │ ─────────────────────────────────> │  ServerMain.lua receives
  │   { actionType, dirModifier,       │  validates input gate (FSM)
  │     lookVector, timestamp }        │  executes all physics math
  │                                   │
  │ <─────────────────────────────── │  MatchStateChanged
  │ <─────────────────────────────── │  BallVelocityUpdate
  │ <─────────────────────────────── │  PlayAnimation
  │ <─────────────────────────────── │  SpawnEffect
  │ <─────────────────────────────── │  PointScored / FoulTriggered
  │                                   │
  │  Renders animation on contact     │  Owns ball network ownership
  │  frame signal from server         │  Runs all FSMs on Heartbeat
```

**The client NEVER calculates ball velocity or touch validity.**  
The server broadcasts results; the client only renders them.

---

## Roblox Studio Setup

### 1. ReplicatedStorage Structure
```
ReplicatedStorage/
└── AnimeVB/                    ← Create this folder
    ├── shared/
    │   ├── constants/          ← GameConstants.lua (ModuleScript)
    │   └── remotes/            ← RemoteRegistry.lua (ModuleScript)
    ├── graphics/
    │   ├── materials/          ← GraphicsEngine.lua (ModuleScript)
    │   ├── particles/          ← ParticleSystem.lua (ModuleScript)
    │   ├── ui/                 ← UIController.lua, ClientMain.lua
    │   └── viewport/           ← CameraEngine.lua (ModuleScript)
    └── animations/
        ├── bones/              ← BoneData.lua (ModuleScript)
        ├── joints/             ← AnimationEngine.lua (ModuleScript)
        └── tracks/             ← TrackMarkers.lua (ModuleScript)
```

### 2. ServerScriptService Structure
```
ServerScriptService/
└── AnimeVB/
    └── gameplay/
        ├── fsm/
        ├── physics/
        ├── gacha/
        ├── bot/
        └── match/
            └── ServerMain.lua  ← Script (not ModuleScript)
```

### 3. StarterPlayerScripts
```
StarterPlayerScripts/
└── ClientMain.lua              ← LocalScript (copy from graphics/ui/)
```

### 4. Required Workspace Objects
```
Workspace/
├── Volleyball                  ← Sphere Part, Size=(1,1,1), Anchored=false
├── MatchZone                   ← Cylinder Part, CanCollide=false, green color
│                                  (no collision but Touched event works)
└── Court/
    ├── Floor                   ← Part (18×0.1×9 studs)
    ├── Net                     ← Part at Z=0, Y=0 to Y=2.43
    └── Walls/                  ← Optional boundary wall parts
```

### 5. ServerStorage
```
ServerStorage/
└── BotTemplate                 ← R15 rig for NPC bots
```

---

## System Initialization Order

### Server (auto-runs via ServerMain.lua Script):
1. `RemoteRegistry` — creates all Remote objects
2. `GachaEngine` — loads DataStore, wires `RequestSpin` and `GetProfile`
3. Player join → `loadProfile()` → currency sync
4. Matchmaking zone `Touched` → fires `ShowMatchSetupPrompt` to client
5. `RequestJoinSlot` → validates slot → `_startMatch()` when ready
6. `MatchStateMachine.start()` → Heartbeat loop begins
7. `BotAI` bots fill empty slots

### Client (auto-runs via ClientMain LocalScript):
1. `GraphicsEngine.init()` — lighting, fullscreen toggle, screen shake listener
2. `CameraEngine.init()` — orbital mode default, Shift toggle wired
3. `UIController` require — all UI event listeners wired
4. `ParticleSystem` require — all effect listeners wired
5. `CharacterAdded` → register animator, apply cel outline and skin

---

## Animation Workflow

1. Open **Animation Editor** plugin in Roblox Studio
2. Load `BotTemplate` or a player R15 rig
3. For each track in `TrackMarkers.lua`, create an Animation:
   - Add **KeyframeMarker** events at the exact time values
   - Name them exactly (e.g., `"ContactFrame"`, `"WindupEnd"`)
   - Follow the `keyframes` table for joint rotation values
4. Publish each animation and copy the **rbxassetid://XXXXXXX**
5. Paste IDs into the `ANIM_IDS` table in `AnimationEngine.lua`

---

## Gacha System Summary

| Rarity    | Base Weight | Cumulative | Level Gate |
|-----------|-------------|------------|------------|
| Common    | 60%         | 0.60       | None       |
| Rare      | 25%         | 0.85       | None       |
| Legendary | 10%         | 0.95       | Level 10   |
| Godly     | 4%          | 0.99       | Level 25   |
| Secret    | 1%          | 1.00       | Level 50   |

- Pity threshold: guaranteed Legendary+ after **90 spins**
- Below level gate: locked tier weight redistributed to Common
- Spin cost: **500 Yen** or **30 Gems**

---

## Physics Constants Reference

| Constant               | Value       | Unit      |
|------------------------|-------------|-----------|
| Gravity                | −196.2      | studs/s²  |
| Jump Impulse           | 52          | studs/s   |
| Walk Speed (base)      | 16          | studs/s   |
| Walk Speed (min clamp) | 4           | studs/s   |
| Touch Cooldown         | 0.10        | seconds   |
| Net Height             | 2.43        | studs     |
| Set Velocity Cap       | 28          | studs/s   |
| Spike Contact Frame    | 0.42        | seconds   |
| Stun Duration          | 1.20        | seconds   |
| W-modifier gravity     | −1.6        | multiplier|
| S-modifier horizontal  | ×1.8        | multiplier|
| A/D lateral force      | ±14         | studs/s   |

---

## Style Abilities

| Style   | Rarity    | Ability        | Description                                    |
|---------|-----------|----------------|------------------------------------------------|
| Rookie  | Common    | None           | Base stats                                     |
| Ace     | Rare      | BoomJump       | 4s super-jump height multiplier                |
| Phantom | Legendary | MagneticPull   | 5s: ball curves toward player on contact       |
| Nexus   | Godly     | SteelBlock     | 6s: block returns ball with 2× speed           |
| Void    | Secret    | ShieldBreaker  | 7s: spike passes through blocker hitboxes      |

---

## Match Rules

- **Set**: First to 25 points, must lead by 2 (Deuce activates at 24-24)
- **Match**: Best of 3 sets
- **Max team touches per rally**: 3
- **Double-touch**: instant foul, point to opponent
- **Net overreach**: foul on spike if hand crosses net plane
- **Touch 1** (Bump): Left click on ground → high vertical arc
- **Touch 2** (Set): Q or E → clean vertical column with directional tilt
- **Touch 3** (Spike): Jump + Left click → look-vector × style power

---

## Known Extension Points

- **Multiplayer / Server Lists**: Wire `PlayButton` to `TeleportService` for multi-server matchmaking
- **Additional Styles**: Add entries to `GameConstants.Styles` with matching `rarity`, ability, and trail color
- **Ranking System**: Extend `GachaEngine` profile with `mmr` field and ladder logic
- **Sound Engine**: Add `SoundService` calls tied to `PlayAnimation` contact frame events
- **Mobile Support**: `UserInputService.TouchStarted` → same `PlayerInput` RemoteEvent payload
