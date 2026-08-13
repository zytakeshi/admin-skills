---
name: html
description: Create a single self-contained animated HTML page that explains a concept, system, dataset, algorithm, or product. Triggers on "make an HTML explainer", "animate this", "visualize how X works", "build an interactive demo", "scrollytelling page", "explain to a non-technical person with a website", "consulting deck as a webpage", "show me X as an animation", or any variation requesting a polished, self-contained HTML artifact (no build step, no framework). Optimized for scrollytelling explainers, technical visualizations, dashboards, and architecture diagrams in dark mode, with full CJK (Chinese / Japanese / Korean) font support.
---

# HTML Specialist

You build **one self-contained `.html` file** — HTML + CSS + JS inline, opens by double-click, runs in any modern browser — that visually explains a concept, system, dataset, or process. Think motion designer + software architect: every frame and every pixel serves the idea.

This skill was distilled from real-world consulting decks and architecture explainers — single-file scrollytelling pages around 60 KB that explain a multi-layer system to a non-technical audience in 6–8 scrollable sections.

---

## Mission

Produce **one** `.html` file. No build step. No bundler. Zero external dependencies by default — and if a CDN script is absolutely needed (D3, three.js), pin the version, justify it, and add a graceful fallback.

The viewer must, in one scroll, walk away with the **one key insight** you set out to deliver.

---

## Execution path — delegate generation to Antigravity

For this skill, the calling agent (Claude, Codex, or another compatible agent) is the **orchestrator and reviewer — not the author**. The HTML generation job itself must be delegated to a coding CLI: by default the Antigravity CLI (`agy`); the Grok CLI (`grok`) is a supported alternative when the user asks for it. Delegate unless the user explicitly opts out.

**Why delegate: token discipline.** The whole point of this skill is to keep a ~60 KB artifact *out of the orchestrator's context window*. The generator writes the file straight to disk; you never read it back in full and you never let it stream into chat. Validation is therefore deliberately lightweight (see *Validate frugally* below). If you catch yourself reading the entire HTML into context, opening it in a headless browser, or taking screenshots, you have defeated the skill's purpose — stop.

1. Clarify intent and choose the output path.
2. Write a short, self-contained delegation prompt that includes the user's request, the chosen path, and the requirements in this skill.
3. Run `agy` in non-interactive print mode and let it create the `.html` file. Put the prompt immediately after `--print`; otherwise the CLI may treat the next flag as the prompt.

```bash
cd "<output-directory-or-workspace-root>" && \
agy --dangerously-skip-permissions \
  --add-dir "<output-directory-or-workspace-root>" \
  --print "$(cat "<delegation-prompt>.md")" \
  --print-timeout 15m
```

Use `--add-dir` for the directory where the file should be written. Use `--dangerously-skip-permissions` only for this delegated local artifact generation flow so Antigravity can create the file without stalling on tool prompts.

**Alternative generator — Grok CLI (`grok`)**, when the user asks for it. Grok is a full agentic coder; run it in write mode scoped to the output directory (verified working):

```bash
grok --prompt-file "<delegation-prompt>.md" \
  --permission-mode bypassPermissions \
  --no-plan \
  --cwd "<output-directory-or-workspace-root>" \
  </dev/null \
  > /tmp/grok_html_events.jsonl 2> /tmp/grok_html.err
```

- `--permission-mode bypassPermissions` is the write-capable analog to `agy --dangerously-skip-permissions`; do NOT add a read-only `--tools` allowlist here (that blocks `write_file`). Leave default tools on so `write_file` is available.
- Run it in the background and watch progress with the Grok progress filter (see the `grok` skill); the file is written via Grok's silent `write_file` tool, and Grok's final text is its self-validation report.
- Note: Grok may *claim* it "used agy" — a confabulation. Ignore the claim; verify the file on disk per *Validate frugally*.

The delegation prompt must contain this contract:

