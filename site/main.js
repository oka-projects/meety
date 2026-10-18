// Meety · site: idioma (PT | EN) e animações com Motion.
import { animate, inView, scroll } from "https://cdn.jsdelivr.net/npm/motion@14.3.0/+esm";
import { strings } from "./i18n.js";

const html = document.documentElement;
html.classList.add("js");
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
if (reduced) html.classList.add("reduced");
const EASE = [0.22, 1, 0.36, 1];
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

/* ---------- Idioma ---------- */
function pickLang() {
  try { const saved = localStorage.getItem("meety.lang"); if (saved && strings[saved]) return saved; } catch {}
  return (navigator.language || "").toLowerCase().startsWith("pt") ? "pt-BR" : "en";
}
function setMeta(selector, value) { const el = $(selector); if (el) el.setAttribute("content", value); }
function applyLang(lang) {
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

/* ---------- Utilidades de animação ---------- */
// Revela os filhos [data-reveal] de um bloco, em cascata.
function reveal(root, { delay = 0, step = 0.09, y = 24, duration = 0.9 } = {}) {
  $$("[data-reveal]", root).forEach((el, i) => {
    animate(el, { opacity: [0, 1], y: [y, 0] }, { duration, delay: delay + i * step, ease: EASE });
  });
}
// Laços infinitos usam a Web Animations API nativa: no Motion 14.3, `repeat: Infinity` em transforms
// gera um easing linear() com valores inválidos e o elemento some. O Motion fica com as revelações,
// as transições entre seções e tudo que é ligado ao scroll.
function loop(target, keyframes, { duration = 1, delay = 0, mirror = false, ease = "ease-in-out", repeatDelay = 0 } = {}) {
  const els = typeof target === "string" ? $$(target) : [target];
  return els.map((el) => el.animate(keyframes, {
    duration: duration * 1000, delay: delay * 1000, endDelay: repeatDelay * 1000, iterations: Infinity,
    direction: mirror ? "alternate" : "normal", easing: ease, fill: "both",
  }));
}
const nav = $("#nav");

/* ---------- Passo 1: a reunião e as trilhas (dados da cena) ---------- */
const COLS = 56;
// Quem fala em cada coluna da linha do tempo.
const SCENE = [["you", 7], ["ana", 11], ["you", 4], ["bruno", 10], ["carla", 9], ["ana", 6], ["you", 5], ["carla", 4]];
const who = []; SCENE.forEach(([sp, n]) => { for (let i = 0; i < n; i++) who.push(sp); });
const SPEAKER_COLOR = { you: "#146C66", ana: "#4453C8", bruno: "#8F5A00", carla: "#8A3C9E" };
const GRAY = "#7B8787";
function buildLanes() {
  const heights = Array.from({ length: COLS }, () => 0.35 + Math.random() * 0.6);
  $$("#ui-record .lane").forEach((lane) => {
    const kind = lane.dataset.lane;
    lane.replaceChildren();
    for (let i = 0; i < COLS; i++) {
      const bar = document.createElement("i");
      const speaks = kind === "meeting" ? who[i] !== "you" : who[i] === kind;
      bar.style.setProperty("--h", heights[i].toFixed(2));
      if (!speaks) bar.classList.add("is-silent");
      bar.dataset.sp = who[i];
      lane.appendChild(bar);
    }
  });
}
buildLanes();

if (reduced) {
  scroll((p) => { $("#progress").style.transform = `scaleX(${p})`; nav.classList.toggle("is-solid", p > 0.01); });
  $$("#ui-record .lane i").forEach((b) => { b.style.opacity = 1; if (b.closest("[data-lane]").dataset.lane !== "you") b.style.background = SPEAKER_COLOR[b.dataset.sp]; });
  $("#ui-record").classList.add("is-split");
} else {
  /* ---------- Carga: hero em cascata ---------- */
  reveal($("#hero"), { delay: 0.1, step: 0.11, y: 28, duration: 1.1 });

  /* ---------- Scroll: progresso e navegação ---------- */
  scroll(animate("#progress", { scaleX: [0, 1] }, { ease: "linear" }));
  scroll((p, info) => nav.classList.toggle("is-solid", info.y.current > 24));

  /* ---------- Hero sai de cena quando a seção seguinte desliza por cima ---------- */
  const local = $("#local");
  scroll(animate(".hero-inner", { opacity: [1, 0], scale: [1, 0.95], y: [0, -60] }, { ease: "linear" }), {
    target: local, offset: ["start end", "start 15%"],
  });
  scroll(animate(".window-hero", { y: [0, 70] }, { ease: "linear" }), { target: local, offset: ["start end", "start start"] });

  /* ---------- Seções: entram subindo, filhos em cascata, saem esmaecendo ---------- */
  const sections = $$(".section");
  sections.forEach((sec, idx) => {
    sec.style.opacity = "0";
    inView(sec, () => {
      animate(sec, { opacity: [0, 1], y: [48, 0] }, { duration: 0.9, ease: EASE });
      reveal(sec, { delay: 0.15, step: 0.08 });
    }, { amount: 0.12 });
    if (idx < sections.length - 1) {
      scroll(animate($(".inner", sec), { opacity: [1, 0.3], y: [0, -32] }, { ease: "linear" }), {
        target: sec, offset: ["end 55%", "end start"],
      });
    }
  });

  /* ---------- Hero: espectro de áudio ---------- */
  const wave = $("#wave");
  for (let i = 0; i < 44; i++) {
    const bar = document.createElement("i");
    wave.appendChild(bar);
    const a = 0.3 + Math.random() * 0.7;
    loop(bar, { transform: ["scaleY(0.08)", `scaleY(${a.toFixed(2)})`] }, { duration: 0.7 + Math.random() * 0.9, delay: Math.random() * 0.6, mirror: true });
  }

  /* ---------- Fluxo "nada sai do Mac": pacotes viajando ---------- */
  const vertical = matchMedia("(max-width: 960px)");
  inView(".flow", () => {
    const controls = [];
    $$(".link").forEach((link, li) => {
      $$(".pkt", link).forEach((pkt, i) => {
        if (vertical.matches) pkt.style.left = "-3px";
        const travel = vertical.matches ? { top: ["0%", "100%"] } : { left: ["0%", "100%"] };
        controls.push(...loop(pkt, { ...travel, opacity: [0, 1, 1, 0] }, { duration: 1.5, delay: li * 0.75 + i * 0.5, repeatDelay: 0.2 }));
      });
    });
    return () => controls.forEach((c) => c.cancel());
  }, { amount: 0.3 });

  /* ---------- Passo 1: gravação em duas trilhas, depois a separação de falantes ---------- */
  inView("#ui-record", (demo) => {
    const STEP = 0.07; // segundos por coluna
    const timers = []; let controls = [];
    const time = $("#rec-time");
    const tiles = Object.fromEntries($$(".tile", demo).map((t) => [t.dataset.sp, t]));
    const bars = (lane) => $$(`[data-lane="${lane}"] i`, demo);
    const after = (s, fn) => timers.push(setTimeout(fn, s * 1000));
    const stopAll = () => { timers.splice(0).forEach(clearTimeout); controls.splice(0).forEach((c) => c.stop()); };

    function run() {
      // zera a cena
      demo.classList.remove("is-split");
      $$(".lane i", demo).forEach((b) => { if (!b.classList.contains("is-silent")) { b.style.opacity = 0; b.style.background = GRAY; } });
      Object.values(tiles).forEach((t) => t.classList.remove("is-speaking"));
      time.textContent = "00:00";

      // fase 1: gravando, as duas trilhas se desenham com o tempo e quem fala acende na reunião
      for (let i = 0; i < COLS; i++) {
        after(0.2 + i * STEP, () => {
          Object.values(tiles).forEach((t) => t.classList.toggle("is-speaking", t.dataset.sp === who[i]));
          const s = (i + 1) * 45; time.textContent = `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
        });
      }
      ["you", "meeting"].forEach((lane) => bars(lane).forEach((b, i) => {
        if (b.classList.contains("is-silent")) return;
        controls.push(animate(b, { opacity: [0, 1] }, { duration: 0.25, delay: 0.2 + i * STEP }));
      }));
      const t1 = 0.2 + COLS * STEP + 0.6;
      after(t1 - 0.2, () => Object.values(tiles).forEach((t) => t.classList.remove("is-speaking")));

      // fase 2: a trilha da reunião ganha a cor de cada pessoa e se divide em três trilhas
      after(t1, () => demo.classList.add("is-split"));
      bars("meeting").forEach((b, i) => {
        if (b.classList.contains("is-silent")) return;
        controls.push(animate(b, { backgroundColor: [GRAY, SPEAKER_COLOR[b.dataset.sp]] }, { duration: 0.3, delay: t1 + 0.2 + i * (STEP * 0.6) }));
      });
      ["ana", "bruno", "carla"].forEach((lane) => bars(lane).forEach((b, i) => {
        if (b.classList.contains("is-silent")) return;
        b.style.background = SPEAKER_COLOR[lane];
        controls.push(animate(b, { opacity: [0, 1], y: [-6, 0] }, { duration: 0.3, delay: t1 + 0.5 + i * (STEP * 0.6) }));
      }));
      const t2 = t1 + 0.5 + COLS * STEP * 0.6 + 2.6;
      after(t2, run);
    }
    run();
    return stopAll;
  }, { amount: 0.4 });

  /* ---------- Passo 2: transcrição aparecendo, frase atual passeando ---------- */
  inView("#ui-transcript", (el) => {
    const lines = $$("[data-line]", el);
    lines.forEach((l, i) => animate(l, { opacity: [0, 1], y: [10, 0] }, { duration: 0.6, delay: 0.3 + i * 0.45, ease: EASE }));
    let cur = -1;
    const march = setInterval(() => {
      lines.forEach((l) => l.classList.remove("is-current"));
      cur = (cur + 1) % lines.length;
      lines[cur].classList.add("is-current");
    }, 1500);
    return () => { clearInterval(march); lines.forEach((l) => l.classList.remove("is-current")); };
  }, { amount: 0.5 });

  /* ---------- Passo 3: ata sendo escrita ---------- */
  inView("#ui-summary", (el) => {
    $$("[data-line]", el).forEach((l, i) => animate(l, { opacity: [0, 1], x: [-8, 0] }, { duration: 0.5, delay: 0.4 + i * 0.38, ease: EASE }));
  }, { amount: 0.5 });
}
