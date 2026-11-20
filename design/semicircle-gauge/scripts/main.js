/* ==========================================================================
   半圆 / 扇形仪表盘 · 效果图交互脚本（纯原生 JS）
   几何全部参数化生成，支持在 180° 半圆 / 220° 扇形 / 260° 扇形间切换。
   ========================================================================== */
(function () {
  "use strict";

  const $ = (s) => document.querySelector(s);
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const SVG_NS = "http://www.w3.org/2000/svg";
  const $id = (id) => document.getElementById(id);

  /* 极坐标：0° 指向正上方，顺时针为正 */
  function polar(cx, cy, r, deg) {
    const a = (deg * Math.PI) / 180;
    return { x: cx + r * Math.sin(a), y: cy - r * Math.cos(a) };
  }
  const f = (n) => n.toFixed(2);
  function make(tag, attrs) {
    const el = document.createElementNS(SVG_NS, tag);
    for (const k in attrs) el.setAttribute(k, attrs[k]);
    return el;
  }

  /* 圆弧 path */
  function arcPath(cx, cy, r, start, end) {
    const s = polar(cx, cy, r, start), e = polar(cx, cy, r, end);
    const large = Math.abs(end - start) > 180 ? 1 : 0;
    return `M ${f(s.x)} ${f(s.y)} A ${r} ${r} 0 ${large} 1 ${f(e.x)} ${f(e.y)}`;
  }
  /* 扇形面 path（圆心 + 弧） */
  function sectorPath(cx, cy, r, start, end) {
    const s = polar(cx, cy, r, start), e = polar(cx, cy, r, end);
    const large = Math.abs(end - start) > 180 ? 1 : 0;
    return `M ${cx} ${cy} L ${f(s.x)} ${f(s.y)} A ${r} ${r} 0 ${large} 1 ${f(e.x)} ${f(e.y)} Z`;
  }
  /* ---------- 几何常量（圆心下移，只露上半弧；无金属外框） ---------- */
  const C = {
    cx: 100, cy: 108,
    rFace: 92,
    rArc: 84,
    rTickO: 82, rTickMaj: 68, rTickMin: 75,
    rLabel: 57, rInnerRing: 48,
    rNeedleTip: 28,
  };

  /* 三种方案：开口朝下，裁掉下半截 */
  const VARIANTS = {
    half180: { label: "半圆 180°", start: -90, sweep: 180 },
    fan220:  { label: "扇形 220°", start: -110, sweep: 220 },
    fan260:  { label: "扇形 260°", start: -130, sweep: 260 },
  };
  let current = "fan220";

  const MAX = 60, STEPS = 30, MAJOR_EVERY = 5, LABEL_EVERY = 5;

  // 表盘 AVG / MAX 标线：演示值与 Flutter 首页一致（18.6 / 36.8 km/h）。
  const MARKERS = [
    { key: "avg", label: "AVG", value: 18.6 },
    { key: "max", label: "MAX", value: 36.8 },
  ];

  function viewBoxHeight(sweep) {
    const half = sweep / 2;
    // 端点相对圆心的竖直下降量（cos 为负时端点低于圆心）
    const endDrop = -Math.cos((half * Math.PI) / 180);
    // 保底高度：扇形下方要留出透视道路的空间
    return Math.max(
      Math.ceil(C.cy + C.rFace * Math.max(0, endDrop) + 12),
      C.cy + 72
    );
  }

  /* 绘制整个表盘几何 */
  function drawGauge() {
    const v = VARIANTS[current];
    const start = v.start, end = v.start + v.sweep;

    // 视口高度随扇形开口自适应（宽固定 200）
    const h = viewBoxHeight(v.sweep);
    $id("semiGaugeSvg").setAttribute("viewBox", `0 0 200 ${h}`);

    // 无框盘面：去掉金属表圈 / 投影 / 内凹槽，盘面直接延伸到盒边附近
    const bezel = $id("semiBezel");
    bezel.replaceChildren(
      make("path", { class: "speedo__face", fill: "url(#dialMain)", d: sectorPath(C.cx, C.cy, C.rFace, start, end) }),
      make("path", { class: "speedo__inner-ring", d: arcPath(C.cx, C.cy, C.rInnerRing, start, end) })
    );

    // 发光弧（轨道 + 活跃）
    $id("semiTrack").setAttribute("d", arcPath(C.cx, C.cy, C.rArc, start, end));
    $id("semiArc").setAttribute("d", arcPath(C.cx, C.cy, C.rArc, start, end));

    // 刻度 + 数字
    const ticks = $id("semiTicks");
    const frag = document.createDocumentFragment();
    for (let i = 0; i <= STEPS; i++) {
      const deg = start + (v.sweep * i) / STEPS;
      const major = i % MAJOR_EVERY === 0;
      const inner = polar(C.cx, C.cy, major ? C.rTickMaj : C.rTickMin, deg);
      const outer = polar(C.cx, C.cy, C.rTickO, deg);
      const line = make("line", { x1: f(inner.x), y1: f(inner.y), x2: f(outer.x), y2: f(outer.y) });
      if (major) line.classList.add("is-major");
      frag.appendChild(line);
      if (i % LABEL_EVERY === 0) {
        const p = polar(C.cx, C.cy, C.rLabel, deg);
        const t = make("text", {
          x: f(p.x), y: f(p.y),
          transform: `rotate(${f(deg)} ${f(p.x)} ${f(p.y)})`,
        });
        t.setAttribute("class", "speedo__tick-label");
        t.textContent = String(Math.round((MAX * i) / STEPS));
        frag.appendChild(t);
      }
    }
    ticks.replaceChildren(frag);

    drawMarkers(v);

    // 中央铭牌（蓝牙图标已去掉，让下方道路与仪表贴合）
    const center = $id("semiCenter");
    const unit = make("text", { class: "gauge-unit-mark", x: C.cx, y: 60, "text-anchor": "middle" });
    unit.textContent = "km/h";
    center.replaceChildren(unit);

    // 指针几何（尖端朝上，绕圆心旋转）
    $id("semiNeedleBody").setAttribute("d",
      `M${C.cx} ${C.cy} L${C.cx - 4} ${C.cy + 6} L${C.cx} ${C.rNeedleTip} L${C.cx + 4} ${C.cy + 6} Z`);
    $id("semiNeedleTail").setAttribute("d",
      `M${C.cx - 3} ${C.cy} L${C.cx} ${C.cy + 20} L${C.cx + 3} ${C.cy} Z`);

    // 轴心
    const hub = $id("semiHub");
    hub.replaceChildren(
      make("circle", { class: "needle__hub-shadow", cx: C.cx + 1, cy: C.cy + 2, r: 9 }),
      make("circle", { class: "needle__hub-outer", cx: C.cx, cy: C.cy, r: 8.5 }),
      make("circle", { class: "needle__hub", cx: C.cx, cy: C.cy, r: 5 }),
      make("circle", { class: "needle__hub-dot", cx: C.cx, cy: C.cy, r: 1.8 })
    );

    // 玻璃罩高光（只覆盖上半盘面）
    $id("semiGlass").setAttribute("d", sectorPath(C.cx, C.cy, C.rFace, start + 4, end - 4));

    $id("semiModeLabel").textContent = v.label;

    buildRoad();
    update();
  }

  /* ---------- MAX 黄色弧线（底层）+ AVG 小三角标线 ---------- */
  function drawMarkers(v) {
    const frag = document.createDocumentFragment();
    // MAX：从起点画到最高速角度的黄色弧，红色实时弧会盖在上面
    const maxMark = MARKERS.find((m) => m.key === "max");
    if (maxMark && maxMark.value > 0) {
      const ratio = Math.max(0, Math.min(1, maxMark.value / MAX));
      const maxEnd = v.start + v.sweep * ratio;
      $id("semiMaxArc").setAttribute(
        "d", arcPath(C.cx, C.cy, C.rArc, v.start, maxEnd)
      );
    } else {
      $id("semiMaxArc").setAttribute("d", "");
    }
    // AVG 用小三角指向刻度（MAX 已由黄弧表示）
    for (const m of MARKERS.filter((x) => x.key === "avg")) {
      const ratio = Math.max(0, Math.min(1, m.value / MAX));
      const deg = v.start + v.sweep * ratio;
      const a = (deg * Math.PI) / 180;
      const ux = Math.sin(a), uy = -Math.cos(a);
      const tx = Math.cos(a), ty = Math.sin(a);
      const at = (r, t) => ({
        x: C.cx + ux * r + tx * t,
        y: C.cy + uy * r + ty * t,
      });
      const apex = at(84.5, 0), b1 = at(90.5, 2.8), b2 = at(90.5, -2.8);
      const g = make("g", { class: `gauge-marker gauge-marker--${m.key}` });
      g.appendChild(make("path", {
        class: "gauge-marker__arrow",
        d: `M ${f(apex.x)} ${f(apex.y)} L ${f(b1.x)} ${f(b1.y)} L ${f(b2.x)} ${f(b2.y)} Z`,
      }));
      const lp = polar(C.cx, C.cy, 96, deg);
      const label = make("text", {
        class: "gauge-marker__label",
        x: f(lp.x), y: f(lp.y),
        "text-anchor": "middle",
        "dominant-baseline": "central",
      });
      label.textContent = m.label;
      g.appendChild(label);
      frag.appendChild(g);
    }
    $id("gaugeMarkers").replaceChildren(frag);
  }

  /* ======================================================================
     透视道路：扇形下方，几条线 + 由远及近滚动的路纹，营造前进感
     ====================================================================== */
  // 远端收进盘面开口的 V 形区域，近端铺到盒边附近，和仪表连成一体
  const ROAD = { yFar: 116, yNear: 176, wFar: 24, wNear: 90, rungCount: 6 };
  const rungs = [];
  let roadTravel = 0;   // 单调递增的行程，驱动路纹与中心虚线流动
  let lastTs = 0;

  function roadHalfWidth(p) {
    return ROAD.wFar + (ROAD.wNear - ROAD.wFar) * p;
  }
  function buildRoad() {
    const { yFar, yNear, wFar, wNear } = ROAD;
    $id("roadSurface").setAttribute("d",
      `M ${C.cx - wFar} ${yFar} L ${C.cx + wFar} ${yFar} ` +
      `L ${C.cx + wNear} ${yNear} L ${C.cx - wNear} ${yNear} Z`);
    $id("roadEdgeL").setAttribute("d", `M ${C.cx - wFar} ${yFar} L ${C.cx - wNear} ${yNear}`);
    $id("roadEdgeR").setAttribute("d", `M ${C.cx + wFar} ${yFar} L ${C.cx + wNear} ${yNear}`);
    $id("roadCenter").setAttribute("d", `M ${C.cx} ${yFar} L ${C.cx} ${yNear}`);
    const frag = document.createDocumentFragment();
    rungs.length = 0;
    for (let i = 0; i < ROAD.rungCount; i++) {
      const line = make("line", { class: "road__rung" });
      frag.appendChild(line);
      rungs.push(line);
    }
    $id("roadRungs").replaceChildren(frag);
    renderRoad();
  }
  function renderRoad() {
    const span = ROAD.yNear - ROAD.yFar;
    for (let i = 0; i < rungs.length; i++) {
      const p = ((i / rungs.length) + roadTravel) % 1;
      const y = ROAD.yFar + span * p;
      const hw = roadHalfWidth(p);
      const ln = rungs[i];
      ln.setAttribute("x1", f(C.cx - hw));
      ln.setAttribute("x2", f(C.cx + hw));
      ln.setAttribute("y1", f(y));
      ln.setAttribute("y2", f(y));
      ln.setAttribute("stroke-width", f(0.5 + 1.5 * p));
      ln.setAttribute("stroke-opacity", f(0.1 + 0.6 * Math.min(1, p * 2.2) * (1 - p * 0.45)));
    }
    // 中心虚线（dash 16 长）随行程向后流动
    $id("roadCenter").style.strokeDashoffset = f(-((roadTravel * 16) % 16));
  }
  function animateRoad(ts) {
    if (!lastTs) lastTs = ts;
    const dt = Math.min(64, ts - lastTs);
    lastTs = ts;
    const speedRatio = Math.max(0, Math.min(1, state.value / MAX));
    const cyclesPerSec = speedRatio * 0.9;   // 与车速成正比：0 速静止，越快越急
    roadTravel = (roadTravel + (dt / 1000) * cyclesPerSec) % 1024;
    renderRoad();
    requestAnimationFrame(animateRoad);
  }

  /* 用数值更新指针与发光弧 */
  const state = { value: 42.6 };
  function update() {
    const v = VARIANTS[current];
    const ratio = Math.max(0, Math.min(1, state.value / MAX));
    const deg = v.start + v.sweep * ratio;
    $id("semiNeedle").style.setProperty("--angle", `${f(deg)}deg`);
    const arc = $id("semiArc");
    const total = arc.getTotalLength();
    arc.style.strokeDasharray = `${f(total * ratio)} ${f(total)}`;
    $id("semiGaugeSvg").setAttribute("aria-label",
      `主速度指针仪表，当前 ${state.value.toFixed(1)} 公里每小时，${v.label}`);
  }

  /* ---------- 方案切换 ---------- */
  document.querySelectorAll(".variant-bar button").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".variant-bar button").forEach((b) => b.classList.remove("is-active"));
      btn.classList.add("is-active");
      current = btn.dataset.variant;
      drawGauge();
    });
  });

  /* ---------- 演示循环 ---------- */
  // 末尾插入 0：演示「车速为 0 时路面完全停下」，再起步重新加速。
  const SCRIPT = [42.6, 49.3, 55.8, 51.2, 44.7, 37.5, 31.9, 40.4, 0];
  let idx = 0;
  function nextFrame() {
    idx = (idx + 1) % SCRIPT.length;
    state.value = SCRIPT[idx];
    update();
  }

  /* ---------- 其它控件（沿用原稿交互） ---------- */
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
  document.querySelectorAll(".assist__step").forEach((b, i) =>
    b.addEventListener("click", () => setPercent(percent + (i === 0 ? -1 : 1))));

  /* ---------- 初始化 ---------- */
  drawGauge();
  requestAnimationFrame(() => requestAnimationFrame(() => {
    document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-in"));
  }));
  if (!reduceMotion) {
    setInterval(nextFrame, 2600);
    requestAnimationFrame(animateRoad);
  }
})();
