# QuickHeal for Turtle WoW

QuickHeal automates healing spell selection and targeting for healers. It finds the lowest health party or raid member, picks the best spell rank for the deficit and your mana, and casts it — no manual targeting required. Works with Priest, Druid, Paladin, and Shaman.

## Installation

Download QuickHeal into your `Interface/AddOns` folder. Ensure the folder is named `QuickHeal` (remove any `-main` suffix).

## General Commands

| Command | Description |
|---------|-------------|
| `/qh` | Heal the lowest health target |
| `/qh cfg` | Open configuration panel |
| `/qh dr` or `/qh downrank` or `/qh ranks` | Open downrank/minrank slider window |
| `/qh toggle` | Toggle between Normal HPS and High HPS mode |
| `/qh tanklist` or `/qh tl` | Toggle main tank list display |
| `/qh dll` | Report DLL enhancement status |
| `/qh test on\|off` | Toggle test mode (ignores health thresholds) |
| `/qh debug on\|off` | Toggle debug output |
| `/qh reset` | Reset configuration to defaults |

### Target Masks

Constrain who can be healed by adding a mask before the command:

| Mask | Targets |
|------|---------|
| `player` | Yourself only |
| `target` | Your current target |
| `targettarget` | Your target's target |
| `party` | Party members only |
| `subgroup` | Configured raid subgroups |
| `mt` | Main tanks only |
| `nonmt` | Non-tanks only |

Examples: `/qh mt` heals only tanks. `/qh party hot` casts a HoT on a party member.

### Heal Types and Modifiers

| Suffix | Effect |
|--------|--------|
| `heal` | Direct heal (default) |
| `hot` | HoT spell (Renew, Rejuvenation) |
| `heal max` | Direct heal at max rank |
| `hot max` | HoT at max rank |
| `hot fh` | Firehose — max rank HoT ignoring HP check |

### HPS Modes

**Normal HPS**: Uses the full spell pyramid (Lesser Heal / Heal / Greater Heal, Healing Touch, Holy Light, Healing Wave) for mana efficiency.

**High HPS**: Restricted to fast-cast spells (Flash Heal, Regrowth, Flash of Light, Lesser Healing Wave) for maximum throughput at the cost of mana.

Toggle with `/qh toggle`.

---

## Priest

**Spells used**: Lesser Heal, Heal, Greater Heal, Flash Heal, Renew, Prayer of Healing

### Commands

| Command | Description |
|---------|-------------|
| `/qh` | Optimal direct heal on lowest health target |
| `/qh hot` | Renew on lowest health target without an active HoT |
| `/qh hot max` | Max rank Renew |
| `/qh hot fh` | Firehose — spam max rank Renew ignoring HP check |
| `/qh book` | Book of Prayer heal — alternates Greater Heal and Flash Heal |
| `/qh poh` | Prayer of Healing on the raid group with highest total deficit |
| `/qh [mask] book` | Book of Prayer with a target mask (e.g. `/qh mt book`) |

### Book of Prayer

The `/qh book` command alternates between Greater Heal and Flash Heal to trigger the Book of Prayer talent, which refunds 15%/30% of a healing spell's mana cost when it differs from the previous healing spell. Rank selection still follows your downrank and minrank settings.

### Prayer of Healing

The `/qh poh` command scores each raid subgroup by total health deficit (the sum of missing HP across all members in the group). The group with the highest combined deficit is selected, and Prayer of Healing is cast on a member of that group. This prefers groups with multiple injured members over groups with a single heavily damaged player.

In a party (not raid), `/qh poh` targets yourself since Prayer of Healing heals the target's party within 36 yards.

### Recommended Macros

```
/qh
```
Basic heal — selects optimal direct heal spell and rank.

```
/qh hot
```
Cast Renew on the lowest health target without an active HoT.

```
/qh book
```
Alternating GH/FH heal for Book of Prayer mana refund.

```
/qh poh
```
Prayer of Healing on the most injured raid group.

---

## Druid

**Spells used**: Healing Touch, Regrowth, Rejuvenation

### Commands

