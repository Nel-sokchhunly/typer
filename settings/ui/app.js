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