```text
You are generating an artifact for the html skill.
Create exactly one self-contained HTML file at: <absolute-output-path>
Do not create a build step, package.json, framework app, image assets, or extra source files.
Keep CSS and JS inline. Avoid external dependencies unless absolutely required; if used, pin versions and add a graceful fallback.
Include an inline data URI favicon or equivalent so browsers do not emit a missing `/favicon.ico` console error.
DELIVERY-CHANNEL RULE (decide BEFORE designing): if the artifact will be delivered as a FILE ATTACHMENT (Telegram, email, chat upload) rather than a hosted URL, assume the preview it opens in (iOS Quick Look — what Telegram/Mail hand HTML files to — and similar document viewers) supports NO interactivity at all: no JS, no CSS :checked/:hover tricks, no details/summary toggling, no links. The complete story must be told by the static initial state alone — before/after and this-vs-that comparisons rendered side-by-side (dual bars, ghost overlays, paired columns), NEVER gated behind a toggle/tab/slider. Interactive controls are browser-only extras, and anything they reveal must ALSO be fully visible statically. When in doubt about the channel, design for the attachment case — it is the strictly-safer superset.
INTERACTIVE CONTROLS MUST BE RELIABLE AND SELF-EVIDENT (hard requirement): (a) attach event listeners DIRECTLY to each control element — never rely on event delegation from a container for primary controls (embedded/in-app webviews have quirky event-target behavior); (b) every control activation must produce an UNMISTAKABLE visible change — a status label/text change or clear color/mode shift, never only a subtle width or number delta the user can miss (a toggle whose only effect is 47%→42% bar widths reads as broken); (c) wrap EACH JS init routine in its own try/catch so one failure cannot disable the others; (d) reveal a JS-only control (remove `hidden`) only AFTER its listeners are attached, never before; (e) before reporting done, self-verify every control by simulating activation (dispatch a click) and asserting the expected DOM change actually happened.
STATIC-FIRST, JS AS ENHANCEMENT ONLY (hard requirement): all text, numbers, chart bars, and diagrams must exist as static HTML/CSS in the markup — the page must be fully readable with JavaScript disabled. Many mobile viewers (iOS Quick Look, which Telegram/Mail/Files hand HTML attachments to; some in-app browsers; email clients) strip or disable JS, and a JS-rendered page shows as a blank styled background there. JS may only ADD animation (count-ups, reveals, morphs, interactivity) on top of already-visible content. Concretely: (a) never build content DOM from a JSON blob at load time — bake the content in; (b) scroll-reveal elements must NOT default to opacity:0 in plain CSS — hide them only under a `.js` class that a first-line inline script adds to <html> (`document.documentElement.classList.add('js')`), so no-JS viewers see everything; (c) bar/funnel widths get static inline width styles, JS may re-animate them; (d) interactive-only controls (toggles, replay buttons) are hidden until `.js` is present.
Follow the html skill's standards: visual-first, before/after contrast, animated change, intuitive metaphor, plain language, responsive layout, reduced-motion support, keyboard-accessible controls, no console errors, and CJK-safe font stack when relevant.
After writing the file, run through the html skill's defensive checklist yourself and reply with the path and a concise PASS/FAIL note per item (self-contained, no-JS full content, no console errors, responsive, reduced-motion, favicon, keyboard-accessible, approx KB). Do not paste the full HTML.
```

If the generator is missing, not authenticated, or fails to write the file, report that clearly and retry once with a narrower prompt. If the retry still fails, fall back to the calling agent generating the single-file HTML directly and mention the failure in the final response.

### Validate frugally — do not read the file back into context

The generator already self-reported the checklist. Trust it, then spot-check **only from the shell** (a few tokens) — never slurp the 60 KB file (~15–20 K tokens) into context:

```bash
F="<absolute-output-path>"
[ -f "$F" ] && wc -c "$F"                                    # exists + size (target < ~90 KB)
grep -cE '<script[^>]*src=|<link[^>]*href=|//cdn' "$F"       # external deps → expect 0 (favicon xmlns is fine)
grep -c 'prefers-reduced-motion' "$F"                        # ≥ 1
grep -cE 'console\.(log|error|warn)|alert\(' "$F"            # expect 0
grep -c '<title>' "$F"                                       # 1
# static-first: key content must exist OUTSIDE <script> (no-JS viewers like iOS Quick Look strip JS)
grep -c "classList.add('js')" "$F"                           # ≥ 1 (.js gate for reveals)
awk '/<script/{s=1} /<\/script>/{s=0;next} !s' "$F" | grep -c '<KEY-CONTENT-STRING>'  # ≥ 1 — a real headline/number visible outside all <script> blocks
```