| Command | Description |
|---------|-------------|
| `/qh` | Optimal Healing Touch or Regrowth based on health threshold |
| `/qh ht` | Force Healing Touch |
| `/qh rg` | Force Regrowth |
| `/qh hot` | Rejuvenation on lowest health target without an active HoT |
| `/qh hot max` | Max rank Rejuvenation |
| `/qh hot fh` | Firehose — spam max rank Rejuvenation |
| `/qh [mask] ht` | Force Healing Touch with a target mask |
| `/qh [mask] rg` | Force Regrowth with a target mask |

### Recommended Macros

```
/qh
```
Basic heal — selects Healing Touch or Regrowth based on the healthy threshold.

```
/qh hot
```
Cast Rejuvenation on the lowest health target without an active HoT.

```
/script QuickHeal(nil,'Swiftmend')
```
Cast Swiftmend (works while moving).

```
/script QuickHeal(nil,'Regrowth')
```
Force max rank Regrowth regardless of heal need.

---

## Paladin

**Spells used**: Holy Light, Flash of Light, Holy Shock

### Commands

| Command | Description |
|---------|-------------|
| `/qh` | Optimal Holy Light or Flash of Light |
| `/qh hs` | Holy Shock on lowest health target (cancels autoattack) |
| `/qh hs max` | Max rank Holy Shock |
| `/qh heal max` | Max rank Flash of Light (or Holy Light with Holy Judgement buff) |

### Blessing of Protection

```
/run qhBoP(20)
```
Cast Blessing of Protection on the lowest HP ally below the given threshold (20% in this example).

### Melee Paladin Macros

These macros do not cancel autoattack:

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

### Commands

| Command | Description |
|---------|-------------|
| `/qh` | Optimal Healing Wave or Lesser Healing Wave |
| `/qh chainheal` | Chain Heal on lowest health target |
| `/qh chainheal max` | Max rank Chain Heal |

### Recommended Macros

```
/qh
```
Basic heal — selects optimal Healing Wave or Lesser Healing Wave rank.

```
/qh chainheal
```
Cast Chain Heal on the lowest health target.

---

## Configuration

Open the config panel with `/qh cfg`. Key settings:

- **Healthy Threshold**: HP percentage above which targets are skipped. Below this threshold, fast heals (Flash Heal, Regrowth, etc.) are used in combat; above it, slow efficient heals are used.
- **Force Self-Heal**: Prioritize self when below this HP percentage.
- **Target Priority**: Always heal current target first if they need healing.
- **Subgroups**: Select which raid groups to include when healing.
- **Tank List**: Add tanks via `/qh tanklist` then click `+` with a tank targeted.

### Downranking

Open the downrank window with `/qh dr`. Two sliders control the rank range:

- **Max rank**: Upper bound on spell rank QuickHeal will use.
- **Min rank**: Lower bound — QuickHeal will never pick a rank below this.

This lets you cap mana usage or force higher ranks for throughput.

### QuickClick (Mouse-Click Healing)

QuickClick lets you heal by Ctrl+clicking unit frames instead of using slash commands. When enabled, holding **Ctrl** and **left-clicking** any supported unit frame calls QuickHeal directly on that unit — it picks the best spell rank for their deficit and casts it immediately, bypassing the normal "find lowest health" search.

If Ctrl is not held, the click behaves normally (targeting, selecting, etc.).

**Supported unit frames:**
- Blizzard default frames (player, pet, target, target-of-target, party)
- pfUI
- CT Raid Assist
- EasyRaid
- Discord Unit Frames
- Perl Classic / X-Perl

Enable or disable QuickClick in the configuration panel (`/qh cfg`).

---

## Stopcasting

QuickHeal includes intelligent stopcasting to prevent wasted heals. When a heal is in progress, it monitors conditions and can cancel the cast.

### Stop Conditions

1. **Target dies** — always stops immediately.
2. **Line of Sight lost** — stops if target moves behind a wall (requires UnitXP).
3. **Overheal threshold exceeded** — stops if the heal would waste too much health.

### Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `StopcastCheckWindow` | 0 | Only check stop conditions when this many seconds or fewer remain in the cast. 0 = always check. |
| `MaxOverhealPercent` | 50 | Stop the cast if overheal would exceed this percentage. 0 = never stop for overheal. 100 = stop only at full health. |

### Tips

