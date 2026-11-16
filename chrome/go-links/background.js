// Address-bar keyword: type "go/", press Tab, then part of a link name.
import { GO, listLinks } from "./golink.js";

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
  const url = `${GO}/${text.trim().replace(/^go\//, "")}`;
  if (disposition === "currentTab") chrome.tabs.update({ url });
  else chrome.tabs.create({ url, active: disposition === "newForegroundTab" });
});
