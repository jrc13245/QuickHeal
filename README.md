# QuickHeal for Turtle WoW

QuickHeal automates healing spell selection and targeting for healers. It heals the lowest health party/raid member without requiring manual targeting, automatically selects the optimal spell rank based on health deficit and mana, and works with Priest, Druid, Paladin, and Shaman.

## Installation

Download QuickHeal into your `Interface/AddOns` folder. Ensure the folder is named `QuickHeal` (remove any `-main` suffix).

## Commands

| Command | Description |
|---------|-------------|
| `/qh` | Heal the lowest health target |
| `/qh cfg` | Open configuration panel |
| `/qh dr` | Open downrank slider window |
| `/qh toggle` | Toggle between Normal and High HPS mode |
| `/qh tanklist` | Toggle tank list display |
| `/qh help` | Show help in chat |
| `/qh dll` | Report DLL enhancement status |
| `/qh test on/off` | Toggle test mode (ignores health thresholds) |
| `/qh debug on/off` | Toggle debug output |
| `/qh reset` | Reset configuration to defaults |

### Target Masks

Constrain who can be healed by adding a mask:

| Mask | Targets |
|------|---------|
| `player` | Yourself only |
| `target` | Your current target |
| `targettarget` | Your target's target |
| `party` | Party members only |
| `mt` | Main tanks only |
| `nonmt` | Non-tanks only |
| `subgroup` | Configured raid subgroups |

Example: `/qh mt` heals only tanks, `/qh party` heals only party members.

### HPS Modes

**Normal HPS**: Uses all healing spells for maximum mana efficiency.

**High HPS**: Restricted to fast-casting spells (Flash Heal, Flash of Light, Lesser Healing Wave, Regrowth) for maximum throughput at the cost of mana efficiency.

Toggle with `/qh toggle`.

---

## Priest

**Spells used**: Lesser Heal, Heal, Greater Heal, Flash Heal, Renew

### Recommended Macros

```
/qh
```
Basic heal - selects optimal direct heal spell and rank.

```
/qh hot
```
Cast Renew on the lowest health target without an active HoT.

```
/qh hot max
```
Cast max rank Renew on the lowest health target.

```
/qh hot fh
```
Firehose mode - spam max rank Renew on targets without a HoT (useful for Naxx gargoyles).

---

## Druid

**Spells used**: Healing Touch, Regrowth, Rejuvenation

### Recommended Macros

```
/qh
```
Basic heal - selects optimal Healing Touch or Regrowth rank.

```
/qh hot
```
Cast Rejuvenation on the lowest health target without an active HoT.

```
/qh hot max
```
Cast max rank Rejuvenation.

```
/qh hot fh
```
Firehose mode - spam max rank Rejuvenation.

```
/script QuickHeal(nil,'Swiftmend')
```
Cast Swiftmend (works while moving).

```
/script QuickHeal(nil,'Regrowth')
```
Force Regrowth at max rank regardless of heal need.

---

## Paladin

**Spells used**: Holy Light, Flash of Light, Holy Shock

### Recommended Macros

```
/qh
```
Basic heal - selects Holy Light or Flash of Light based on heal need and talents.

```
/qh hs
```
Cast Holy Shock on the lowest health target. Cancels autoattack.

```
/qh hs max
```
Cast max rank Holy Shock.

```
/qh heal max
```
Cast max rank Flash of Light (or Holy Light if Holy Judgement buff active).

### Melee Paladin Macros

These macros are for paladins healing in melee range and do not cancel autoattack:

```
/run qhHShock(85)
```
Cast max rank Holy Shock if any target is below 85% HP.

```
/run qhHStrike(93,3)
```
Cast Holy Strike if 3+ targets are below 93% HP.

---

## Shaman

**Spells used**: Healing Wave, Lesser Healing Wave, Chain Heal

### Recommended Macros

```
/qh
```
Basic heal - selects optimal Healing Wave or Lesser Healing Wave rank.

```
/qh chainheal
```
Cast Chain Heal on the lowest health target.

```
/qh chainheal max
```
Cast max rank Chain Heal.

---

## Configuration

Open the config panel with `/qh cfg`. Key settings:

- **Healthy Threshold**: Skip healing targets above this HP percentage
- **Force Self-Heal**: Prioritize self when below this HP percentage
- **Target Priority**: Heal current target first if they need healing
- **Subgroups**: Select which raid groups to heal
- **Tank List**: Add tanks via `/qh tanklist` then click `+` with a tank targeted

### Downranking

Open the downrank window with `/qh dr`. The slider limits the maximum spell rank QuickHeal will use, allowing you to conserve mana by using lower ranks.

### Mouse-Click Healing

