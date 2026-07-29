// Renders site/og.png, the Open Graph card for the landing page.
//
//   cd site/og && npm install && npm run build
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

const html = `
<div style="
  width:1200px;height:630px;display:flex;align-items:center;
  background:linear-gradient(135deg,#ffffff 0%,#f6f7fb 52%,#e6edfd 100%);
  font-family:Geist;
">
  <!-- Brand stripe, echoing the accent colour used on the site's buttons. -->
  <div style="display:flex;width:14px;height:630px;background:#0071e3;"></div>

  <div style="display:flex;flex-direction:column;justify-content:center;flex:1;padding:0 0 0 78px;">
    <div style="display:flex;font-size:88px;font-weight:700;color:#1d1d1f;letter-spacing:-3px;line-height:1;">
      Authenticator
    </div>
    <div style="display:flex;font-size:36px;color:#474747;margin-top:26px;letter-spacing:-0.6px;">
      Two-factor codes, native on your Mac.
    </div>
    <!-- align-items:center so the separator dots sit on the text's optical centre
         rather than dropping to each flex item's own baseline. -->
    <div style="display:flex;align-items:center;margin-top:44px;">
      <div style="display:flex;font-size:23px;color:#0071e3;font-weight:600;letter-spacing:-0.2px;">
        Touch ID locked
      </div>
      <div style="display:flex;font-size:23px;color:#a6a6ab;padding:0 12px;">·</div>
      <div style="display:flex;font-size:23px;color:#0071e3;font-weight:600;letter-spacing:-0.2px;">
        Encrypted on disk
      </div>
      <div style="display:flex;font-size:23px;color:#a6a6ab;padding:0 12px;">·</div>
      <div style="display:flex;font-size:23px;color:#0071e3;font-weight:600;letter-spacing:-0.2px;">
        Fully offline
      </div>
    </div>
    <div style="display:flex;font-size:21px;color:#8a8a8e;margin-top:52px;letter-spacing:-0.2px;">
      macOS 15 or later · Free and open source
    </div>
  </div>

  <div style="display:flex;align-items:center;justify-content:center;width:470px;height:630px;">
    <img src="${icon}" style="width:318px;height:318px;" />
  </div>
</div>
`;

const png = await render(html, { width: 1200, height: 630, format: "png" });
await writeFile(output, png);
console.log(`wrote ${output} (${png.length} bytes)`);
