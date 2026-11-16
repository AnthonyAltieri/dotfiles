import { listLinks } from "./golink.js";

// Every go/ trip from the address bar goes through go.html, which opens the link only once your
// go server answers over HTTPS (see go.js). Rules are added at install because the redirect
// target holds this extension's ID, which differs per unpacked install.
const GUARD = chrome.runtime.getURL("go.html");
const guardUrl = (path) => `${GUARD}#p=${encodeURI(path)}`;

const RULES = [
  {
    // http://go/<path> and https://go/<path>, typed or from links.
    id: 1,
    priority: 1,
    action: { type: "redirect", redirect: { regexSubstitution: `${GUARD}#p=\\1` } },
    condition: { regexFilter: "^https?://go/(.*)$", resourceTypes: ["main_frame"] },
  },
  {
    // Chrome sends a typed go/<name> to the default search engine.
    id: 2,
    priority: 1,
    action: { type: "redirect", redirect: { regexSubstitution: `${GUARD}#q=\\1` } },
    condition: {
      regexFilter: "^https://www\\.google\\.com/search\\?(?:[^#]*&)?q=go(?:%2F|/)([^&#]*)(?:[&#].*)?$",
      isUrlFilterCaseSensitive: false,
      resourceTypes: ["main_frame"],
    },
  },
];

chrome.runtime.onInstalled.addListener(async () => {
  const old = await chrome.declarativeNetRequest.getDynamicRules();
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: old.map((rule) => rule.id),
    addRules: RULES,
  });
});

// Address-bar keyword: type "go/", press Tab, then part of a link name.
let links = [];

chrome.omnibox.setDefaultSuggestion({ description: "Open go/%s" });

chrome.omnibox.onInputStarted.addListener(async () => {
  try {
    links = await listLinks();
  } catch (err) {
    console.warn("go links: could not load links", err);
  }
});

const escapeXml = (s) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[c]);

// Names that start with the query first, then names or targets that merely contain it.
const rank = (link, query) => (link.Short.toLowerCase().startsWith(query) ? 0 : 1);

chrome.omnibox.onInputChanged.addListener((text, suggest) => {
  const query = text.trim().toLowerCase();
  const matches = links
    .filter((l) => l.Short.toLowerCase().includes(query) || l.Long.toLowerCase().includes(query))
    .sort((a, b) => rank(a, query) - rank(b, query))
    .slice(0, 8);
  suggest(
    matches.map((l) => ({
      content: l.Short,
      description: `<match>go/${escapeXml(l.Short)}</match> <dim>${escapeXml(l.Long)}</dim>`,
    })),
  );
});

chrome.omnibox.onInputEntered.addListener((text, disposition) => {
  const url = guardUrl(text.trim().replace(/^go\//, ""));
  if (disposition === "currentTab") chrome.tabs.update({ url });
  else chrome.tabs.create({ url, active: disposition === "newForegroundTab" });
});
