# HLW-Roblox

A Roblox adaptation of **Hero Line War**, the classic Warcraft 3 custom game.

## Game Overview

Hero Line War is a team-based strategy game where players:
- **Pick a hero** from a roster with unique abilities
- **Send creep waves** down lanes toward the enemy base (spending gold, gaining income)
- **Earn income** every 17 seconds based on creeps sent
- **Level up** their hero and buy items to defend their base
- **Win** by depleting the enemy team's base lives to zero

Teams of 1-4 players compete. Each base starts with 100 lives. Every creep that reaches the enemy base costs them 1 life.

## Tech Stack

- **Rojo** - filesystem-based project sync
- **Wally** - package manager (Knit, Signal, Promise, Trove, etc.)
- **Knit** - service/controller framework
- **Selene** - Luau linter
- **StyLua** - Luau formatter
- **Aftman** - tool version manager

## Setup

```bash
# Install tool versions
aftman install

# Install packages
wally install

# Start Rojo dev server
rojo serve
```

Then connect Roblox Studio via the Rojo plugin.

## Project Structure

- `src/ServerScriptService/Services/` - Server-authoritative game logic (Knit services)
- `src/StarterPlayerScripts/Controllers/` - Client UI and input (Knit controllers)
- `src/ReplicatedStorage/Shared/` - Shared constants, types, and data tables

## Architecture

All game logic is **server-authoritative**. The client handles UI and input only. Shared data modules (HeroData, CreepData, ItemData) are in ReplicatedStorage so the client can display stats without network calls.
