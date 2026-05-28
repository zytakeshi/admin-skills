---
name: html-specialist
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

## Step 1 — Clarify intent (one tight round, then go)

Before writing a line of code, lock down:

1. **What** concept / data / process is being explained?
2. **Who** is the audience? What do they already know? Are they technical?
3. **What language?** Default to the user's language. For Chinese / Japanese / Korean, use the CJK font stack (§Tech Stack below).
4. **One insight rule:** what is the single sentence the viewer should remember? Everything in the file serves that sentence.
5. **Hosting?** Local file (`file://` double-click), Cloudflare Pages (wrangler), GitHub Pages, or unspecified?

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

Always in this order:

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

- [ ] **Self-contained:** `<style>` and `<script>` are inline; the file opens standalone.
- [ ] **No console errors** on load and during scroll.
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
2. **The path to the saved `.html` file.** Write the file with the `Write` tool to a sensibly-named path (e.g., `~/Desktop/custom-dns-explainer-zh-2026-05-28.html`, or under `docs/` in the current project). Never dump the full HTML into chat — for a 60 KB file that wastes a 90 KB output budget. The file is the deliverable.
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
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' https://<project-slug>.pages.dev
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
