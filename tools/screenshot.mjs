// HTML-Abbilder aus tools/lune/ui als PNG fotografieren (braucht Node + Playwright mit Chromium).
//   node tools/screenshot.mjs [.tools/out/ui]
import { createRequire } from "node:module";
import { readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
let playwright;
try {
	playwright = require("playwright");
} catch {
	console.log("Playwright fehlt – keine PNGs (npm i -D playwright && npx playwright install chromium).");
	process.exit(0);
}

const dir = resolve(process.argv[2] ?? ".tools/out/ui");
const pages = readdirSync(dir).filter((f) => f.endsWith(".html") && f !== "index.html");
const browser = await playwright.chromium.launch();
for (const file of pages) {
	const page = await browser.newPage({ viewport: { width: 1920, height: 1112 } });
	await page.goto(pathToFileURL(join(dir, file)).href, { waitUntil: "load", timeout: 15000 }).catch(() => {});
	await page.evaluate(() => Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 3000))]));
	const stage = await page.$("#stage");
	await stage.screenshot({ path: join(dir, file.replace(/\.html$/, ".png")) });
	await page.close();
}
await browser.close();
console.log(`✔ ${pages.length} PNGs in ${dir}`);
