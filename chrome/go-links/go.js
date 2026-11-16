// Every address-bar trip to go/<name> lands here first (see background.js), so the link only
// opens once your go server answers over HTTPS. Without Tailscale it stops here instead of
// letting the bare name "go" resolve to whatever the current network calls go.
//
// The hash carries the rest of the link:
//   #q=<form-encoded search text after "go/">  from a Google search for go/<name>
//   #p=<path>                                  from http://go/<path> or the go/ keyword
import { connectedOrigin } from "./golink.js";

const title = document.getElementById("title");
const message = document.getElementById("message");
const retry = document.getElementById("retry");

function linkPath() {
  const hash = location.hash.slice(1);
  if (hash.startsWith("p=")) return hash.slice(2);
  if (!hash.startsWith("q=")) return "";
  try {
    return decodeURIComponent(hash.slice(2).replace(/\+/g, " "));
  } catch {
    return hash.slice(2);
  }
}

async function open() {
  const path = linkPath();
  title.textContent = `go/${path}`;
  document.title = `go/${path}`;
  message.textContent = "Checking your go server…";
  message.className = "";
  retry.hidden = true;
  try {
    location.replace(`${await connectedOrigin()}/${path}`);
  } catch (err) {
    message.textContent = err.message;
    message.className = "error";
    retry.hidden = false;
  }
}

retry.addEventListener("click", open);
open();
