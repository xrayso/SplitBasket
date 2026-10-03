#!/usr/bin/env node
// Runs the receipt reader on the photos in functions/test-receipts and shows
// what it found, whether the items add up, and roughly what it cost.
//
//   node scripts/eval-receipts.js [--model gpt-6-luna] [--effort medium]
//                                 [--names] [photo ...]
//
// Needs OPENAI_API_KEY (env or functions/.secret.local) and Google
// Application Default Credentials for Cloud Vision.

const fs = require("fs");
const os = require("os");
const path = require("path");
const {execFileSync} = require("child_process");
const OpenAI = require("openai");
const vision = require("@google-cloud/vision");
const {foldDiscounts, readReceipt, tidyNames} =
    require("../receipt-reader");

// $ per 1M tokens (input, output). Web search: $10 per 1K calls.
const PRICES = {
  "gpt-6-luna": [0.10, 0.50],
  "gpt-5.4-nano": [0.20, 1.25],
  "gpt-5-mini": [0.25, 2.00],
  "gpt-5.4-mini": [0.75, 4.50],
};
const VISION_PER_IMAGE = 0.0015;
const SEARCH_PER_CALL = 0.01;

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args.splice(i, 2)[1] : fallback;
};
const model = flag("--model", "gpt-6-luna");
const effort = flag("--effort", "medium");
const withNames = args.includes("--names");
const photos = args.filter((a) => !a.startsWith("--"));

const root = path.join(__dirname, "..");
if (!process.env.OPENAI_API_KEY) {
  const secrets = path.join(root, ".secret.local");
  if (fs.existsSync(secrets)) {
    for (const line of fs.readFileSync(secrets, "utf8").split("\n")) {
      const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
    }
  }
}
process.env.GOOGLE_CLOUD_QUOTA_PROJECT ||= "splitbasketapp";

const dir = path.join(root, "test-receipts");
const files = photos.length ? photos : fs.readdirSync(dir)
    .filter((f) => /\.(jpe?g|png|heic|heif|webp)$/i.test(f))
    .map((f) => path.join(dir, f));

/**
 * Loads a photo, converting iPhone HEIC files to JPEG with macOS's sips.
 * @param {string} file
 * @return {Buffer}
 */
function loadPhoto(file) {
  if (!/\.hei[cf]$/i.test(file)) return fs.readFileSync(file);
  const out = path.join(os.tmpdir(), `${path.basename(file)}.jpg`);
  execFileSync("sips", ["-s", "format", "jpeg", file, "--out", out],
      {stdio: "ignore"});
  return fs.readFileSync(out);
}

const money = (n) => (n == null ? "—" : `$${n.toFixed(2)}`);

(async () => {
  const openai = new OpenAI();
  const ocr = new vision.ImageAnnotatorClient();
  const [inPrice, outPrice] = PRICES[model] || [0, 0];
  const resultsDir = path.join(dir, "results");
  fs.mkdirSync(resultsDir, {recursive: true});

  let passed = 0;
  let totalCost = 0;
  for (const file of files) {
    const name = path.basename(file);
    console.log(`\n=== ${name}  (${model}, effort ${effort})`);
    const started = Date.now();
    try {
      const {receipt, lines, check, usage} = await readReceipt(
          {openai, vision: ocr, model, effort}, loadPhoto(file));
      // As processReceipt does: discounts come off the item they're for.
      const items = receipt.readable ? foldDiscounts(receipt.items) : [];
      let names = null;
      if (withNames && items.length) {
        names = await tidyNames({openai, model}, {
          store: receipt.store || "grocery store",
          items: items.map((i) => ({
            text: i.receiptText,
            code: i.code,
          })),
        });
      }
      const seconds = ((Date.now() - started) / 1000).toFixed(1);

      const tokensIn = usage.input + (names?.usage.input || 0);
      const tokensOut = usage.output + (names?.usage.output || 0);
      const cost = VISION_PER_IMAGE + (tokensIn * inPrice +
        tokensOut * outPrice) / 1e6 +
        (names?.usage.searches || 0) * SEARCH_PER_CALL;
      totalCost += cost;

      if (!receipt.readable) {
        console.log(`✗ Not readable (${lines.length} OCR lines) — ${seconds}s`);
        continue;
      }
      if (check.ok) passed++;
      console.log(`Store: ${receipt.store || "?"} · ${lines.length} OCR ` +
        `lines · ${items.length} items · attempt(s): ` +
        `${usage.attempts} · ${seconds}s · ≈$${cost.toFixed(4)}` +
        (names ? ` · ${names.usage.searches} web search(es)` : ""));
      console.log(`${check.ok ? "✓" : "✗"} items ${money(check.itemsTotal)} ` +
        `vs subtotal ${money(check.expected)}` +
        (check.missedLines.length ?
          ` · unused priced lines: ${check.missedLines.join(", ")}` : ""));
      items.forEach((item, i) => {
        const shown = names ? names.items[i].name : item.description;
        console.log(`  ${String(i + 1).padStart(2)}. ` +
          `[L${item.lines.join(",L")}] ${item.receiptText} → ${shown}` +
          ` · ${item.qty} × ${money(item.total)}` +
          `${item.discount ? ` (${money(item.discount)} off)` : ""}` +
          `${item.taxable ? " · taxed" : ""}`);
      });
      console.log(`  subtotal ${money(receipt.subtotal)} · tax ` +
        `${money(receipt.tax)} · total ${money(receipt.total)}`);

      fs.writeFileSync(path.join(resultsDir, `${model}-${name}.json`),
          JSON.stringify({receipt, items, names, lines, check, usage}, null,
              2));
    } catch (err) {
      console.log(`✗ Failed: ${err.message}`);
    }
  }
  console.log(`\n${passed}/${files.length} receipts fully accounted for · ` +
    `total ≈$${totalCost.toFixed(3)}`);
})();
