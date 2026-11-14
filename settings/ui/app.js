const INFO = {
  generated: ["Extra words", "ពាក្យបន្ថែម", "Suggest words whose Latin spellings Typer guessed by rule. They always rank below known words."],
  english: ["English words", "ពាក្យអង់គ្លេស", "Mix English into suggestions: thank you bong → thank you បង."],
  learn: ["Learn from my picks", "រៀនពីការជ្រើសរើស", "Rank what you pick higher next time. Off: nothing new is saved."],
  badge: ["Mode badge", "សញ្ញា ខ / EN", "Show the small ខ / EN badge under the cursor."],
};
const { invoke } = window.__TAURI__.core;
const err = document.getElementById("err");
invoke("get_settings").then(settings => {
  const list = document.getElementById("list");
  for (const [name, on] of settings) {
    const [title, km, desc] = INFO[name] || [name, "", ""];
    const label = document.createElement("label");
    label.innerHTML = `<span class="text"><span class="name"></span> <span class="km"></span><br><span class="desc"></span></span>
      <input type="checkbox" role="switch">`;
    label.querySelector(".name").textContent = title;
    label.querySelector(".km").textContent = km;
    label.querySelector(".desc").textContent = desc;
    const box = label.querySelector("input");
    box.checked = on;
    box.addEventListener("change", () => {
      err.textContent = "";
      invoke("set_setting", { name, on: box.checked }).catch(e => {
        box.checked = !box.checked;
        err.textContent = "Couldn't save: " + e;
      });
    });
    list.append(label);
  }
}).catch(e => { err.textContent = "Couldn't read settings: " + e; });

const tabs = document.querySelectorAll("nav button");
const show = tab => {
  for (const b of tabs) b.setAttribute("aria-selected", b.dataset.tab === tab);
  for (const s of document.querySelectorAll("section")) s.hidden = s.id !== tab;
};
for (const b of tabs) b.addEventListener("click", () => show(b.dataset.tab));

invoke("welcome").then(([tutorial, os]) => {
  if (["macos", "windows", "linux"].includes(os)) {
    for (const p of document.querySelectorAll("[data-os]")) p.hidden = p.dataset.os !== os;
  }
  if (os === "macos") {
    for (const k of document.querySelectorAll(".enter")) k.textContent = "Return";
    for (const k of document.querySelectorAll(".del")) k.textContent = "Delete";
  }
  if (tutorial) show("tutorial");
}).finally(() => { document.body.style.visibility = ""; });

const practice = document.getElementById("practice");
practice.addEventListener("input", () => {
  document.getElementById("done").hidden = !practice.value.includes("ខ្ញុំទៅសាលារៀន");
});

document.querySelectorAll(".demo").forEach(d => {
  const v = d.querySelector("video"), b = d.querySelector("button");
  const sync = () => { b.textContent = v.paused ? "▶" : "⏸"; b.setAttribute("aria-label", v.paused ? b.dataset.play : b.dataset.pause); };
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) { v.removeAttribute("autoplay"); v.pause(); }
  b.onclick = () => v.paused ? v.play().catch(() => {}) : v.pause();
  v.onplay = v.onpause = sync; sync();
});