If a grep flags a concrete problem, read **only the offending region** (`grep -n '<pattern>' "$F" | head`) and make a surgical Edit. The first complete draft must come from the generator, not you.

**Do NOT, by default:** read the whole HTML into context, open it in a headless browser (chrome-devtools/playwright), or take screenshots. Those pull the artifact's full token cost back into the orchestrator and defeat the entire point of delegating. Do a browser render or screenshot **only when the user explicitly asks** to verify rendering or see a preview — and even then, prefer saving the screenshot to a file and surfacing it with `SendUserFile` over inlining it.

---

## Core principles — the five defaults you never skip

These are *why this skill exists*. They are the baseline, not the upgrade — the user should **never have to ask for them**. Apply all five on every page unless the user explicitly opts out.

### 1. Show, don't tell — visualization over prose
Default to a **diagram, animation, or visual metaphor**. Reach for text only when an idea genuinely can't be drawn. If a paragraph could be a picture, make it a picture; prose is the caption, not the content.

> **Before** (avoid): three paragraphs explaining how a firewall rejects a packet.
> **After** (prefer): an animated packet flying at a wall, bouncing off, with a one-line caption underneath.

Rule of thumb: **if a scene is mostly text, you haven't finished designing it.**

### 2. Before / after everywhere it fits
Contrast is the fastest teacher. Don't save before/after for the summary scene — use it at **every point where something changes**: the broken way vs. your way, naive vs. optimized, attack-succeeds vs. attack-blocked. Show the two states **side by side, or as a toggle/slider** — never as two separate paragraphs the reader has to hold in their head.

### 3. Animate the change, don't describe it
Anything that moves, flows, transforms, or fails over **should be shown moving**: a packet travels, a queue fills, a node lights up, a wall blocks. Static-then-static loses the "aha". Always honor `prefers-reduced-motion` (§4.5) — animation enriches the story, but the point must still land with motion off.

### 4. Make it intuitive — a non-expert gets it in 5 seconds
Lead with **physical, real-world metaphors** (locks, walls, pipes, traffic, doors, keys). Establish a consistent visual legend in the hero (one color = one role, §4.1) and never break it for the rest of the page. The viewer should *feel* the answer before they finish reading it.

### 5. Easy-to-understand language
Write for a smart person **outside the field**. Short sentences. Plain words over jargon. When a technical term is unavoidable, define it inline the first time in one clause. Default to the user's language; for CJK use the §4.2 font stack. Prefer "the server says no" over "the endpoint returns a 403".

> **Self-check before delivering:** could a non-technical friend scroll this once and explain the one insight back to you? If not, you've *told* instead of *shown* — go back to principle 1.

---

## Step 1 — Clarify intent (one tight round, then go)

Before writing a line of code, lock down:

1. **What** concept / data / process is being explained?
2. **Who** is the audience? What do they already know? Are they technical?
3. **What language?** Default to the user's language. For Chinese / Japanese / Korean, use the CJK font stack (§Tech Stack below).
4. **One insight rule:** what is the single sentence the viewer should remember? Everything in the file serves that sentence.
5. **Hosting / delivery channel?** Local file (`file://` double-click), Cloudflare Pages (wrangler), GitHub Pages, or **file attachment** (Telegram/email/chat)? Attachment delivery triggers the DELIVERY-CHANNEL RULE in the delegation contract: document previews (iOS Quick Look etc.) support zero interactivity, so the static initial state must carry the whole message. Unspecified → design for the attachment case.

If any of these would *substantially change the design*, ask one concise round. Otherwise state your assumptions in two lines and proceed.

**Don't over-ask.** One round of clarification, max. Build.

---

## Step 2 — Decompose into scenes

A scrollytelling explainer is a **timeline of discrete scenes**. Outline them first, before any code:

```
§1 HERO          — title + one-sentence promise + scroll cue
§2 PROBLEM       — what goes wrong without your design
§3 ANTAGONIST    — the threat / failure mode, dramatized
§4 OUR DESIGN    — the architecture, revealed layer by layer
§5 WHY IT WORKS  — the key insight, isolated on its own scene
§6 EDGE CASES    — common objections answered
§7 SUMMARY       — side-by-side before/after
§8 CTA / FOOTER  — credit, links, or call to action
```

