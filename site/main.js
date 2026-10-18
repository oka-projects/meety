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
function reveal(root, { delay = 0, step = 0.09, y = 28, duration = 0.9 } = {}) {
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

if (reduced) {
  // Sem movimento: tudo visível, barra de progresso e navegação sólida ainda funcionam.
  scroll((p) => { $("#progress").style.transform = `scaleX(${p})`; nav.classList.toggle("is-solid", p > 0.01); });
} else {
  /* ---------- Carga: hero em cascata ---------- */
  reveal($("#hero"), { delay: 0.1, step: 0.11, y: 34, duration: 1.1 });

  /* ---------- Scroll: progresso, navegação, atmosfera ---------- */
  scroll(animate("#progress", { scaleX: [0, 1] }, { ease: "linear" }));
  scroll((p, info) => nav.classList.toggle("is-solid", info.y.current > 24));
  scroll(animate(".glow-a", { x: [0, 260], y: [0, 520], opacity: [1, 0.55] }, { ease: "linear" }));
  scroll(animate(".glow-b", { x: [0, -320], y: [0, -140], opacity: [0.9, 0.5] }, { ease: "linear" }));

  /* ---------- Hero sai de cena quando a seção seguinte desliza por cima ---------- */
  const local = $("#local");
  scroll(animate(".hero-inner", { opacity: [1, 0], scale: [1, 0.93], y: [0, -70] }, { ease: "linear" }), {
    target: local, offset: ["start end", "start 15%"],
  });
  scroll(animate(".window-hero", { y: [0, 90] }, { ease: "linear" }), { target: local, offset: ["start end", "start start"] });

  /* ---------- Seções: entram subindo, filhos em cascata, saem esmaecendo ---------- */
  const sections = $$(".section");
  sections.forEach((sec, idx) => {
    sec.style.opacity = "0";
    inView(sec, () => {
      animate(sec, { opacity: [0, 1], y: [56, 0], scale: [0.985, 1] }, { duration: 1, ease: EASE });
      reveal(sec, { delay: 0.18, step: 0.08 });
    }, { amount: 0.12 });
    if (idx < sections.length - 1) {
      scroll(animate($(".inner", sec), { opacity: [1, 0.25], y: [0, -40] }, { ease: "linear" }), {
        target: sec, offset: ["end 55%", "end start"],
      });
    }
  });

  /* ---------- Hero: ondas de áudio ---------- */
  const wave = $("#wave");
  for (let i = 0; i < 44; i++) {
    const bar = document.createElement("i");
    wave.appendChild(bar);
    const a = 0.3 + Math.random() * 0.7;
    loop(bar, { transform: ["scaleY(0.08)", `scaleY(${a.toFixed(2)})`] }, { duration: 0.7 + Math.random() * 0.9, delay: Math.random() * 0.6, mirror: true });
  }

  /* ---------- Fluxo "nada sai do Mac": pacotes viajando ---------- */
  const vertical = matchMedia("(max-width: 900px)");
  inView(".flow", () => {
    const controls = [];
    $$(".link").forEach((link, li) => {
      $$(".pkt", link).forEach((pkt, i) => {
        if (vertical.matches) pkt.style.left = "-3px";
        const travel = vertical.matches ? { top: ["0%", "100%"] } : { left: ["0%", "100%"] };
        controls.push(...loop(pkt, { ...travel, opacity: [0, 1, 1, 0] }, { duration: 1.5, delay: li * 0.75 + i * 0.5, repeatDelay: 0.2, ease: "ease-in-out" }));
      });
    });
    controls.push(...loop(".chip-core", { filter: ["brightness(1)", "brightness(1.3)"] }, { duration: 0.75, mirror: true }));
    return () => controls.forEach((c) => c.cancel());
  }, { amount: 0.3 });

  /* ---------- Passo 1: gravando ---------- */
  inView("#ui-record", () => {
    const time = $("#rec-time");
    let s = 0;
    const tick = setInterval(() => {
      s += 1;
      const h = String(Math.floor(s / 3600)).padStart(2, "0"), m = String(Math.floor((s % 3600) / 60)).padStart(2, "0"), ss = String(s % 60).padStart(2, "0");
      time.textContent = `${h}:${m}:${ss}`;
    }, 1000);
    const controls = [
      ...loop(".rec-btn", { boxShadow: ["0 0 0 0 rgba(255,98,89,0.45)", "0 0 0 16px rgba(255,98,89,0)"] }, { duration: 1.5, ease: "ease-out" }),
      ...loop("#meter-you", { transform: ["scaleX(0.15)", "scaleX(0.95)"] }, { duration: 0.55, mirror: true }),
      ...loop("#meter-others", { transform: ["scaleX(0.9)", "scaleX(0.2)"] }, { duration: 0.8, mirror: true }),
    ];
    return () => { clearInterval(tick); controls.forEach((c) => c.cancel()); };
  }, { amount: 0.5 });

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
