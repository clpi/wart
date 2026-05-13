const BENCHES = [
  { name: "compute_bench", path: "wasm/compute_bench.wasm" },
  { name: "arithmetic_bench", path: "wasm/arithmetic_bench.wasm" },
];

const resultsEl = document.getElementById("results");
const statusEl = document.getElementById("status");
const runBtn = document.getElementById("run");
const warmupInput = document.getElementById("warmup");
const runsInput = document.getElementById("runs");

function setStatus(text) {
  statusEl.textContent = text;
}

function formatMs(ms) {
  if (ms < 1) return `${(ms * 1000).toFixed(2)}us`;
  if (ms < 1000) return `${ms.toFixed(2)}ms`;
  return `${(ms / 1000).toFixed(2)}s`;
}

function selectEntry(exports) {
  if (typeof exports._start === "function") return exports._start;
  if (typeof exports.main === "function") return exports.main;
  for (const key of Object.keys(exports)) {
    if (typeof exports[key] === "function") return exports[key];
  }
  return null;
}

async function loadModule(path) {
  const resp = await fetch(path);
  const bytes = await resp.arrayBuffer();
  return WebAssembly.compile(bytes);
}

async function runBench(module, warmup, runs) {
  const instance = await WebAssembly.instantiate(module, {});
  const entry = selectEntry(instance.exports);
  if (!entry) return { error: "no callable export" };

  for (let i = 0; i < warmup; i += 1) {
    entry();
  }

  let total = 0;
  for (let i = 0; i < runs; i += 1) {
    const start = performance.now();
    entry();
    const end = performance.now();
    total += end - start;
  }

  return { avg: total / runs };
}

function renderResult(name, avg, note) {
  const tr = document.createElement("tr");
  const nameTd = document.createElement("td");
  nameTd.textContent = name;
  const avgTd = document.createElement("td");
  avgTd.textContent = avg ? formatMs(avg) : "error";
  const noteTd = document.createElement("td");
  noteTd.textContent = note || "";
  tr.appendChild(nameTd);
  tr.appendChild(avgTd);
  tr.appendChild(noteTd);
  resultsEl.appendChild(tr);
}

async function runAll() {
  resultsEl.innerHTML = "";
  const warmup = Number(warmupInput.value) || 0;
  const runs = Math.max(1, Number(runsInput.value) || 1);

  runBtn.disabled = true;
  setStatus("Loading modules...");

  const compiled = [];
  for (const bench of BENCHES) {
    try {
      const module = await loadModule(bench.path);
      compiled.push({ bench, module });
    } catch (err) {
      renderResult(bench.name, null, "load failed");
    }
  }

  setStatus("Running...");
  for (const item of compiled) {
    try {
      const res = await runBench(item.module, warmup, runs);
      if (res.error) {
        renderResult(item.bench.name, null, res.error);
      } else {
        renderResult(item.bench.name, res.avg, "");
      }
    } catch (err) {
      renderResult(item.bench.name, null, "run failed");
    }
  }

  setStatus("Done");
  runBtn.disabled = false;
}

runBtn.addEventListener("click", runAll);
