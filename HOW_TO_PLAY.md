# How to play Iron & Angles

You run a mercenary artillery battery. You **bid for contracts**, then **shell the targets**. Every shell costs money, so the fewer shots you need, the more you keep.

```
Region Map (bid, shop, research)  →  Battle (aim and fire)  →  Results (profit)  →  back to the map
```

Start: **Main Menu → New Campaign**. You begin with **5,000 funds**, a **Trebuchet** and **20 Stone Balls**.

---

## 1. Region Map: win a contract

The map is on the left. The **Auction / Shop / Repair** tabs are on the right.

1. **Pick a plot.** Each contract this week is listed with its plots. Click a plot (its tag on the map, or its chip in the list). The **Selected lot** card shows:
   - **Payout:** what you're paid if you win the battle.
   - **Reserve:** the minimum bid.
   - **Plot:** the terrain type, your height advantage, and the **distance to the targets**. Closer and higher is easier.
   - **Difficulty:** how accurately the enemy fires back.
2. **Bid.** Set an amount in the number box and click **Place sealed bid**. You get one bid per week. Bidding again replaces your old bid.
3. **Close bidding.** The rivals (shown under "Rival war chests") bid too. The highest bid wins and pays it **up front**. If bids tie, the earlier bid wins.
4. Then:
   - **You won:** click **Deploy to battle**.
   - **You lost:** click **Next week** for new offers.

**Before deploying, check the Shop tab.** 20 stones isn't much. A target with 150 HP needs about 3 direct hits from a 60-damage stone ball, and you'll miss a lot at first. Buy ammo here; firing it later costs the full shell price.

Other buttons:
- **Research** (top bar) opens the tech tree. Spend funds to unlock better weapons and ammo, which then appear in the Shop. An **era gate** node moves you into the next era (Industrial → Modern → Experimental).
- **Repair tab:** fixes battery damage taken in battle.
- **Autosave:** the campaign saves itself after every purchase, research, auction and battle. **Continue** on the main menu picks up where you left off. **New Campaign** asks before overwriting it.

---

## 2. Battle: hit the targets

The battle runs **in real time**. Your battery is on the left (the selected weapon is drawn in amber). The **red towers** to the right are the targets, each with a health bar. The ground is marked every 50 m from your battery.

The screen has three plates:
- **Top left:** the contract, one tower icon per target (crossed out when destroyed) and the clock.
- **Top right:** wind, rain and air density, the **Revealed** meter, shells fired and hit, and your funds.
- **Bottom left:** fire control: the weapon and its integrity, the **elevation dial** and the **charge column**, the ammo and its price per shot, and the **reload bar**.

### Controls

| Key | Action |
|---|---|
| **W / S** or **↑ / ↓** | Raise / lower the **elevation** (barrel angle) |
| **D / A** or **→ / ←** | More / less **charge** (launch power) |
| hold **Shift** | Fine adjustment, 10× slower |
| Mouse wheel / Shift + wheel | Elevation / charge in small steps |
| **Space** | **Fire** |
| **Tab** or **E** | Next weapon (if you own several) |
| **R** | Next ammo type |
| **V** | Overview camera (battery, targets and enemy on one screen) |
| **Esc** | Retreat. This is a defeat: no payout. |

### How to aim

There's no crosshair. You **dial in angle and charge**, fire, and **correct from where the shot landed**:

1. Watch the shell fly. The camera follows it, then comes back.
2. Your previous shot stays on screen as a **faint line with a circle where it landed**, labelled with the angle and charge you used (`last: 31.0° / 88.0%`).
3. Correct:
   - **Fell short** → add charge. **Overshot** → reduce charge.
   - Change charge in small steps (1–3%). Hold **Shift** for precision.
   The dial and the charge column also show your last shot's settings as amber ticks.
4. Read the **wind** arrow. `→` pushes your shells further, `←` holds them back. The shaded band is the gust range: gusts make each shot vary a little.
5. Stone balls **bounce**, and the bounce direction is a bit random. A bounce still does half damage.

**Trebuchet tip:** it starts at 50° and 50% charge, which is far too weak. The medieval plots (220–300 m away) are hit at about **30–35° and 75–100% charge**. Start at around **30°, 85%** and adjust from there.

### Reload and reveal

- After each shot the weapon **reloads** (the trebuchet takes 12 s). The reload bar fills up and then shows `READY [Space]`.
- Every shot raises the **Revealed** meter, and misses raise it more. Past the red **return fire** mark (10%), the enemy starts **firing back** (red shells), and gets more accurate as Revealed rises. If all your weapons are destroyed, you lose.

### Winning and losing

- **Victory:** every target is destroyed. You're paid the contract payout.
- **Defeat:** all your weapons are destroyed, you run out of time (on contracts with a time limit), or you press Esc. You get no payout, and the shells and auction price are still spent.

---

## 3. Results: did you make money?

| Line | Meaning |
|---|---|
| **Payout** | What the client paid |
| **Auction price** | What you bid (already paid) |
| **Shells fired** | What you spent on ammo |
| **Net profit** and margin | What you actually earned |
| **Repairs needed** | What fixing the battle damage will cost |

Continue takes you back to the map for next week's auction.

---

## Strategy in one paragraph

Don't overbid: a 2,000 bid on a 2,200 payout leaves almost nothing for shells. Choose plots that are **close and high**. Stock enough ammo before you deploy. Take a few careful ranging shots rather than rushing, because every miss costs money **and** helps the enemy find you. Spend profits on research to reach rifled cannons (Industrial era). They fly much flatter and hit far more often.
