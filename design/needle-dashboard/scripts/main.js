/* ==========================================================================
   指针仪表盘 · 交互脚本
   职责：生成刻度 / 计算指针角度与发光弧线 / 演示循环 / 来源切换 / 入场序列
   纯原生 JS，无外部依赖。所有动画在 prefers-reduced-motion 下自动降级。
   ========================================================================== */

(function () {
  "use strict";

  const $ = (sel) => document.querySelector(sel);
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- 极坐标：0° 指向正上方，顺时针为正 ---------- */
  function polar(cx, cy, r, deg) {
    const rad = (deg * Math.PI) / 180;
    return { x: cx + r * Math.sin(rad), y: cy - r * Math.cos(rad) };
  }

  /* ---------- 生成一段圆弧 path（起始角 → 结束角，顺时针） ---------- */
  function arcPath(cx, cy, r, startDeg, endDeg) {
    const s = polar(cx, cy, r, startDeg);
    const e = polar(cx, cy, r, endDeg);
    const large = Math.abs(endDeg - startDeg) > 180 ? 1 : 0;
    return `M ${s.x.toFixed(2)} ${s.y.toFixed(2)} A ${r} ${r} 0 ${large} 1 ${e.x.toFixed(2)} ${e.y.toFixed(2)}`;
  }

  const SVG_NS = "http://www.w3.org/2000/svg";
  function make(tag, attrs) {
    const el = document.createElementNS(SVG_NS, tag);
    for (const k in attrs) el.setAttribute(k, attrs[k]);
    return el;
  }

  /* ======================================================================
     刻度生成器
     ====================================================================== */
  function buildTicks(groupId, cfg) {
    const group = $(groupId);
    if (!group) return;
    const frag = document.createDocumentFragment();

    for (let i = 0; i <= cfg.steps; i++) {
      const deg = cfg.start + (cfg.sweep * i) / cfg.steps;
      const major = cfg.majorEvery > 0 && i % cfg.majorEvery === 0;
      const inner = polar(cfg.cx, cfg.cy, major ? cfg.rMajorInner : cfg.rMinorInner, deg);
      const outer = polar(cfg.cx, cfg.cy, cfg.rOuter, deg);
      const line = make("line", {
        x1: inner.x.toFixed(2), y1: inner.y.toFixed(2),
        x2: outer.x.toFixed(2), y2: outer.y.toFixed(2),
      });
      if (major) line.classList.add("is-major");
      frag.appendChild(line);

      // 数字标签：沿弧线径向倾斜排列（德系机械仪表盘的标志性排布）
      if (cfg.labelEvery > 0 && i % cfg.labelEvery === 0) {
        const p = polar(cfg.cx, cfg.cy, cfg.rLabel, deg);
        const t = make("text", {
          x: p.x.toFixed(2),
          y: p.y.toFixed(2),
          transform: `rotate(${deg.toFixed(2)} ${p.x.toFixed(2)} ${p.y.toFixed(2)})`,
        });
        t.setAttribute("class", "speedo__tick-label");
        t.textContent = String(Math.round((cfg.max * i) / cfg.steps));
        frag.appendChild(t);
      }
    }
    group.appendChild(frag);
  }

  /* ======================================================================
     表盘配置
     ====================================================================== */
  const MAIN = {
    cx: 100, cy: 100, rOuter: 90, rMajorInner: 79, rMinorInner: 84,
    rLabel: 68, rArc: 84,
    start: -135, sweep: 270, max: 60, steps: 30,
    majorEvery: 5, labelEvery: 5,
    arc: "#arcMain", track: "#arcTrackMain", needle: "#needleMain",
  };

  function initGauge(cfg) {
    // 轨道弧线（固定）
    const track = $(cfg.track);
    track.setAttribute("d", arcPath(cfg.cx, cfg.cy, cfg.rArc, cfg.start, cfg.start + cfg.sweep));
    // 活跃弧线：用 dasharray 控制填充长度
    const arc = $(cfg.arc);
    arc.setAttribute("d", arcPath(cfg.cx, cfg.cy, cfg.rArc, cfg.start, cfg.start + cfg.sweep));
    const total = arc.getTotalLength();
    arc.dataset.total = total.toFixed(2);
    arc.style.strokeDasharray = `0 ${total.toFixed(2)}`;
  }

  function updateGauge(cfg, value) {
    const arc = $(cfg.arc);
    const ratio = Math.max(0, Math.min(1, value / cfg.max));
    const total = parseFloat(arc.dataset.total);
    arc.style.strokeDasharray = `${(total * ratio).toFixed(2)} ${total.toFixed(2)}`;
    const deg = cfg.start + cfg.sweep * ratio;
    $(cfg.needle).style.setProperty("--angle", `${deg.toFixed(2)}deg`);
  }

  /* ======================================================================
     数值状态 + 演示循环
     ====================================================================== */
  const state = { main: 42.6 };

  function render() {
    // 表盘只保留指针；速度值写入 aria-label 供屏幕阅读器读取
    $("#mainGaugeSvg").setAttribute("aria-label", `主速度指针仪表，当前 ${state.main.toFixed(1)} 公里每小时`);
    updateGauge(MAIN, state.main);
  }

  // 演示数据轨迹：0–60 区间内循环，指针带节奏地扫动
  const SCRIPT = [
    { main: 42.6 },
    { main: 49.3 },
    { main: 55.8 },
    { main: 51.2 },
    { main: 44.7 },
    { main: 37.5 },
    { main: 31.9 },
    { main: 40.4 },
  ];
  let scriptIndex = 0;
  function nextFrame() {
    scriptIndex = (scriptIndex + 1) % SCRIPT.length;
    Object.assign(state, SCRIPT[scriptIndex]);
    render();
  }

  /* ---------- 助力：模式 / 滑杆 ---------- */
  document.querySelectorAll(".assist__modes button").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".assist__modes button").forEach((b) => {
        b.classList.remove("is-active");
        b.removeAttribute("aria-pressed");
      });
      btn.classList.add("is-active");
      btn.setAttribute("aria-pressed", "true");
    });
  });

  const slider = $(".assist__slider");
  let percent = 45;
  function setPercent(v) {
    percent = Math.max(0, Math.min(99, Math.round(v)));
    $("#sliderFill").style.width = percent + "%";
    $("#sliderThumb").style.left = percent + "%";
    $("#assistPercent").textContent = percent + "%";
    slider.setAttribute("aria-valuenow", String(percent));
  }
  slider.addEventListener("pointerdown", (e) => {
    const move = (ev) => {
      const r = slider.getBoundingClientRect();
      setPercent(((ev.clientX - r.left) / r.width) * 99);
    };
    move(e);
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  });
  slider.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight" || e.key === "ArrowUp") { setPercent(percent + 1); e.preventDefault(); }
    if (e.key === "ArrowLeft" || e.key === "ArrowDown") { setPercent(percent - 1); e.preventDefault(); }
  });
  document.querySelectorAll(".assist__step").forEach((btn, i) => {
    btn.addEventListener("click", () => setPercent(percent + (i === 0 ? -1 : 1)));
  });

  /* ---------- 底部导航（视觉演示） ---------- */
  document.querySelectorAll(".bottomnav button").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".bottomnav button").forEach((b) => {
        b.classList.remove("is-active");
        b.removeAttribute("aria-current");
      });
      btn.classList.add("is-active");
      btn.setAttribute("aria-current", "page");
    });
  });

  /* ======================================================================
     初始化 + 入场序列
     ====================================================================== */
  buildTicks("#ticksMain", MAIN);
  initGauge(MAIN);

  // 先落在起始角，入场后扫到首个数值 —— 形成一次完整的仪表自检动画
  $(MAIN.needle).style.setProperty("--angle", `${MAIN.start}deg`);

  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-in"));
      setTimeout(render, reduceMotion ? 0 : 220);
    });
  });

  if (!reduceMotion) {
    setInterval(nextFrame, 2600);
  }
})();