Six to eight scenes is the sweet spot. Less = thin. More = the reader drops off.

For a non-scrollytelling page (dashboard, single interactive simulation, data viz), skip this and go straight to §4.

---

## Step 3 — Pick the rendering tech

| Goal                                | Use                          |
|-------------------------------------|------------------------------|
| Crisp diagrams, finite elements     | **SVG** (inline, `viewBox`)  |
| Many particles, pixels, high-FPS    | **Canvas 2D** with DPR scaling |
| UI-style transitions, reveals       | **CSS** + Web Animations API |
| Charts (when scale demands it)      | D3 v7 from CDN (pin version) |
| True 3D (rare)                      | three.js (pin version)       |

**Default to vanilla.** SVG + CSS + a single Canvas hero covers 90% of explainer needs.

---

## Step 4 — The validated tech stack (copy-paste foundations)

These are the patterns that proved clean in production. Start from these, then customize.

### 4.1 Color palette — dark-mode consulting

```css
:root {
  --bg:        #0a0e27;  /* deep navy background */
  --bg2:       #0d1230;
  --bg3:       #111840;
  --cyan:      #00d4ff;  /* "our side / safe / positive" */
  --cyan-dim:  rgba(0,212,255,0.15);
  --cyan-glow: rgba(0,212,255,0.40);
  --red:       #ff4757;  /* "threat / authority / failure" */
  --red-dim:   rgba(255,71,87,0.15);
  --amber:     #ffa502;  /* "neutral warning / accent" */
  --green:     #2ed573;  /* "running / success" */
  --text:      #e8eaf6;
  --text-dim:  rgba(232,234,246,0.55);
  --text-muted:rgba(232,234,246,0.35);
  --card:      rgba(255,255,255,0.04);
  --card-border: rgba(255,255,255,0.08);
}
```

Color logic: pick one role per color (e.g. cyan = primary, red = warning, amber = accent, green = success), establish in the hero, and repeat consistently — viewers internalize the legend in 5 seconds and follow it for the rest of the page.

### 4.2 CJK-safe font stack

```css
--font: -apple-system, "PingFang SC", "Hiragino Sans",
        "Microsoft YaHei", "Noto Sans CJK SC", sans-serif;
```

Covers macOS, iOS, Windows, Android, ChromeOS, Linux without any web-font download.

### 4.3 Fluid type scale

```css
h1 { font-size: clamp(32px, 5vw, 62px); font-weight: 800; line-height: 1.18; letter-spacing: -0.02em; }
h2 { font-size: clamp(24px, 3.5vw, 42px); font-weight: 700; line-height: 1.25; }
h3 { font-size: clamp(18px, 2.5vw, 26px); font-weight: 600; }
body { font-size: 18px; line-height: 1.7; }
```

`clamp()` is your friend — no media queries needed for typography.

### 4.4 IntersectionObserver scroll reveals

```html
<div class="reveal">...</div>
<div class="reveal reveal-delay-1">...</div>
```

```css
.reveal {
  opacity: 0;
  transform: translateY(36px);
  transition: opacity .7s cubic-bezier(.22,1,.36,1),
              transform .7s cubic-bezier(.22,1,.36,1);
}
.reveal.visible { opacity: 1; transform: translateY(0); }
.reveal-delay-1 { transition-delay: .1s; }
.reveal-delay-2 { transition-delay: .2s; }
.reveal-delay-3 { transition-delay: .3s; }
```

```js
const io = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (e.isIntersecting) {
      e.target.classList.add('visible');
      io.unobserve(e.target);
    }
  }
}, { threshold: 0.12, rootMargin: '-40px 0px' });

document.querySelectorAll('.reveal').forEach(el => io.observe(el));
```

**Threshold 0.12 + rootMargin -40px** is the sweet spot — reveals trigger when the element is ~12% on screen and slightly past the viewport edge. No jank, no premature fires.

Staggered cascade comes free from `.reveal-delay-N` classes.

### 4.5 Canvas particle hero (with DPR + cleanup)

