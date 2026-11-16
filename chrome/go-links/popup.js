import { LinkExistsError, listLinks, saveLink } from "./golink.js";

const form = document.getElementById("save");
const shortInput = document.getElementById("short");
const longInput = document.getElementById("long");
const existing = document.getElementById("existing");
const submit = document.getElementById("submit");
const status = document.getElementById("status");

const parseHtml = (text) => new DOMParser().parseFromString(text, "text/html");
let linksByShort = new Map();
let confirmOverwrite = null; // short name the user has been asked to confirm overwriting

function show(message, kind = "") {
  status.textContent = message;
  status.className = kind;
}

function showExisting(names) {
  existing.hidden = names.length === 0;
  existing.textContent = names.length ? `Already saved as ${names.map((n) => `go/${n}`).join(", ")}` : "";
}

async function init() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  longInput.value = tab?.url ?? "";
  shortInput.focus();
  try {
    const links = await listLinks();
    linksByShort = new Map(links.map((l) => [l.Short.toLowerCase(), l]));
    showExisting(links.filter((l) => l.Long === longInput.value).map((l) => l.Short));
  } catch {
    show("Can't reach http://go. Is Tailscale connected?", "error");
  }
}

shortInput.addEventListener("input", () => {
  confirmOverwrite = null;
  submit.textContent = "Save";
  show("");
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const short = shortInput.value.trim().replace(/^go\//, "");
  const long = longInput.value.trim();
  const current = linksByShort.get(short.toLowerCase());
  if (current && current.Long !== long && confirmOverwrite !== short) {
    confirmOverwrite = short;
    submit.textContent = "Replace";
    show(`go/${current.Short} points to ${current.Long}. Press Replace to change it.`, "error");
    return;
  }
  submit.disabled = true;
  show("Saving…");
  try {
    const link = await saveLink(short, long, { overwrite: Boolean(current), parseHtml });
    linksByShort.set(link.Short.toLowerCase(), link);
    confirmOverwrite = null;
    submit.textContent = "Save";
    show(`Saved go/${link.Short}`, "ok");
  } catch (err) {
    show(err instanceof LinkExistsError ? `${err.message}. Reopen this popup to replace it.` : err.message, "error");
  } finally {
    submit.disabled = false;
  }
});

init();
