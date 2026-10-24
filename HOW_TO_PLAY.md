# How to play Iron & Angles

You run a mercenary artillery battery. You **bid for contracts**, then **shell the targets**. Every shell costs money, so the fewer shots you need, the more you keep.

```
Region Map (bid, shop, research)  →  Battle (aim and fire)  →  Results (profit)  →  back to the map
```

Start: **Main Menu → New Campaign**. You begin with **5,000 funds**, a **Trebuchet** and **20 Stone Balls**.

---

## 1. Region Map: win a contract

The map is on the left. The **Auction / Shop / Battery** tabs are on the right.

1. **Pick a plot.** The land is new every week: each contract comes with one or two freshly surveyed plots, each with its own terrain, distance, height and weather. Each contract this week is listed with its plots. Click a plot (its tag on the map, or its chip in the list). The **Selected lot** card shows:
   - **Payout:** what you're paid if you win the battle.
   - **Reserve:** the minimum bid.
   - **Plot:** the terrain type, your height advantage, and the **distance to the targets**. Closer and higher is easier.
   - **Difficulty:** how accurately the enemy fires back.
   The card also has a **Bid advisor**:
   - **Shells (est.):** what your *deployed* guns will probably spend on shells here (assuming about 40% of shots hit), and what it would cost if every shot hit.
   - **Break-even bid:** bid more than this and you lose money even if you win the battle.
   - **Rivals:** each rival's likely bid range, whether this is the contract they're probably after (they each bid on one contract a week), and how often they sit a week out.
   - **Suggested bid:** enough to beat the likely rivals. Click **Use** to put it in the bid box. It turns red when winning isn't worth it.
2. **Bid.** Set an amount in the number box and click **Place sealed bid**. You get one bid per week. Bidding again replaces your old bid.
3. **Close bidding.** The rivals (shown under "Rival war chests") bid too. The highest bid wins and pays it **up front**. If bids tie, the earlier bid wins.
4. Then:
   - **You won:** click **Deploy to battle**.
   - **You lost:** click **Next week** for new offers.

**Before deploying, check the Shop tab.** 20 stones isn't much. A target with 150 HP needs about 3 direct hits from a 60-damage stone ball, and you'll miss a lot at first. Buy ammo here; firing it later costs the full shell price.

Other buttons:
- **Research** (top bar) opens the tech tree. Spend funds to unlock better weapons and ammo, which then appear in the Shop. An **era gate** node moves you into the next era (Industrial → Modern → Experimental).
- **Battery tab:** your guns. Only **deployed** guns go to battle, and the battery has limited slots: **2** in the Medieval era, **3** in the Industrial and Modern eras, **4** in the Experimental era. Click **Deploy** or **Stand down** to choose. Each gun shows whether it **reaches the selected plot**. A destroyed gun (0 hp) can't deploy until it's repaired. A newly bought gun deploys automatically if a slot is free.
  - **Repair** fixes battle damage.
  - **Sell** returns **50% of the price, minus what the damage would cost to repair**. Ammo stays in stock. You can't sell your last gun. The free starting trebuchet sells for nothing.
  - Old guns still have a use: a cheap gun on the pad draws some of the enemy's fire away from your expensive one.
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
| **D / A** or **→ / ←** | Next / previous **charge** (propellant increment: Charge 1 = weakest) |
| hold **right mouse** | **Rangefinder**: read the range and height of any ground point; release to send it to the firing table |
| **G** | **Relocate** ("shoot and scoot"): guns silent for 15 s, then the enemy has lost most of its fix on you (60 s cooldown) |
| hold **Shift** | Fine adjustment, 10× slower |
| Mouse wheel / Shift + wheel | Elevation / charge in small steps |
| **Space** | **Fire** |
| **Tab** or **E** | Next weapon (if you own several) |
| **R** | Next ammo type |
| **T** | **Firing table**: where your selected gun and ammo land at each angle and charge (still air) |
| **F** | **Fire-control computer**: dials in the nearest standing target (needs the *Fire Control Computers* research) |
| **X** | **Split screen** on/off: your battery on the left, the observer's view of the targets on the right (on by default when the targets are off-screen) |
| **V** | Overview camera (battery, targets and enemy on one screen) |
| **Esc** | Retreat. This is a defeat: no payout. |

### How to aim

There's no crosshair. You **pick a charge, dial an elevation**, fire, and **correct from where the shot landed** (see *Gunnery* below for the full crew drill):