```js
const cvs = document.getElementById('hero-canvas');
const ctx = cvs.getContext('2d');
let dpr = Math.max(1, window.devicePixelRatio || 1);
let W = 0, H = 0, particles = [], rafId = null;

function resize() {
  const r = cvs.getBoundingClientRect();
  W = r.width; H = r.height;
  cvs.width  = Math.floor(W * dpr);
  cvs.height = Math.floor(H * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function spawn() {
  particles = Array.from({ length: 48 }, () => ({
    x: Math.random() * W,
    y: Math.random() * H,
    vx: (Math.random() - 0.5) * 0.4,
    vy: (Math.random() - 0.5) * 0.4,
  }));
}

function tick() {
  ctx.clearRect(0, 0, W, H);
  for (const p of particles) {
    p.x += p.vx; p.y += p.vy;
    if (p.x < 0 || p.x > W) p.vx *= -1;
    if (p.y < 0 || p.y > H) p.vy *= -1;
    ctx.fillStyle = 'rgba(0,212,255,0.7)';
    ctx.beginPath(); ctx.arc(p.x, p.y, 1.5, 0, Math.PI * 2); ctx.fill();
  }
  // connection mesh
  for (let i = 0; i < particles.length; i++) {
    for (let j = i + 1; j < particles.length; j++) {
      const a = particles[i], b = particles[j];
      const d = Math.hypot(a.x - b.x, a.y - b.y);
      if (d < 140) {
        ctx.strokeStyle = `rgba(0,212,255,${0.18 * (1 - d / 140)})`;
        ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
      }
    }
  }
  rafId = requestAnimationFrame(tick);
}

function start() {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) { cvs.style.display = 'none'; return; }
  resize(); spawn(); tick();
}

window.addEventListener('resize', () => { cancelAnimationFrame(rafId); resize(); spawn(); tick(); });
start();
```

**48 particles** is the sweet spot. Visible mesh, low CPU. Above ~80 it starts to hitch on low-end phones. Below ~30 it looks sparse. Always honor `prefers-reduced-motion`.

### 4.6 Inline SVG architecture diagram

```html
<svg viewBox="0 0 900 240" width="100%" role="img" aria-label="System architecture">
  <defs>
    <marker id="arrow-cyan"  viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" fill="#00d4ff"/>
    </marker>
    <marker id="arrow-red"   viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" fill="#ff4757"/>
    </marker>
  </defs>
  <!-- nodes -->
  <rect x="40"  y="90" width="160" height="60" rx="10" fill="#111840" stroke="#00d4ff"/>
  <text x="120" y="125" text-anchor="middle" fill="#e8eaf6" font-size="14">Client</text>
  <!-- arrow -->
  <line x1="200" y1="120" x2="380" y2="120" stroke="#00d4ff" stroke-width="2"
        marker-end="url(#arrow-cyan)"/>
</svg>
```

Inline SVG: scales crisply at any DPI, no JS, fully styleable via CSS. Always set `role="img"` + `aria-label` for accessibility.

### 4.7 Staircase / ladder timeline

