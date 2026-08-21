# Prompt: frame 3, "calorie intake" — Total Calories 1.8.2

Paste everything below the line into whatever builds the frame.

---

Build one App Store screenshot for the iOS app **Total Calories**, to sit third
in an existing nine-frame set. It must look like it came from the same set, so
match the established treatment exactly rather than inventing a new one.

## Source capture

Use `raw-calorie-intake-1206x2622.png` in this folder. It is a real simulator
capture, not a mockup. Do not re-render, retouch, or rebuild the UI — composite
this exact image into the device frame.

It shows, top to bottom:

- the calorie ring at **2,400 / 2,500 cal**
- a green pacing pill, **420 cal ahead of usual pace**
- **+450 deficit**, with **2,400 burned − 1,950 eaten** beneath it
- a **MACROS** card: 142 g protein, 186 g carbs, 61 g fat, and the
  31% · 40% · 29% split

Steps are deliberately absent. The whole point of the frame is that every number
on screen is a calorie, so the reader sees burn, intake, and macros as one
picture. Do not add a steps row back in.

## Header

Two lines, no terminal punctuation. Line 1 is near-black and regular weight;
line 2 is the coral accent, italic, bold — the same two-tone treatment as
"Know your / **total burn**" on frame 1 and "See your / **macros**" on the
current macro frame.

Use, in preference order:

1. `Burned, eaten,` / `and macros`
2. `Every calorie` / `in one view`
3. `The whole` / `calorie picture`

Option 1 is the recommendation: it names the three things actually visible and
its second line lands on the release's new feature.

## Layout and treatment

- Canvas **1284 x 2778**, RGB, **no alpha**.
- Header occupies roughly the top quarter; device frame below it, bleeding off
  the bottom edge like frames 1, 5 and 6.
- Background: warm cream, consistent with frames 1 and 2. A soft out-of-focus
  food photograph is acceptable if it stays quiet enough that the ring and the
  deficit figure remain the first things the eye lands on — this frame carries
  more small type than any other in the set, so contrast matters more than mood.
- Keep at least 60% of the canvas as actual app UI.
- Headline must stay legible at thumbnail size; this frame appears in search
  results.

## Output

Deliver as `03-calorie-intake.png`, 1284 x 2778, RGB, no alpha.

## Where it lands

Frame 3 of 9, between "Keep it on your wrist" and "See what makes your burn".
Final order:

1. Know your total burn
2. Keep it on your wrist
3. **this frame**
4. See what makes your burn (active vs resting)
5. Find your daily patterns (history)
6. Burned minus eaten (net deficit)
7. Set your macro goals
8. Spot your macro patterns
9. Read it in dark mode
