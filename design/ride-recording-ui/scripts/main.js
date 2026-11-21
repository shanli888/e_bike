/* ==========================================================================
   原型交互：表盘生成 / 屏幕切换 / 按钮演示 / 设计说明
   ========================================================================== */

(function () {
  'use strict';

  /* ---------- 表盘生成（复用真机指针表盘逻辑） ---------- */
  const CX = 170, CY = 168, R = 138;
  const START = 210, END = -30, SPAN = START - END; // 240° 扫过

  function polar(angleDeg, radius) {
    const a = (angleDeg * Math.PI) / 180;
    return { x: CX + radius * Math.cos(a), y: CY - radius * Math.sin(a) };
  }
  function arcPath(fromAngle, toAngle, radius) {
    const s = polar(fromAngle, radius);
    const e = polar(toAngle, radius);
    const large = Math.abs(fromAngle - toAngle) > 180 ? 1 : 0;
    return `M ${s.x.toFixed(2)} ${s.y.toFixed(2)} A ${radius} ${radius} 0 ${large} 0 ${e.x.toFixed(2)} ${e.y.toFixed(2)}`;
  }
  function angleFor(value, max) {
    return START - (Math.min(value, max) / max) * SPAN;
  }

  function buildGauge(wrap) {
    const speed = parseFloat(wrap.dataset.speed || '0');
    const avg = parseFloat(wrap.dataset.avg || '0');
    const max = parseFloat(wrap.dataset.max || '0');
    const MAXV = 60;
    const svg = wrap.querySelector('.gauge-svg');
    const parts = [];

    // 底层刻度轨道
    parts.push(`<path d="${arcPath(START, END, R)}" fill="none" stroke="var(--gauge-track)" stroke-width="9" stroke-linecap="round"/>`);

    // AVG 弧（青色，从起点到均速）
    if (avg > 0) {
      parts.push(`<path d="${arcPath(START, angleFor(avg, MAXV), R)}" fill="none" stroke="var(--color-cyan)" stroke-width="6" stroke-linecap="round" opacity="0.9"/>`);
    }
    // MAX 弧（橙色，从极速到终点）
    if (max > 0) {
      parts.push(`<path d="${arcPath(angleFor(max, MAXV), END, R)}" fill="none" stroke="var(--color-orange)" stroke-width="6" stroke-linecap="round" opacity="0.9"/>`);
    }

    // 刻度：每 2 一格，每 10 主刻度
    for (let v = 0; v <= MAXV; v += 2) {
      const a = angleFor(v, MAXV);
      const major = v % 10 === 0;
      const p1 = polar(a, major ? R - 15 : R - 10);
      const p2 = polar(a, R - 3);
      parts.push(`<line x1="${p1.x.toFixed(2)}" y1="${p1.y.toFixed(2)}" x2="${p2.x.toFixed(2)}" y2="${p2.y.toFixed(2)}" stroke="${major ? 'var(--gauge-tick-major)' : 'var(--gauge-tick)'}" stroke-width="${major ? 2 : 1}" stroke-linecap="round"/>`);
      if (major) {
        const tp = polar(a, R - 27);
        parts.push(`<text x="${tp.x.toFixed(2)}" y="${tp.y.toFixed(2)}" fill="var(--gauge-tick-major)" font-family="var(--font-mono)" font-size="12" text-anchor="middle" dominant-baseline="central">${v}</text>`);
      }
    }

    // AVG / MAX 弧端标注
    if (avg > 0) {
      const ap = polar(angleFor(avg, MAXV), R + 8);
      parts.push(`<text x="${ap.x.toFixed(2)}" y="${ap.y.toFixed(2)}" fill="var(--color-cyan)" font-family="var(--font-mono)" font-size="9" font-style="italic" text-anchor="middle" dominant-baseline="central">AVG</text>`);
    }
    if (max > 0) {
      const mp = polar(angleFor(max, MAXV), R + 8);
      parts.push(`<text x="${mp.x.toFixed(2)}" y="${mp.y.toFixed(2)}" fill="var(--color-orange)" font-family="var(--font-mono)" font-size="9" font-style="italic" text-anchor="middle" dominant-baseline="central">MAX</text>`);
    }

    // 内圈导引弧
    parts.push(`<path d="${arcPath(START, END, R - 34)}" fill="none" stroke="rgba(146,176,218,0.07)" stroke-width="1"/>`);

    // 指针
    const needleA = angleFor(speed, MAXV);
    const tip = polar(needleA, R - 20);
    const tail = polar(needleA + 180, 18);
    parts.push(`<line x1="${tail.x.toFixed(2)}" y1="${tail.y.toFixed(2)}" x2="${tip.x.toFixed(2)}" y2="${tip.y.toFixed(2)}" stroke="var(--needle-main)" stroke-width="3" stroke-linecap="round" style="filter:drop-shadow(0 0 4px rgba(255,176,32,.55))"/>`);
    parts.push(`<circle cx="${CX}" cy="${CY}" r="9" fill="#0a0e1c" stroke="var(--needle-main)" stroke-width="2.5"/>`);
    parts.push(`<circle cx="${CX}" cy="${CY}" r="3.5" fill="var(--needle-main)"/>`);

    // 底部基线（呼应真机表盘下的三角台）
    parts.push(`<path d="M ${polar(START, R+4).x.toFixed(1)} ${polar(START, R+4).y.toFixed(1)} L ${CX} ${CY+52} L ${polar(END, R+4).x.toFixed(1)} ${polar(END, R+4).y.toFixed(1)}" fill="none" stroke="rgba(130,190,255,0.22)" stroke-width="1"/>`);

    svg.innerHTML = parts.join('');
  }

  document.querySelectorAll('.gauge-wrap').forEach(buildGauge);

  /* ---------- 设计说明内容 ---------- */
  const NOTES = {
    standby: {
      title: '01 · 纯码表模式（未连接助力）',
      blocks: [
        ['分水岭切分', '未连接助力器时，助力控制卡片与传感器行整块隐藏，App 退化为独立骑行记录码表，只保留 GPS 可驱动的速度、均速、极速、里程。'],
        ['主行动点', '空出的空间交给「开始骑行」主按钮，一个动作进入记录态——这是本期记录功能的主场。'],
        ['连接入口保留', '底部「设备」标签弱化为「连接助力器」，随时能回到完整模式，避免死路。']
      ]
    },
    assist: {
      title: '02 · 助力完整模式（已连接）',
      blocks: [
        ['完全兼容', '已连接电机控制器 / BR80 闪控时，界面与现有真机版本一致：助力控制卡片 + 电量/温度/陀螺仪三卡完整保留。'],
        ['记录不缺席', '骑行记录控制以悬浮条形式叠加，助力与记录两套功能并行不悖。'],
        ['视觉同源', '暖色描边助力卡、数码管读数、三色语义均沿用真机，无重绘成本。']
      ]
    },
    recording: {
      title: '03 · 记录中 · 实时数据',
      blocks: [
        ['录制状态可感知', '红色呼吸点 + 计时数码管明确「正在记录」，暂停 / 结束一键可达。'],
        ['轨迹可视化', '自绘 GPS 轨迹缩略图实时生长，无需在线地图瓦片，全程离线。'],
        ['衍生指标', '爬升、坡度、卡路里为纯算法产出，作为后期外接设备指标的位置预留。']
      ]
    },
    summary: {
      title: '04 · 骑行汇总弹层',
      blocks: [
        ['结束即汇总', '结束记录后底部弹出汇总，六项核心数据一屏看全，保存后进入历史。'],
        ['关键口径', '移动均速排除停止时间，避免等红灯拉低数值。'],
        ['数据主权', '保存仅写入本机 SQLite，不上传、不联网。']
      ]
    },
    history: {
      title: '05 · 历史列表',
      blocks: [
        ['一目了然', '时间倒序列表，每条带轨迹缩略图 + 距离/时长/均速三要素。'],
        ['生涯统计', '顶部本月里程、次数、累计爬升，按日期范围筛选。'],
        ['本地数据', '全部来自本地数据库，支持删除单条与 GPX 导出。']
      ]
    },
    detail: {
      title: '06 · 骑行详情 · 曲线分析',
      blocks: [
        ['轨迹回放', '自绘轨迹 + 时间轴回放，当前位置随时间移动。'],
        ['双曲线', '速度曲线（蓝）与海拔剖面（金）叠加，横轴为距离。'],
        ['分段与 PB', '每公里分段用时与速度，个人最佳以金色高亮标注。']
      ]
    },
    navigation: {
      title: '07 · 路书跟随导航',
      blocks: [
        ['零 SDK', '纯自绘轨迹图，不接三方地图、不注册开发者、不需要 key、完全离线。'],
        ['只做三件事', '位置投影算进度、偏航检测、关键点提示——不做实时算路。'],
        ['可替换架构', '绘制抽象为 RouteMapRenderer，后期换真实底图不动导航算法。']
      ]
    }
  };

  const notesTitle = document.getElementById('notes-title');
  const notesBody = document.getElementById('notes-body');
  function renderNotes(key) {
    const n = NOTES[key] || NOTES.standby;
    notesTitle.textContent = n.title;
    notesBody.innerHTML = n.blocks.map(function (b) {
      return '<div class="note-block"><p class="note-h">' + b[0] + '</p><p class="note-p">' + b[1] + '</p></div>';
    }).join('');
  }

  /* ---------- 屏幕切换 ---------- */
  const screens = Array.prototype.slice.call(document.querySelectorAll('.screen'));
  const pickers = Array.prototype.slice.call(document.querySelectorAll('.picker-btn'));
  function showScreen(key, updateHash) {
    if (!NOTES[key]) key = 'standby';
    screens.forEach(function (s) { s.hidden = s.dataset.screen !== key; });
    pickers.forEach(function (p) { p.classList.toggle('active', p.dataset.target === key); });
    renderNotes(key);
    if (updateHash && location.hash !== '#' + key) {
      history.replaceState(null, '', '#' + key);
    }
  }
  pickers.forEach(function (p) {
    p.addEventListener('click', function () { showScreen(p.dataset.target, true); });
  });
  document.querySelectorAll('[data-go]').forEach(function (el) {
    el.addEventListener('click', function () { showScreen(el.dataset.go, true); });
  });
  window.addEventListener('hashchange', function () {
    showScreen(location.hash.replace('#', ''), false);
  });

  // 初始屏幕（入场动画改由 CSS 驱动，避免依赖 rAF 时序）
  const initial = location.hash.replace('#', '') || 'standby';
  showScreen(initial, false);
})();
