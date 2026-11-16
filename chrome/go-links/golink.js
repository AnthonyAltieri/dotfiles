// Client for the golink server (github.com/tailscale/golink) at http://go on the tailnet.

export const GO = "http://go";

// Same rule golink enforces on short names.
export const SHORT_NAME = /^\w[\w\-.]*$/;

// Every saved link, as golink's /.export JSON lines: {Short, Long, Created, LastEdit, Owner}.
export async function listLinks() {
  const res = await fetch(`${GO}/.export`);
  if (!res.ok) throw new Error(`${GO}/.export: HTTP ${res.status}`);
  const text = await res.text();
  return text.split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

// golink only accepts form posts carrying an XSRF token from one of its own pages: the home
// page's token creates new links, a link's detail page token edits that link. When the tailnet
// has HTTPS, http://go redirects to https://go.<tailnet>.ts.net, and a redirected POST turns
// into a GET, so the post goes straight to the origin the GET landed on.
// The detail page answers with JSON unless the request asks for HTML.
async function readForm(path, parseHtml) {
  const res = await fetch(GO + path, { headers: { Accept: "text/html" } });
  if (!res.ok) throw new Error(`${GO}${path}: HTTP ${res.status}`);
  const input = parseHtml(await res.text()).querySelector('input[name="xsrf"]');
  if (!input) throw new Error(`${GO}${path} has no XSRF token`);
  return { origin: new URL(res.url).origin, xsrf: input.value };
}

export class LinkExistsError extends Error {}

// Creates go/<short> -> long, or replaces an existing go/<short> when overwrite is set.
// parseHtml(text) must return a Document (DOMParser is not available in service workers).
export async function saveLink(short, long, { overwrite = false, parseHtml }) {
  if (!SHORT_NAME.test(short)) {
    throw new Error("Use letters, numbers, dashes and periods, starting with a letter or number.");
  }
  const page = overwrite ? `/.detail/${encodeURIComponent(short)}` : "/";
  const { origin, xsrf } = await readForm(page, parseHtml);
  const res = await fetch(`${origin}/`, {
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