1. Watch the shell fly. In split screen it leaves on the left and lands on the right; the minimap at the top shows the whole flight.
2. Your previous shot stays on screen as a **faint line with a circle where it landed**, labelled with the angle and charge you used, and the **observer calls it** (SHORT 40 m, OVER 25 m...).
3. Correct with **elevation** (W/S, hold **Shift** for fine steps):
   - At a **low angle** (under 45°): short → raise the barrel, over → lower it.
   - At a **high angle** (over 45°): it's the other way round. Short → lower the barrel toward 45°, over → raise it.
   - If no elevation reaches, change **charge** (A/D).
4. Read the **wind** arrow. `→` pushes your shells further, `←` holds them back. The shaded band is the gust range: gusts make each shot vary a little.
5. Stone balls **bounce**, and the bounce direction is a bit random. A bounce still does half damage.

**Trebuchet tip:** the medieval plots (220–300 m away) need the basic trebuchet on **Charge 5** (it reaches 190–300 m); the Great Trebuchet covers them on Charge 4 or 5. The firing table (T) is pre-filled with the target's range in the Medieval era: read the elevation off its amber line.

**Railguns** (Experimental era) fire almost dead straight, so you aim them like a rifle. A railgun needs a **clear line to the targets**: its plots are level ground or slightly uphill. The angle dial moves **10× finer** for them and shows hundredths of a degree, because at 2 km, 0.05° is about 2 m. Railguns can't see the enemy gun behind the targets, so keep a howitzer in your battery to fight the duel.

### Gunnery: how real crews aim

You aim the way artillery crews do:

1. **Choose a charge.** Charge is a fixed **propellant increment** (A/D steps through Charge 1–5; the heavy howitzer has 8). Each charge reaches a band of ranges; the **elevation** (W/S) fine-tunes inside it.
2. **Measure the target.** Hold the **right mouse button** on the target in either pane: the **rangefinder** reads its **range** and **height** (above + or below − your battery). Release, and the numbers go into the firing table. In the Medieval era the table is pre-filled for you; later you measure yourself.
3. **Read the firing table (T).** It's laid out like a real one: for your gun, ammo and **current charge**, each **RANGE** row gives the **LOW** and **HIGH** angle elevation, the **time of flight**, and the **wind** correction (meters the shot moves per 1 m/s of tailwind). The amber line reads off your measured range: the elevation to dial. If it says "out of reach", change charge.
4. **Correct for wind yourself.** Tailwind (→) of 3 m/s and WIND +1.5 means the shot lands about 4–5 m long: aim a little shorter (lower elevation at low angle).
5. **Fire and listen to the observer.** After each shot the forward observer calls it: **SHORT 40 m**, **OVER 25 m**, **ON LINE, CLOSE** or **TARGET HIT**. Bracket like a real crew: once you have one short and one over, split the difference.

**Fire-control computer (F).** Once you've researched **Fire Control Computers** (the Modern-era gate), the panel also shows a charge and elevation for each standing target and the spotted enemy gun, corrected for the mean wind. **Apply** (or **F** for the nearest target) dials it in. It doesn't predict gusts or spread.

**Shoot and scoot (G).** Every shot raises Revealed. When the enemy starts landing near you, **relocate**: your guns go silent for 15 s while they move, then the enemy has lost most of its fix (Revealed drops to a quarter). It has a 60 s cooldown.

**Split screen and minimap.** When the targets are off-screen, the battle splits: your battery on the left, the observer's view of the targets on the right (X toggles). The strip at the top is a **minimap** of the whole field, so you can follow every shell from launch to impact.

### Reload and reveal

- After each shot the weapon **reloads** (the trebuchet takes 12 s). The reload bar fills up and then shows `READY [Space]`.
- Every shot raises the **Revealed** meter, and misses raise it more. Past the red **return fire** mark (10%), the enemy starts **firing back** (red shells), and gets more accurate as Revealed rises. If all your weapons are destroyed, you lose.

### Counter-battery: the duel

- The enemy has **one gun** somewhere behind the targets. It's **hidden** until it fires: its first shot's **red muzzle flash** gives its position away. (Hitting it by luck also reveals it.) The HUD shows `ENEMY GUN: HIDDEN → SPOTTED → DESTROYED`.
- Once spotted, it's drawn with a health bar and **you can shoot it**. It has about as much HP as one of your own guns, so in later eras **two good hits** usually finish it.
- **Destroying it silences return fire for the rest of the battle.** You still need to destroy the contract targets to win.
- **Counter-battery bonus:** if you destroy the gun *and* win, the client adds **10% of the payout**.
- In later eras its shells have big blasts, so it often hits on its first or second shot. When it fires, **switch to the gun and make your first shot count**.

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