- **PvP**: Low `StopcastCheckWindow` (0–0.5) to react quickly.
- **Raid healing**: Moderate `MaxOverhealPercent` (30–50) for efficiency.
- **Tank healing**: High `MaxOverhealPercent` (70–100) to ensure heals land.

---

## Aggro Detection and Pre-Healing

QuickHeal detects when friendly units are being targeted by enemies and can pre-heal them before damage lands.

### Detection Methods

- **GUID-based tracking**: Compares enemy target GUIDs with friendly unit GUIDs (requires Nampower DLL).
- **UnitIsUnit fallback**: Traditional method using unit ID comparison.

### Settings

Configure in the configuration panel:

- **Precast Aggro Targets**: Heal targets with aggro even above the normal healthy threshold.
- **Pre-HOT Aggro Targets**: Cast HoTs on aggro targets preemptively.
- **Aggro Target Preference**: Heal highest or lowest max-health aggro target first.

---

## Keybindings

Accessible through the WoW keybinding menu:

| Keybind | Action |
|---------|--------|
| QuickHeal Heal | Main healing function |
| QuickHeal HoT | HoT casting |
| QuickHeal HoT Firehose | HoT firehose mode |
| QuickHeal Heal Subgroup | Heal configured raid subgroups |
| QuickHeal HoT Subgroup | HoT configured raid subgroups |
| QuickHeal Heal Party | Heal party members only |
| QuickHeal Heal MT | Heal main tanks only |
| QuickHeal HoT MT | HoT main tanks only |
| QuickHeal Heal NonMT | Heal non-tanks only |
| QuickHeal Heal Self | Heal yourself |
| QuickHeal Heal Target | Heal current target |
| QuickHeal Heal Target's Target | Heal your target's target |
| QuickHeal Toggle Healthy Threshold | Toggle HPS mode |
| QuickHeal Show/Hide Downrank Window | Toggle downrank slider |

---

## DLL Enhancements

QuickHeal can utilize optional DLL enhancements for improved functionality. Run `/qh dll` to check which are detected.

### Nampower

- `GetCastInfo` — accurate cast time tracking
- `IsSpellInRange` — reliable range checking
- `GetUnitField` — read unit health/mana directly from memory
- `GetSpellModifiers` — spell coefficient and modifier data
- `GetPlayerAuraDuration` — buff/debuff duration tracking
- Spell pushback and failure event handling

### UnitXP_SP3

- `UnitXP("distanceBetween")` — accurate distance measurement (40-yard range check)
- `UnitXP("inSight")` — line of sight detection

### SuperWoW

- `SpellInfo` — spell information lookup
- GUID-based targeting — cast on specific units without switching target

---

## HealComm Integration

QuickHeal includes QHealComm, a HealComm-compatible library that broadcasts incoming heal information to other healers. When pfUI is loaded, QHealComm delegates to pfUI's libpredict for seamless interop. When pfUI is absent, QHealComm runs a standalone implementation that sends and receives the same HealComm messages.

This means:
- Other healers using pfUI, HealComm, or QuickHeal can see your incoming heals.
- QuickHeal subtracts other healers' incoming heals when selecting targets, reducing overheal.
- HoT durations (Renew, Rejuvenation, Regrowth) and resurrections are tracked.

---

## Troubleshooting

**Heals not stopping when they should:**
- Check that `StopcastCheckWindow` is not too high.
- Verify `MaxOverhealPercent` is set appropriately.
- Ensure stopcasting is enabled in config.

**Heals stopping too often:**
- Increase `MaxOverhealPercent` to allow more overheal.
- Decrease `StopcastCheckWindow` to check later in the cast.

**AddOn not working:**
- Make sure folder is named `QuickHeal` (not `QuickHeal-main`).
- Check that all required libraries are present in the `libs` folder.
- Try `/reload` to refresh the UI.
- Run `/qh dll` to check DLL status.

**Unit frames not responding to click healing:**
- Ensure QuickClick is enabled in configuration.
- Check that your unit frame addon is supported.
- Verify Ctrl key is being held while clicking.

---

## Credits

QuickHeal was originally created by Thomas Thorsen, Scott Geeding, and Kostas Karachalios, with contributions from the Turtle WoW community.
