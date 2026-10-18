// Meety · site: idioma (PT | EN) e as animações com Motion.
import { animate, inView, scroll } from "https://cdn.jsdelivr.net/npm/motion@14.3.0/+esm";
import { strings } from "./i18n.js";

const html = document.documentElement;
html.classList.add("js");
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
if (reduced) html.classList.add("reduced");
const EASE = [0.22, 1, 0.36, 1];
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));

/* ---------- Idioma ---------- */
let lang = "pt-BR";
const t = (key) => strings[lang][key] ?? key;
function pickLang() {
  try { const saved = localStorage.getItem("meety.lang"); if (saved && strings[saved]) return saved; } catch {}
  return (navigator.language || "").toLowerCase().startsWith("pt") ? "pt-BR" : "en";
}
function setMeta(selector, value) { const el = $(selector); if (el) el.setAttribute("content", value); }
function applyLang(next) {
  lang = next;
  const d = strings[lang];
  html.lang = lang;
  document.title = d["meta.title"];
  setMeta('meta[name="description"]', d["meta.desc"]);
  setMeta('meta[property="og:title"]', d["meta.title"]);
  setMeta('meta[property="og:description"]', d["meta.desc"]);
  setMeta('meta[property="og:locale"]', lang === "pt-BR" ? "pt_BR" : "en_US");
  $$("[data-i18n]").forEach((el) => { const v = d[el.dataset.i18n]; if (v != null) el.textContent = v; });
  $$("[data-i18n-attr]").forEach((el) => {
    el.dataset.i18nAttr.split(";").forEach((pair) => {
      const [attr, key] = pair.split(":").map((s) => s.trim());
      if (attr && d[key] != null) el.setAttribute(attr, d[key]);
    });
  });
  $$("[data-lang]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
  try { localStorage.setItem("meety.lang", lang); } catch {}
}
applyLang(pickLang());
$$("[data-lang]").forEach((b) => b.addEventListener("click", () => applyLang(b.dataset.lang)));

/* ---------- Utilidades ---------- */
// Revela os filhos [data-reveal] de um bloco, em cascata.
function reveal(root, { delay = 0, step = 0.09, y = 24, duration = 0.9 } = {}) {
  $$("[data-reveal]", root).forEach((el, i) => {
    animate(el, { opacity: [0, 1], y: [y, 0] }, { duration, delay: delay + i * step, ease: EASE });
  });
}
// Laços infinitos usam a Web Animations API nativa: no Motion 14.3, `repeat: Infinity` em transforms
// gera um easing linear() com valores inválidos e o elemento some. O Motion fica com as revelações,
// as transições de cena e tudo que é ligado ao scroll.
function loop(target, keyframes, { duration = 1, delay = 0, mirror = false, ease = "ease-in-out", repeatDelay = 0 } = {}) {
  const els = typeof target === "string" ? $$(target) : [target];
  return els.map((el) => el.animate(keyframes, {
    duration: duration * 1000, delay: delay * 1000, endDelay: repeatDelay * 1000, iterations: Infinity,
    direction: mirror ? "alternate" : "normal", easing: ease, fill: "both",
  }));
}
// Um "jogador" de cena: timers e animações que podem ser parados de uma vez.
function player() {
  const timers = [], controls = [];
  return {
    after: (s, fn) => timers.push(setTimeout(fn, s * 1000)),
    every: (s, fn) => timers.push(setInterval(fn, s * 1000)),
    add: (c) => { (Array.isArray(c) ? c : [c]).forEach((x) => controls.push(x)); return c; },
    stop: () => { timers.splice(0).forEach((id) => { clearTimeout(id); clearInterval(id); }); controls.splice(0).forEach((c) => (c.cancel ? c.cancel() : c.stop?.())); },
  };
}
const clock = (s) => `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
const SPEAKER_COLOR = { you: "#0d7a68", ana: "#4a42d6", bruno: "#0b6f8c", carla: "#b0246a", p1: "#4a42d6", p2: "#0b6f8c" };
const GRAY = "#8a97a6";

// Monta as barras de uma trilha a partir de quem fala em cada coluna.
function buildLane(lane, who, kind) {
  lane.replaceChildren();
  who.forEach((sp, i) => {
    const bar = document.createElement("i");
    const speaks = kind === "meeting" ? sp !== "you" : sp === kind;
    bar.style.setProperty("--h", (0.35 + Math.random() * 0.6).toFixed(2));
    if (!speaks) bar.classList.add("is-silent");
    bar.dataset.sp = sp;
    lane.appendChild(bar);
  });
}
const expand = (scene) => scene.flatMap(([sp, n]) => Array(n).fill(sp));

const nav = $("#nav");

/* =====================================================================
   Hero: o palco. Dock → janela → gravação → processamento → ata, com a
   transição "buraco negro" entre as cenas.
   ===================================================================== */
function stageController(stage) {
  const sc = Object.fromEntries($$(".scene", stage).map((s) => [s.dataset.scene, s]));
  const hole = $("#hole"), ring = $("i", hole), cursor = $("#cursor"), ripple = $("#ripple");
  const recbtn = $("#mw-recbtn"), rec = $("#mw-rec"), live = $("#mw-live"), empty = $("#mw-empty");
  const time1 = $("#mw-time"), time2 = $("#mw-time2"), wave = $("#mw-wave");
  const pcFill = $("#pc-fill"), pcPct = $("#pc-pct"), pcSteps = $$("#pc-steps li");
  const ataLines = $$("[data-ln]", sc.ata);
  for (let i = 0; i < 18; i++) wave.appendChild(document.createElement("i"));
  let token = 0;
  let p = player();

  function reset() {
    // o Motion escreve em `transform`, então o estado inicial também vai em `transform`
    Object.values(sc).forEach((s) => { s.style.opacity = "0"; s.style.transform = "scale(0.02)"; s.style.filter = "none"; });
    sc.dock.style.opacity = "1"; sc.dock.style.transform = "none";
    cursor.style.opacity = "0";
    $("em", $("#dock-meety")).style.opacity = "0";
    recbtn.classList.remove("is-on"); rec.classList.remove("is-on"); live.classList.remove("is-on"); empty.style.display = "";
    time1.textContent = "00:00"; time2.textContent = "00:00";
    pcFill.style.transform = "scaleX(0)"; pcPct.textContent = "0%";
    pcSteps.forEach((li) => li.classList.remove("is-now", "is-done"));
    ataLines.forEach((l) => { l.style.opacity = "0"; if (l.classList.contains("ln")) l.style.transform = "scaleX(0)"; });
  }
  function center(el) {
    const r = el.getBoundingClientRect(), s = stage.getBoundingClientRect();
    return { x: r.left - s.left + r.width / 2, y: r.top - s.top + r.height / 2 };
  }
  async function moveTo(el, duration = 0.8) {
    const c = center(el);
    await animate(cursor, { x: c.x - 5, y: c.y - 3, opacity: 1 }, { duration, ease: [0.3, 0.6, 0.2, 1] });
  }
  async function click() {
    animate(ripple, { scale: [0.3, 1.8], opacity: [0.7, 0] }, { duration: 0.5, ease: "easeOut" });
    await animate(cursor, { scale: [1, 0.85, 1] }, { duration: 0.28 });
  }
  async function swallow(from, to, tk) {
    animate(cursor, { opacity: 0 }, { duration: 0.2 });
    animate(hole, { scale: [0, 1] }, { duration: 0.35, ease: "easeOut" });
    await animate(from, { scale: [1, 0.02], rotate: ["0deg", "55deg"], opacity: [1, 0], filter: ["blur(0px)", "blur(5px)"] }, { duration: 0.8, ease: [0.7, 0, 0.95, 0.35] });
    if (tk !== token) return;
    animate(hole, { scale: [1, 1.6, 1] }, { duration: 0.4 });
    await animate(ring, { scale: [0.6, 2.4], opacity: [0.8, 0] }, { duration: 0.55 });
    if (tk !== token) return;
    animate(hole, { scale: [1, 0] }, { duration: 0.4, delay: 0.1 });
    await animate(to, { scale: [0.02, 1], rotate: ["-40deg", "0deg"], opacity: [0, 1], filter: ["blur(6px)", "blur(0px)"] }, { duration: 0.95, ease: [0.16, 1, 0.3, 1] });
  }

  async function run(tk) {
    const ok = () => tk === token;
    reset();
    // cursor entra pelo canto
    cursor.style.translate = ""; await animate(cursor, { x: stage.clientWidth * 0.72, y: stage.clientHeight * 0.3 }, { duration: 0 });
    await sleep(0.5); if (!ok()) return;

    // 1. Dock: clicar no ícone do Meety
    const icon = $("#dock-meety");
    await moveTo(icon, 0.9); if (!ok()) return;
    await click();
    animate(icon, { y: [0, -14, 0] }, { duration: 0.55, ease: "easeOut" });
    animate($("em", icon), { opacity: [0, 1] }, { duration: 0.3, delay: 0.3 });
    await sleep(0.7); if (!ok()) return;
    await swallow(sc.dock, sc.app, tk); if (!ok()) return;

    // 2. Janela: gravar
    await sleep(0.4); if (!ok()) return;
    await moveTo(recbtn, 0.9); if (!ok()) return;
    await click(); if (!ok()) return;
    recbtn.classList.add("is-on"); rec.classList.add("is-on"); live.classList.add("is-on"); empty.style.display = "none";
    p.add(loop("#mw-m1", { transform: ["scaleX(0.15)", "scaleX(0.95)"] }, { duration: 0.5, mirror: true }));
    p.add(loop("#mw-m2", { transform: ["scaleX(0.9)", "scaleX(0.25)"] }, { duration: 0.7, mirror: true }));
    $$("i", wave).forEach((b) => p.add(loop(b, { transform: ["scaleY(0.15)", `scaleY(${(0.4 + Math.random() * 0.6).toFixed(2)})`] }, { duration: 0.35 + Math.random() * 0.5, mirror: true })));
    let secs = 0;
    p.every(0.12, () => { secs += 37; time1.textContent = time2.textContent = clock(secs); });
    // o cursor sai de cima do botão enquanto grava
    animate(cursor, { x: stage.clientWidth * 0.7, y: stage.clientHeight * 0.75 }, { duration: 1, ease: EASE });
    await sleep(3.4); if (!ok()) return;
    await moveTo(recbtn, 0.8); if (!ok()) return;
    await click(); if (!ok()) return;
    p.stop(); p = player();
    recbtn.classList.remove("is-on"); rec.classList.remove("is-on");
    await sleep(0.45); if (!ok()) return;
    await swallow(sc.app, sc.proc, tk); if (!ok()) return;

    // 3. Processando
    const total = 3;
    pcSteps.forEach((li, i) => { p.after((i / pcSteps.length) * total, () => { pcSteps.forEach((x) => x.classList.remove("is-now")); li.classList.add("is-now"); if (i > 0) pcSteps[i - 1].classList.replace("is-now", "is-done"), pcSteps[i - 1].classList.add("is-done"); }); });
    p.after(total, () => pcSteps.forEach((x) => { x.classList.remove("is-now"); x.classList.add("is-done"); }));
    p.add(animate(pcFill, { scaleX: [0, 1] }, { duration: total, ease: "linear" }));
    p.add(animate(0, 100, { duration: total, ease: "linear", onUpdate: (v) => (pcPct.textContent = `${Math.round(v)}%`) }));
    await sleep(total + 0.6); if (!ok()) return;
    p.stop(); p = player();
    await swallow(sc.proc, sc.ata, tk); if (!ok()) return;

    // 4. A ata, linha por linha
    let at = 0.2;
    ataLines.forEach((l) => {
      if (l.classList.contains("ln")) p.add(animate(l, { opacity: [0, 1], scaleX: [0, 1] }, { duration: 0.45, delay: at, ease: EASE }));
      else p.add(animate(l, { opacity: [0, 1], y: [6, 0] }, { duration: 0.4, delay: at, ease: EASE }));
      at += l.classList.contains("ln") ? 0.3 : 0.36;
    });
    await sleep(at + 2.4); if (!ok()) return;
    p.stop(); p = player();
    await swallow(sc.ata, sc.dock, tk); if (!ok()) return;
    run(tk);
  }

  function staticEnd() {
    reset();
    sc.dock.style.opacity = "0";
    sc.ata.style.opacity = "1"; sc.ata.style.transform = "none";
    ataLines.forEach((l) => { l.style.opacity = "1"; l.style.transform = "none"; });
  }
  return {
    start: () => { token += 1; run(token); },
    stop: () => { token += 1; p.stop(); p = player(); },
    staticEnd,
  };
}

/* =====================================================================
   Demonstrações dos três passos (reaproveitadas no deck)
   ===================================================================== */
const SCENE1 = expand([["you", 7], ["ana", 11], ["you", 4], ["bruno", 10], ["carla", 9], ["ana", 6], ["you", 5], ["carla", 4]]);
function playRecord(demo) {
  const p = player();
  const STEP = 0.07;
  const time = $("#rec-time", demo);
  const tiles = $$(".tile", demo);
  $$(".lane", demo).forEach((lane) => buildLane(lane, SCENE1, lane.dataset.lane));
  const bars = (lane) => $$(`[data-lane="${lane}"] i:not(.is-silent)`, demo);
  function run() {
    demo.classList.remove("is-split");
    $$(".lane i:not(.is-silent)", demo).forEach((b) => { b.style.opacity = 0; b.style.background = GRAY; });
    tiles.forEach((x) => x.classList.remove("is-speaking"));
    time.textContent = "00:00";
    SCENE1.forEach((sp, i) => p.after(0.2 + i * STEP, () => {
      tiles.forEach((x) => x.classList.toggle("is-speaking", x.dataset.sp === sp));
      time.textContent = clock((i + 1) * 45);
    }));
    ["you", "meeting"].forEach((lane) => $$(`[data-lane="${lane}"] i`, demo).forEach((b, i) => {
      if (!b.classList.contains("is-silent")) p.add(animate(b, { opacity: [0, 1] }, { duration: 0.25, delay: 0.2 + i * STEP }));
    }));
    const t1 = 0.2 + SCENE1.length * STEP + 0.6;
    p.after(t1 - 0.2, () => tiles.forEach((x) => x.classList.remove("is-speaking")));
    p.after(t1, () => demo.classList.add("is-split"));
    $$(`[data-lane="meeting"] i`, demo).forEach((b, i) => {
      if (!b.classList.contains("is-silent")) p.add(animate(b, { backgroundColor: [GRAY, SPEAKER_COLOR[b.dataset.sp]] }, { duration: 0.3, delay: t1 + 0.2 + i * STEP * 0.6 }));
    });
    ["ana", "bruno", "carla"].forEach((lane) => $$(`[data-lane="${lane}"] i`, demo).forEach((b, i) => {
      if (b.classList.contains("is-silent")) return;
      b.style.background = SPEAKER_COLOR[lane];
      p.add(animate(b, { opacity: [0, 1], y: [-6, 0] }, { duration: 0.3, delay: t1 + 0.5 + i * STEP * 0.6 }));
    }));
    p.after(t1 + 0.5 + SCENE1.length * STEP * 0.6 + 2.6, run);
  }
  run();
  return () => p.stop();
}
function playTranscript(el) {
  const p = player();
  const lines = $$("[data-line]", el);
  lines.forEach((l, i) => { l.style.opacity = 0; p.add(animate(l, { opacity: [0, 1], y: [10, 0] }, { duration: 0.6, delay: 0.3 + i * 0.45, ease: EASE })); });
  let cur = -1;
  p.every(1.5, () => { lines.forEach((l) => l.classList.remove("is-current")); cur = (cur + 1) % lines.length; lines[cur].classList.add("is-current"); });
  return () => { p.stop(); lines.forEach((l) => l.classList.remove("is-current")); };
}
function playSummary(el) {
  const p = player();
  $$("[data-line]", el).forEach((l, i) => { l.style.opacity = 0; p.add(animate(l, { opacity: [0, 1], x: [-8, 0] }, { duration: 0.5, delay: 0.4 + i * 0.38, ease: EASE })); });
  return () => p.stop();
}

/* =====================================================================
   Deck "Como funciona": um relógio só, páginas com progresso, setas.
   ===================================================================== */
function deckController(deck) {
  const pages = $$(".page", deck), segs = $$("#deck-progress button", deck);
  const demos = [() => playRecord($("#ui-record")), () => playTranscript($("#ui-transcript")), () => playSummary($("#ui-summary"))];
  const DUR = [12, 9, 8];
  let idx = 0, elapsed = 0, last = null, raf = null, running = false, paused = false, stopDemo = null, switching = false;
  const seg = (i) => $("i", segs[i]);
  function paint() { segs.forEach((_, j) => seg(j).style.setProperty("--p", j < idx ? 1 : j > idx ? 0 : elapsed / DUR[idx])); }
  async function show(i, dir = 1) {
    if (switching || i === idx) return;
    switching = true;
    const from = pages[idx], to = pages[i];
    stopDemo?.(); stopDemo = null;
    idx = i; elapsed = 0; paint();
    from.classList.add("is-leaving"); from.classList.remove("is-active");
    to.classList.add("is-active");
    animate(from, { opacity: [1, 0], x: [0, -28 * dir] }, { duration: 0.35, ease: "easeIn" }).then(() => { from.classList.remove("is-leaving"); from.style.opacity = ""; from.style.translate = ""; });
    await animate(to, { opacity: [0, 1], x: [28 * dir, 0] }, { duration: 0.55, delay: 0.15, ease: EASE });
    to.style.translate = "";
    if (running) stopDemo = demos[idx]();
    switching = false;
  }
  function tick(now) {
    if (!running) return;
    if (last != null && !paused && !document.hidden && !switching) {
      elapsed += (now - last) / 1000;
      if (elapsed >= DUR[idx]) show((idx + 1) % pages.length, 1); else paint();
    }
    last = now; raf = requestAnimationFrame(tick);
  }
  $("#deck-prev", deck).addEventListener("click", () => show((idx + pages.length - 1) % pages.length, -1));
  $("#deck-next", deck).addEventListener("click", () => show((idx + 1) % pages.length, 1));
  segs.forEach((b, j) => b.addEventListener("click", () => show(j, j > idx ? 1 : -1)));
  deck.addEventListener("pointerenter", () => (paused = true));
  deck.addEventListener("pointerleave", () => (paused = false));
  deck.addEventListener("focusin", () => (paused = true));
  deck.addEventListener("focusout", () => (paused = false));
  return {
    start: () => { running = true; last = null; stopDemo?.(); stopDemo = demos[idx](); raf = requestAnimationFrame(tick); },
    stop: () => { running = false; cancelAnimationFrame(raf); stopDemo?.(); stopDemo = null; },
  };
}

/* =====================================================================
   Recursos: seis pontos, um palco. Cada ponto tem a sua cena.
   ===================================================================== */
const SCENE2 = expand([["you", 8], ["p1", 10], ["you", 4], ["p2", 9], ["p1", 6], ["you", 3]]);
const panelPlayers = {
  0(panel) { // quem falou: duas trilhas, depois as frases com dono
    const p = player();
    $$(".lane", panel).forEach((lane) => buildLane(lane, SCENE2, lane.dataset.lane === "f-you" ? "you" : "meeting"));
    $$(".lane i:not(.is-silent)", panel).forEach((b) => { b.style.background = b.dataset.sp === "you" ? SPEAKER_COLOR.you : GRAY; });
    $$(".lane i", panel).forEach((b, i) => { if (!b.classList.contains("is-silent")) p.add(animate(b, { opacity: [0, 1] }, { duration: 0.2, delay: 0.2 + (i % SCENE2.length) * 0.035 })); });
    $$(`[data-lane="f-meeting"] i:not(.is-silent)`, panel).forEach((b, i) => p.add(animate(b, { backgroundColor: [GRAY, SPEAKER_COLOR[b.dataset.sp]] }, { duration: 0.3, delay: 1.9 + i * 0.03 })));
    $$("[data-fx]", panel).forEach((l, i) => { l.style.opacity = 0; p.add(animate(l, { opacity: [0, 1], y: [8, 0] }, { duration: 0.45, delay: 2.4 + i * 0.3, ease: EASE })); });
    return () => p.stop();
  },
  1(panel) { // juntar falantes
    const p = player();
    const chip2 = $("#chip-2", panel), chip3 = $("#chip-3", panel), note = $("#chip-note", panel), line2 = $("#line-2", panel), line3 = $("#line-3", panel);
    const label2 = $("span", chip2);
    // depois de juntar, as duas pessoas viram uma só, em todas as falas
    const restore = () => { label2.textContent = t("fp.sp2"); line2.textContent = t("fp.sp2"); line3.textContent = t("fp.sp3"); line3.className = "s4"; chip3.style.opacity = "1"; chip3.style.translate = ""; chip3.style.scale = ""; chip2.style.scale = ""; note.style.opacity = "0"; };
    restore();
    p.after(1.1, async () => {
      const dx = chip2.getBoundingClientRect().left - chip3.getBoundingClientRect().left + chip2.offsetWidth * 0.35;
      p.add(animate(chip3, { x: [0, dx], scale: [1, 0.6], opacity: [1, 0] }, { duration: 0.8, ease: [0.5, 0, 0.2, 1] }));
      p.after(0.7, () => {
        label2.textContent = t("fp.merged"); line2.textContent = t("fp.merged"); line3.textContent = t("fp.merged"); line3.className = "s3";
        p.add(animate(chip2, { scale: [1, 1.12, 1] }, { duration: 0.5 }));
        p.add(animate(note, { opacity: [0, 1], x: [-6, 0] }, { duration: 0.4, delay: 0.2 }));
      });
    });
    return () => { p.stop(); restore(); };
  },
  2(panel) { // projetos: arrastar a gravação para o projeto
    const p = player();
    const card = $("#rec-card", panel), row = $("#proj-1", panel), tag = $("#rec-tag", panel);
    const reset = () => { card.style.translate = ""; card.style.rotate = ""; row.classList.remove("is-over"); tag.style.opacity = "0"; tag.style.scale = ""; };
    reset();
    p.after(0.8, () => {
      const c = card.getBoundingClientRect(), r = row.getBoundingClientRect();
      const dx = r.left - c.left + 24, dy = r.top - c.top + (r.height - c.height) / 2;
      p.add(animate(card, { x: [0, dx], y: [0, dy], rotate: ["0deg", "-2deg"] }, { duration: 1, ease: [0.4, 0, 0.2, 1] }));
      p.after(0.75, () => row.classList.add("is-over"));
      p.after(1.5, () => {
        row.classList.remove("is-over");
        p.add(animate(card, { x: [dx, 0], y: [dy, 0], rotate: ["-2deg", "0deg"] }, { duration: 0.7, ease: EASE }));
        p.after(0.75, () => p.add(animate(tag, { opacity: [0, 1], scale: [0.7, 1] }, { duration: 0.4, ease: EASE })));
      });
    });
    return () => { p.stop(); reset(); };
  },
  3(panel) { // busca: digitar e ver os resultados
    const p = player();
    const q = $("#q", panel), count = $("#res-count", panel), res = $$("[data-fx]", panel);
    const word = t("fp.query");
    q.textContent = ""; count.style.opacity = "0"; res.forEach((r) => (r.style.opacity = "0"));
    for (let i = 1; i <= word.length; i++) p.after(0.5 + i * 0.09, () => (q.textContent = word.slice(0, i)));
    const done = 0.5 + word.length * 0.09 + 0.3;
    p.after(done, () => p.add(animate(count, { opacity: [0, 1] }, { duration: 0.3 })));
    res.forEach((r, i) => p.after(done + 0.1 + i * 0.25, () => p.add(animate(r, { opacity: [0, 1], y: [8, 0] }, { duration: 0.45, ease: EASE }))));
    return () => p.stop();
  },
  4(panel) { // arquivo solto na janela
    const p = player();
    const drop = $("#drop", panel), file = $("#file", panel), row = $("#file-row", panel), fill = $("#file-fill", panel), pct = $("#file-pct", panel);
    const reset = () => { drop.classList.remove("is-over"); drop.style.opacity = "1"; file.style.opacity = "0"; file.style.translate = ""; row.style.opacity = "0"; fill.style.transform = "scaleX(0)"; pct.textContent = "0%"; };
    reset();
    p.add(animate(file, { opacity: [0, 1], y: [-70, 0] }, { duration: 0.9, delay: 0.5, ease: [0.3, 0, 0.3, 1] }));
    p.after(0.9, () => drop.classList.add("is-over"));
    p.after(1.8, () => {
      p.add(animate(file, { opacity: [1, 0], scale: [1, 0.8] }, { duration: 0.3 }));
      p.add(animate(drop, { opacity: [1, 0] }, { duration: 0.3 }));
      p.add(animate(row, { opacity: [0, 1], y: [8, 0] }, { duration: 0.45, delay: 0.25, ease: EASE }));
      p.add(animate(fill, { scaleX: [0, 0.42] }, { duration: 2.2, delay: 0.5, ease: "linear" }));
      p.add(animate(0, 42, { duration: 2.2, delay: 0.5, ease: "linear", onUpdate: (v) => (pct.textContent = `${Math.round(v)}%`) }));
    });
    return () => { p.stop(); reset(); };
  },
  5(panel) { // exportar: a escolha do formato muda a prévia
    const p = player();
    const items = $$("#exp-list li", panel), lines = $$("#exp-preview .sk", panel);
    let on = 0;
    const paint = () => { items.forEach((li, i) => li.classList.toggle("is-on", i === on)); lines.forEach((l) => (l.style.width = `${45 + Math.random() * 50}%`)); };
    items.forEach((li) => li.classList.remove("is-on")); on = 0; paint();
    p.every(0.95, () => { on = (on + 1) % items.length; paint(); });
    return () => { p.stop(); on = 0; paint(); };
  },
};
function featuresController(root) {
  const items = $$("#feat-list li", root), panels = $$(".fp", root);
  const DUR = 7;
  let idx = 0, elapsed = 0, last = null, raf = null, running = false, paused = false, stopPanel = null, switching = false;
  const prog = (i) => $(".feat-prog", items[i]);
  function paint() { prog(idx).style.setProperty("--p", elapsed / DUR); }
  async function show(i) {
    if (switching || i === idx) return;
    switching = true;
    stopPanel?.(); stopPanel = null;
    const from = panels[idx], to = panels[i];
    prog(idx).style.setProperty("--p", 0);
    items[idx].classList.remove("is-active"); items[i].classList.add("is-active");
    idx = i; elapsed = 0;
    await animate(from, { opacity: [1, 0], y: [0, -8] }, { duration: 0.28, ease: "easeIn" });
    from.classList.remove("is-active"); from.style.opacity = ""; from.style.translate = "";
    to.classList.add("is-active");
    if (running) stopPanel = panelPlayers[idx](to);
    await animate(to, { opacity: [0, 1], y: [10, 0] }, { duration: 0.45, ease: EASE });
    to.style.translate = "";
    switching = false;
  }
  function tick(now) {
    if (!running) return;
    if (last != null && !paused && !document.hidden && !switching) {
      elapsed += (now - last) / 1000;
      if (elapsed >= DUR) show((idx + 1) % panels.length); else paint();
    }
    last = now; raf = requestAnimationFrame(tick);
  }
  items.forEach((li, i) => $("button", li).addEventListener("click", () => show(i)));
  root.addEventListener("pointerenter", () => (paused = true));
  root.addEventListener("pointerleave", () => (paused = false));
  return {
    start: () => { running = true; last = null; panels[idx].classList.add("is-active"); stopPanel?.(); stopPanel = panelPlayers[idx](panels[idx]); raf = requestAnimationFrame(tick); },
    stop: () => { running = false; cancelAnimationFrame(raf); stopPanel?.(); stopPanel = null; },
  };
}

/* =====================================================================
   Liga tudo
   ===================================================================== */
const stage = stageController($("#stage"));
const deck = deckController($("#deck"));
const feats = featuresController($(".feat"));

if (reduced) {
  scroll((p) => { $("#progress").style.transform = `scaleX(${p})`; nav.classList.toggle("is-solid", p > 0.01); });
  stage.staticEnd();
  $$("#ui-record .lane").forEach((lane) => buildLane(lane, SCENE1, lane.dataset.lane));
  $$("#ui-record .lane i").forEach((b) => { b.style.opacity = 1; if (b.closest(".lane").dataset.lane !== "you") b.style.background = SPEAKER_COLOR[b.dataset.sp]; });
  $("#ui-record").classList.add("is-split");
  const fp0 = $$(".fp", $(".feat"))[0];
  $$(".lane", fp0).forEach((lane) => buildLane(lane, SCENE2, lane.dataset.lane === "f-you" ? "you" : "meeting"));
  $$(".lane i", fp0).forEach((b) => { b.style.opacity = 1; b.style.background = SPEAKER_COLOR[b.dataset.sp]; });
  fp0.classList.add("is-active");
} else {
  reveal($("#hero"), { delay: 0.1, step: 0.11, y: 28, duration: 1.1 });
  scroll(animate("#progress", { scaleX: [0, 1] }, { ease: "linear" }));
  scroll((p, info) => nav.classList.toggle("is-solid", info.y.current > 24));

  // o hero sai de cena quando a primeira seção desliza por cima
  const first = $(".section");
  scroll(animate(".hero-inner", { opacity: [1, 0], scale: [1, 0.95], y: [0, -60] }, { ease: "linear" }), { target: first, offset: ["start end", "start 15%"] });

  const sections = $$(".section");
  sections.forEach((sec, idx) => {
    sec.style.opacity = "0";
    inView(sec, () => {
      animate(sec, { opacity: [0, 1], y: [48, 0] }, { duration: 0.9, ease: EASE });
      reveal(sec, { delay: 0.15, step: 0.08 });
    }, { amount: 0.12 });
    if (idx < sections.length - 1) {
      scroll(animate($(".inner", sec), { opacity: [1, 0.3], y: [0, -32] }, { ease: "linear" }), { target: sec, offset: ["end 55%", "end start"] });
    }
  });

  inView("#stage", () => { stage.start(); return () => stage.stop(); }, { amount: 0.3 });
  inView("#deck", () => { deck.start(); return () => deck.stop(); }, { amount: 0.3 });
  inView(".feat", () => { feats.start(); return () => feats.stop(); }, { amount: 0.3 });
}