QuickHeal supports mouse-click healing. Hold **Ctrl** and left-click on any unit frame (player, target, party member, etc.) to trigger a heal. This works with Blizzard frames and many popular unit frame addons including Discord Unit Frames, Perl Classic, X-Perl, EasyRaid, and CT Raid Assist.

Enable/disable in configuration panel.

---

## Stopcasting Function

QuickHeal includes intelligent stopcasting to prevent wasted heals and mana. When a heal is in progress, it automatically checks several conditions and can cancel the cast if needed.

### How Stopcasting Works

When you start casting a heal, QuickHeal monitors the situation and can stop the cast if:

1. **Target dies** - Always stops immediately
2. **Line of Sight lost** - Stops if target moves behind a wall
3. **Overheal threshold exceeded** - Stops if the heal would waste too much health

### Stopcasting Settings

These settings control when QuickHeal stops a cast:

#### **StopcastCheckWindow** (Default: 0)
Controls **when** the addon checks for stop conditions during a cast.

- **0** = Always check from the start of the cast
- **1.5** = Only check if ≤ 1.5 seconds remain in the cast
- **3.0** = Only check if ≤ 3 seconds remain

**Use case**: Set to 0 for maximum safety. Set higher if you want to avoid interruptions early in long casts.

#### **MaxOverhealPercent** (Default: 50)
Controls **how much overheal** is tolerated before stopping.

- **0** = Never stop for overheal
- **50** = Stop if heal is ≥ 50% overheal (half the heal is wasted)
- **100** = Stop only if target is already at full health

**Use case**: Lower values prevent waste but may interrupt needed heals. Higher values complete more heals but waste more mana.

### Example Scenarios

**Scenario 1**: You're casting a 3-second heal on a tank taking damage.
- `StopcastCheckWindow = 0`, `MaxOverhealPercent = 50`
- At 1.5 seconds remaining, tank gets a big heal from another healer
- QuickHeal calculates: heal would be 70% overheal → **STOPS** the cast

**Scenario 2**: You're casting a 1.5-second Flash Heal on a low-health DPS.
- `StopcastCheckWindow = 1.5`, `MaxOverhealPercent = 50`
- Since remaining time (1.5s) equals the window (1.5s), checks run
- DPS moves behind a pillar → **STOPS** the cast (LOS)

**Scenario 3**: You want to always complete your casts.
- `StopcastCheckWindow = 3.0`, `MaxOverhealPercent = 100`
- Most casts complete unless target dies or is already full health

### Tips

- **PvP**: Use low `StopcastCheckWindow` (0-0.5) to react quickly to target changes
- **Raid healing**: Use moderate `MaxOverhealPercent` (30-50) to balance efficiency and safety
- **Tank healing**: Use high `MaxOverhealPercent` (70-100) to ensure tanks get every heal

---

## Keybindings

QuickHeal includes the following keybindings (accessible through WoW keybinding menu):

- **QuickHeal Heal** - Main healing function
- **QuickHeal HoT** - HoT casting function
- **QuickHeal HoT Firehose** - HoT firehose mode (Naxx gargoyles)
- **QuickHeal Heal Subgroup** - Heal configured raid subgroups
- **QuickHeal HoT Subgroup** - HoT configured raid subgroups
- **QuickHeal Heal Party** - Heal party members only
- **QuickHeal Heal MT** - Heal main tanks only
- **QuickHeal HoT MT** - HoT main tanks only
- **QuickHeal Heal NonMT** - Heal non-tanks only
- **QuickHeal Heal Self** - Heal yourself only
- **QuickHeal Heal Target** - Heal current target
- **QuickHeal Heal Target's Target** - Heal your target's target
- **QuickHeal Toggle Healthy Threshold** - Toggle between Normal and High HPS modes
- **QuickHeal Show/Hide Downrank Window** - Toggle downrank slider

---

## Troubleshooting

**Heals not stopping when they should:**
- Check that `StopcastCheckWindow` is not too high
- Verify `MaxOverhealPercent` is set appropriately
- Ensure `StopcastEnabled` is checked in config

**Heals stopping too often:**
- Increase `MaxOverhealPercent` to allow more overheal
- **Decrease** `StopcastCheckWindow` to check later in the cast (e.g., from 1.5 to 0.5)
- Check if target is frequently moving out of LOS

**AddOn not working:**
- Make sure folder is named `QuickHeal` (not `QuickHeal-main`)
- Check that all required libraries are present in the `libs` folder
- Try `/reload` to refresh the UI
- Run `/qh dll` to check for DLL enhancement status

**Unit frames not responding to click healing:**
- Ensure QuickClick is enabled in configuration
- Check that your unit frame addon is supported (Blizzard, Discord, Perl, X-Perl, EasyRaid, CT Raid Assist)
- Verify Ctrl key is being held while clicking
