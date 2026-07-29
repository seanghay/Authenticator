// Renders site/og.png, the Open Graph card for the landing page.
//
//   cd site/og && npm install && npm run build
//
// The window on the right is built out of elements rather than dropped in as a
// screenshot: it stays crisp at any scale, carries demo accounts instead of real
// ones, and re-renders for free when the palette changes.
//
// takumi lays out with flexbox and has no block flow, so every container holding
// more than bare text declares display:flex explicitly.

import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { render } from "takumi-js";

const repoRoot = fileURLToPath(new URL("../../", import.meta.url));
const output = process.argv[2] ?? `${repoRoot}site/og.png`;

const iconPath = `${repoRoot}Authenticator/Assets.xcassets/AppIcon.appiconset/icon_512x512.png`;
const icon = `data:image/png;base64,${(await readFile(iconPath)).toString("base64")}`;

const ACCENT = "#0a84ff";
const SURFACE = "#1c1c1e";
const HAIRLINE = "#303034";
const DIM = "#8e8e93";

/** One account row in the mock window. `progress` picks how full the ring looks. */
const row = ({ issuer, account, code, progress, last = false }) => `
  <div style="
    display:flex;align-items:center;padding:17px 22px;
    ${last ? "" : `border-bottom:1px solid ${HAIRLINE};`}
  ">
    <div style="display:flex;flex-direction:column;flex:1;">
      <div style="display:flex;font-size:19px;font-weight:600;color:#ffffff;letter-spacing:-0.3px;">${issuer}</div>
      <div style="display:flex;font-size:14px;color:${DIM};margin-top:3px;">${account}</div>
      <div style="display:flex;font-size:29px;color:#f2f2f7;margin-top:7px;letter-spacing:2px;">${code}</div>
    </div>
    ${ring(progress)}
  </div>`;

/**
 * The countdown ring. Borders are the only primitive here, so the arc is faked by
 * greying out sides: 3 -> full, 2 -> two thirds, 1 -> one third.
 */
const ring = (progress) => {
  const sides = {
    3: "",
    2: `border-bottom-color:${HAIRLINE};border-left-color:${HAIRLINE};`,
    1: `border-bottom-color:${HAIRLINE};border-left-color:${HAIRLINE};border-right-color:${HAIRLINE};`,
  }[progress];
  return `<div style="display:flex;width:32px;height:32px;border-radius:16px;border:3px solid ${ACCENT};${sides}"></div>`;
};

const html = `
<div style="
  width:1200px;height:630px;display:flex;align-items:center;overflow:hidden;
  background:linear-gradient(135deg,#0b0e14 0%,#111726 48%,#0d1c38 100%);
  font-family:Geist;
">
  <!-- Left: what it is -->
  <div style="display:flex;flex-direction:column;justify-content:center;width:620px;height:630px;padding:0 28px 0 72px;">
    <div style="display:flex;align-items:center;">
      <img src="${icon}" style="width:64px;height:64px;" />
      <div style="display:flex;font-size:27px;font-weight:600;color:#ffffff;margin-left:16px;letter-spacing:-0.4px;">
        Authenticator
      </div>
    </div>

    <div style="display:flex;flex-direction:column;margin-top:34px;">
      <div style="display:flex;font-size:55px;font-weight:700;color:#ffffff;letter-spacing:-2px;line-height:1.06;">
        Two-factor codes,
      </div>
      <div style="display:flex;font-size:55px;font-weight:700;color:${ACCENT};letter-spacing:-2px;line-height:1.06;">
        native on your Mac.
      </div>
    </div>

    <div style="display:flex;font-size:25px;color:#98a1b3;margin-top:24px;letter-spacing:-0.4px;">
      Scan a QR code, search, click to copy.
    </div>

    <!-- align-items:center keeps the dividers on the text's optical centre. -->
    <div style="display:flex;align-items:center;margin-top:40px;">
      <div style="display:flex;font-size:21px;color:#ffffff;font-weight:600;">Touch ID</div>
      <div style="display:flex;font-size:21px;color:#4a5468;padding:0 11px;">·</div>
      <div style="display:flex;font-size:21px;color:#ffffff;font-weight:600;">Encrypted</div>
      <div style="display:flex;font-size:21px;color:#4a5468;padding:0 11px;">·</div>
      <div style="display:flex;font-size:21px;color:#ffffff;font-weight:600;">Offline</div>
    </div>
  </div>

  <!-- Right: the product itself, bleeding off the edge so it reads as a window -->
  <div style="display:flex;align-items:center;width:580px;height:630px;overflow:hidden;">
    <div style="
      display:flex;flex-direction:column;width:600px;margin-left:10px;
      background:${SURFACE};border:1px solid ${HAIRLINE};border-radius:20px;overflow:hidden;
      box-shadow:0 26px 70px rgba(0,0,0,0.55);
    ">
      <!-- title bar -->
      <div style="display:flex;align-items:center;padding:16px 20px;border-bottom:1px solid ${HAIRLINE};">
        <div style="display:flex;width:12px;height:12px;border-radius:6px;background:#ff5f57;"></div>
        <div style="display:flex;width:12px;height:12px;border-radius:6px;background:#febc2e;margin-left:8px;"></div>
        <div style="display:flex;width:12px;height:12px;border-radius:6px;background:#28c840;margin-left:8px;"></div>
        <div style="display:flex;flex:1;justify-content:center;font-size:15px;font-weight:600;color:#e5e5ea;">
          Authenticator
        </div>
        <div style="display:flex;width:60px;"></div>
      </div>

      <!-- search field -->
      <div style="display:flex;padding:14px 20px 12px 20px;">
        <div style="
          display:flex;align-items:center;flex:1;height:36px;padding:0 13px;
          background:#141416;border:1px solid ${HAIRLINE};border-radius:9px;
        ">
          <div style="display:flex;font-size:15px;color:#6d6d73;">Search accounts</div>
        </div>
      </div>

      ${row({ issuer: "GitHub", account: "octocat", code: "418 240", progress: 3 })}
      ${row({ issuer: "Cloudflare", account: "ops@example.com", code: "902 517", progress: 2 })}
      ${row({ issuer: "Vercel", account: "team-production", code: "174 663", progress: 1, last: true })}
    </div>
  </div>
</div>
`;

// trim() matters: leading whitespace becomes a text node above the root element,
// which pushes the layout down and leaves a transparent strip across the top.
const png = await render(html.trim(), { width: 1200, height: 630, format: "png" });
await writeFile(output, png);
console.log(`wrote ${output} (${png.length} bytes)`);
