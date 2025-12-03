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