For "step 1 → 2 → 3 → conclusion" flows (e.g., showing the attacker's path of investigation):

```html
<ol class="ladder">
  <li class="step"><h4>Step 1</h4><p>...</p></li>
  <li class="step"><h4>Step 2</h4><p>...</p></li>
  <li class="step"><h4>Step 3 <span class="stop-badge">STOPS HERE</span></h4><p>...</p></li>
  <li class="step step-dim"><h4>Step 4 (never reached)</h4><p>...</p></li>
</ol>
```

Use `step-active` and `step-dim` classes to color-code which steps light up versus fade — drives the narrative of "they stop at step 3, never reach step 4".

### 4.8 Useful keyframes

```css
@keyframes danger-pulse {
  0%,100% { box-shadow: 0 0 0 0 var(--red-glow); }
  50%     { box-shadow: 0 0 0 14px rgba(255,71,87,0); }
}
@keyframes honey-pulse {
  0%,100% { filter: drop-shadow(0 0 6px var(--amber)); }
  50%     { filter: drop-shadow(0 0 18px var(--amber)); }
}
@keyframes packet-travel {
  from { transform: translateX(0); opacity: 1; }
  to   { transform: translateX(280px); opacity: 0; }
}
@keyframes scroll-cue {
  0%,100% { transform: translateY(0); opacity: .7; }
  50%     { transform: translateY(8px); opacity: 1; }
}
```

---

## Step 5 — Build order

Use this order inside the `agy` delegation prompt:

1. **Data / state model** — what are the entities, what state do they have?
2. **Static layout + CSS** — get the whole page looking right *before* adding animation.
3. **Reveals** — wire up IntersectionObserver scroll reveals.
4. **Hero animation** — canvas particles or whatever the splash is.
5. **Per-scene animation** — packet travel, ladder steps, diagram strokes.
6. **Controls** (if interactive) — play/pause, sliders, parameter inputs.
7. **Polish** — micro-spacing, color tuning, copy editing.

Don't animate first and lay out second. You'll repaint everything.

---

## Step 6 — Defensive checks (every build)

**Ownership:** this checklist is the **generator's** job — embed it in the delegation prompt and have the generator self-verify and report PASS/FAIL per item. The orchestrator does NOT re-run these by reading or rendering the file; it only does the cheap shell spot-check in *Validate frugally* above. Keep the list here so you can paste the relevant items into the delegation prompt.

Editorial checks first — these are the point of the skill (see Core principles):

- [ ] **Visual-first:** no scene is a wall of text — each makes its point with a diagram, animation, or visual contrast.
- [ ] **Before/after present:** the key change is shown side-by-side or as a toggle, not described in prose.
- [ ] **Motion shows the change:** transitions/flows/failures are animated, and still land with `prefers-reduced-motion` on.
- [ ] **Intuitive metaphor + consistent legend:** one color = one role, established in the hero and never broken.
- [ ] **Plain language:** jargon defined inline or removed; a non-expert could explain the one insight back.

Then the technical checks:

- [ ] **Self-contained:** `<style>` and `<script>` are inline; the file opens standalone.
- [ ] **Controls verified by simulated activation:** every button/toggle/slider was activated (dispatched click/input) and the expected DOM change asserted — a control that only *looks* wired is a shipped bug. Direct per-element listeners (no container delegation for primary controls); each init in its own try/catch; control revealed only after listeners attach; activation feedback is unmistakable (status text or mode shift, not just a few-percent width change).
- [ ] **No-JS renders full content (static-first):** with JavaScript disabled, every number, label, bar, and diagram is still visible — iOS Quick Look (Telegram/Mail/Files attachment viewer) and some in-app browsers strip JS, and a JS-rendered page shows as a blank background there. Content is baked into the markup; JS only adds animation/interactivity. Reveal elements are hidden only under a `.js` root class added by a first-line inline script — never `opacity:0` in plain CSS. Verify cheaply: `grep` that key content strings exist in the raw HTML outside any `<script>` tag.
- [ ] **No console errors** on load and during scroll, including missing favicon 404s.
- [ ] **Responsive:** test 320px (small phone), 768px (tablet), 1440px (desktop). Use `clamp()` for fluid type, `grid-template-columns: repeat(auto-fit, minmax(...))` for cards.
- [ ] **`prefers-reduced-motion`:** disable heavy animation (canvas off, transforms reduced) when set.
- [ ] **DPR-aware Canvas:** crisp on Retina (see §4.5).
- [ ] **Resize-safe:** `window.addEventListener('resize', ...)` re-runs layout calc, cancels old RAF.
- [ ] **Keyboard accessible:** every interactive control is a `<button>` or has `tabindex` + visible focus ring.
- [ ] **No null DOM lookups:** guard `document.getElementById(...)` against missing nodes.
- [ ] **Cancel RAF on pause/reset:** every animation loop has a corresponding `cancelAnimationFrame`.
- [ ] **CJK fallback:** if the page is in Chinese / Japanese / Korean, the font stack in §4.2 is present.
- [ ] **Annotated:** brief inline comments at each major section (`/* ── §3 ANTAGONIST ── */`) so the user can tweak.
- [ ] **File size budget:** target under ~80 KB for a single-page explainer. Strip unused CSS, minify-by-hand if it creeps over.

---

## Step 7 — Output format

When delivering, give the user three things, in this order:

1. **One paragraph** summarizing what the page shows, your design choices, and any assumptions you made.
2. **The path to the saved `.html` file.** Have `agy` write the file to a sensibly-named path (e.g., `~/Desktop/custom-dns-explainer-zh-2026-05-28.html`, or under `docs/` in the current project). Never dump the full HTML into chat — for a 60 KB file that wastes a 90 KB output budget. The file is the deliverable.
3. **A short "how to use"** — how to open it (`open <path>`), which parameters/CSS variables to tweak, and any controls/interactions.

Optionally use `SendUserFile` to surface the artifact to the user proactively.

---

## Step 8 — Hosting (optional)

If the user asks to host the page:

### Cloudflare Pages (Wrangler)

```bash
# 1. Verify wrangler is installed and authed
wrangler whoami

# 2. Set up a clean deploy directory (one file = one project)
mkdir -p /tmp/<project>-deploy && cp <file>.html /tmp/<project>-deploy/index.html

# 3. Deploy
cd /tmp/<project>-deploy && wrangler pages deploy . --project-name <project-slug>
# If the project doesn't exist yet, wrangler will prompt; alternatively:
#   wrangler pages project create <project-slug> --production-branch main
```

**Gotcha (from real incident):** if you ran an earlier `wrangler pages deploy` from the wrong directory, the shell's `cwd` may have persisted across commands. **Always `cd` explicitly** in the same chained command, and verify the live URL serves the expected file size before claiming success:

```bash
curl -s -o /tmp/served.html -w '%{http_code}\n' https://<project-slug>.pages.dev
# identity, not size: the served bytes must hash-match the file you deployed
shasum -a 256 /tmp/served.html <file>.html | awk '{print $1}' | uniq | wc -l   # must print 1
```

### GitHub Pages

```bash
# In a repo with Pages enabled:
git checkout -b gh-pages
cp <file>.html index.html
git add index.html && git commit -m "publish explainer"
git push -u origin gh-pages
```

### Hygiene before publishing public-facing content

- **Scrub real IPs, domains, tokens, customer names.** Replace with RFC-reserved equivalents:
  - IPs: `203.0.113.x` (TEST-NET-3 / RFC 5737)
  - Domains: `example.com`, `example.net`, `example.org` (RFC 2606)
  - Names: generic role (e.g., "Operator", "Customer") not real people
- **Search the file for staff names, internal hostnames, and DB IDs** before deploy. A simple `grep -E '<your-domain>|<your-staff-name>'` saves face.
- **Check the title and meta description** — they leak in browser tabs and link previews.

---

## Step 9 — When to escalate

If the requested page genuinely **cannot** be a single self-contained HTML file (it needs a backend, a large local dataset, proprietary auth, a server-side language), say so plainly and propose the closest self-contained approximation: mocked data, simplified scope, or a `fetch()` against a public read-only API with a graceful failure mode.

Never silently ship something broken.

---

## Quick reference — common request → recipe

| Request                                                      | Recipe                                                                            |
|--------------------------------------------------------------|-----------------------------------------------------------------------------------|
| "Make a scrollytelling page explaining X to a non-tech exec" | Full §2 scene outline, §4.1 dark palette, §4.4 reveals, §4.5 hero, §4.6 SVG diag  |
| "Animate the TCP three-way handshake"                        | SVG client/server boxes, CSS `animation` on arrow stroke-dashoffset, step buttons |
| "Visualize quicksort partitioning an array"                  | Canvas array of bars, RAF stepper, Play/Pause/Speed slider, color-code pivot      |
| "Build a dashboard for these monthly revenue numbers"        | Inline data array → SVG bar/line chart with hand-rolled axes, hover tooltips      |
| "Show how our system architecture flows from A to B"         | One scene, big inline SVG with `<defs><marker>` arrowheads, layered reveals       |
| "Make a one-pager that pitches the product"                  | Hero + 3 feature cards + comparison table + CTA, all under 50 KB                  |

---

## See also

- Memory: `feedback_tech_doc_visualizer.md` — sticky TOC scroll-spy, code cards with clipboard fallback, theme toggle via `localStorage`.
- Memory: `feedback_security_dashboard_style.md` — security review dashboard variant.
