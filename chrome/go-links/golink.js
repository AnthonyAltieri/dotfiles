// Client for the golink server (github.com/tailscale/golink) on the tailnet.
//
// The extension only talks to golink over HTTPS at the server's full tailnet name,
// https://go.<tailnet>.ts.net. That name resolves only through Tailscale, and only the tailnet
// can get a certificate for it, so an answer from it means Tailscale is connected and this is
// your server. Bare http://go is used once, to learn that name: with HTTPS on in the tailnet,
// golink redirects http://go there. Off the tailnet http://go can reach some other machine or a
// DNS search page, so its answer counts only if it ends on such a name.

const LEARN_URL = "http://go/";
const TAILNET_ORIGIN = /^https:\/\/go\.[a-z0-9-]+\.ts\.net$/;
const TIMEOUT_MS = 5000;

// Same rule golink enforces on short names.
export const SHORT_NAME = /^\w[\w\-.]*$/;

export class NotConnectedError extends Error {}
export class LinkExistsError extends Error {}

const request = (url, init = {}) => fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS), ...init });

async function learnOrigin() {
  let res;
  try {
    res = await request(LEARN_URL, { method: "HEAD" });
  } catch {
    throw new NotConnectedError("Can't reach your go server. Is Tailscale connected?");
  }
  const origin = new URL(res.url).origin;
  if (!res.ok || !TAILNET_ORIGIN.test(origin)) {
    throw new NotConnectedError(
      `Something other than your go server answered at http://go (${origin}). Is Tailscale connected?`,
    );
  }
  await chrome.storage.local.set({ origin });
  return origin;
}

// The pinned https://go.<tailnet>.ts.net origin, learned on first use.
async function serverOrigin() {
  const { origin } = await chrome.storage.local.get("origin");
  return origin ?? learnOrigin();
}

// Requests path from the server, turning network failures (no Tailscale) into NotConnectedError.
async function get(path, init) {
  const origin = await serverOrigin();
  try {
    return { origin, res: await request(origin + path, init) };
  } catch {
    throw new NotConnectedError(`Can't reach ${origin}. Is Tailscale connected?`);
  }
}

// Resolves to the server's origin once it answers, or throws NotConnectedError.
export async function connectedOrigin() {
  return (await get("/", { method: "HEAD" })).origin;
}

// Every saved link, as golink's /.export JSON lines: {Short, Long, Created, LastEdit, Owner}.
export async function listLinks() {
  const { res } = await get("/.export");
  if (!res.ok) throw new Error(`/.export: HTTP ${res.status}`);
  const text = await res.text();
  return text.split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

// golink only accepts form posts carrying an XSRF token from one of its own pages: the home
// page's token creates new links, a link's detail page token edits that link. The detail page
// answers with JSON unless the request asks for HTML.
async function readForm(path, parseHtml) {
  const { origin, res } = await get(path, { headers: { Accept: "text/html" } });
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  const input = parseHtml(await res.text()).querySelector('input[name="xsrf"]');
  if (!input) throw new Error(`${origin}${path} has no XSRF token`);
  return { origin, xsrf: input.value };
}

// Creates go/<short> -> long, or replaces an existing go/<short> when overwrite is set.
// parseHtml(text) must return a Document (DOMParser is not available in service workers).
export async function saveLink(short, long, { overwrite = false, parseHtml }) {
  if (!SHORT_NAME.test(short)) {
    throw new Error("Use letters, numbers, dashes and periods, starting with a letter or number.");
  }
  const page = overwrite ? `/.detail/${encodeURIComponent(short)}` : "/";
  const { origin, xsrf } = await readForm(page, parseHtml);
  const res = await request(`${origin}/`, {
    method: "POST",
    body: new URLSearchParams({ short, long, xsrf }),
    headers: { Accept: "application/json" },
    // A create that hits an existing name is answered with a redirect to its detail page.
    redirect: "manual",
  });
  if (res.type === "opaqueredirect") throw new LinkExistsError(`go/${short} already exists`);
  if (!res.ok) throw new Error((await res.text()).trim() || `HTTP ${res.status}`);
  return res.json();
}
