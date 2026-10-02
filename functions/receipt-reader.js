// Reads grocery receipts so nothing gets missed:
//   1. Google Cloud Vision reads every word on the photo (OCR).
//   2. The words are rebuilt into the receipt's printed lines.
//   3. An OpenAI model turns those lines (plus the photo) into items, citing
//      which lines each item came from.
//   4. The answer is checked: items must add up to the printed subtotal, and
//      every line with a price must be accounted for. If not, the model is
//      told exactly what's off and asked again.
//   5. Item names are tidied, searching the web for ones the model doesn't
//      recognize.

const sharp = require("sharp");

const CATEGORIES = [
  "produce", "meat_seafood", "dairy_eggs", "bakery", "frozen", "pantry",
  "snacks", "beverages", "household", "personal_care", "other",
];
const OTHER_LINE_KINDS = [
  "subtotal", "tax", "total", "payment", "change", "savings_summary",
  "points", "header", "other",
];

const round2 = (n) => Math.round(n * 100) / 100;
const sum = (list) => round2(list.reduce((s, n) => s + n, 0));

/**
 * Rotates a photo upright and makes the two sizes we need: a large one for
 * OCR and a smaller one for the model.
 * @param {Buffer} buffer The uploaded photo.
 * @return {Promise<{ocr: Buffer, model: Buffer}>} JPEGs.
 */
async function prepareImages(buffer) {
  const resized = (max, quality) => sharp(buffer)
      .rotate()
      .resize(max, max, {fit: "inside", withoutEnlargement: true})
      .jpeg({quality})
      .toBuffer();
  const [ocr, model] = await Promise.all([
    resized(4000, 90),
    resized(2048, 85),
  ]);
  return {ocr, model};
}

// ── 1-2. OCR, rebuilt into printed lines ───────────────────────────────────

/**
 * Groups OCR words into the receipt's printed lines. Vision reads a
 * two-column receipt as "all the names, then all the prices", so we rebuild
 * rows from word positions instead, correcting for a tilted photo.
 * @param {Array<{text: string, box: Array<{x: number, y: number}>}>} words
 * @return {Array<string>} The receipt's lines, top to bottom.
 */
function wordsToLines(words) {
  if (words.length === 0) return [];
  const pt = (v) => ({x: v?.x || 0, y: v?.y || 0});

  // Tilt: the median angle of the words' top edges.
  const angles = words
      .filter((w) => w.text.length >= 3)
      .map((w) => {
        const [a, b] = [pt(w.box[0]), pt(w.box[1])];
        return Math.atan2(b.y - a.y, b.x - a.x);
      })
      .sort((a, b) => a - b);
  const angle = angles.length ? angles[Math.floor(angles.length / 2)] : 0;
  const [cos, sin] = [Math.cos(-angle), Math.sin(-angle)];

  const placed = words.map((w) => {
    const corners = w.box.map(pt);
    const cx = corners.reduce((s, v) => s + v.x, 0) / corners.length;
    const cy = corners.reduce((s, v) => s + v.y, 0) / corners.length;
    const height = Math.hypot(corners[3].x - corners[0].x,
        corners[3].y - corners[0].y);
    const width = Math.hypot(corners[1].x - corners[0].x,
        corners[1].y - corners[0].y);
    return {
      text: w.text,
      x: cx * cos - cy * sin,
      y: cx * sin + cy * cos,
      height: Math.max(height, 1),
      charWidth: width / Math.max(w.text.length, 1),
    };
  });

  const heights = placed.map((w) => w.height).sort((a, b) => a - b);
  const lineHeight = heights[Math.floor(heights.length / 2)];

  const rows = [];
  for (const word of placed.sort((a, b) => a.y - b.y)) {
    const row = rows[rows.length - 1];
    if (row && Math.abs(word.y - row.y) < lineHeight * 0.55) {
      row.words.push(word);
      row.y += (word.y - row.y) / row.words.length;
    } else {
      rows.push({y: word.y, words: [word]});
    }
  }

  return rows.map((row) => {
    const sorted = row.words.sort((a, b) => a.x - b.x);
    let line = "";
    sorted.forEach((w, i) => {
      if (i > 0) {
        const prev = sorted[i - 1];
        const gap = (w.x - w.text.length * w.charWidth / 2) -
          (prev.x + prev.text.length * prev.charWidth / 2);
        line += gap > prev.charWidth * 2.5 ? "   " : " ";
      }
      line += w.text;
    });
    return line;
  });
}

/**
 * Runs Google Cloud Vision OCR on a photo.
 * @param {object} vision An ImageAnnotatorClient.
 * @param {Buffer} image JPEG.
 * @return {Promise<Array<string>>} The receipt's printed lines.
 */
async function ocrLines(vision, image) {
  const [result] = await vision.documentTextDetection({
    image: {content: image},
    imageContext: {languageHints: ["en", "fr"]},
  });
  const words = [];
  for (const page of result.fullTextAnnotation?.pages || []) {
    for (const block of page.blocks || []) {
      for (const paragraph of block.paragraphs || []) {
        for (const word of paragraph.words || []) {
          const text = (word.symbols || []).map((s) => s.text).join("");
          const box = word.boundingBox?.vertices || [];
          if (text && box.length === 4) words.push({text, box});
        }
      }
    }
  }
  return wordsToLines(words);
}

// Lines that show a price, e.g. "12.99", "-3.00", "4,99 H".
const PRICE = /(^|[^\d.,/])-?\$?\d{1,4}[.,]\d{2}(?![\d/])/;

/**
 * Line numbers (1-based) that contain a price.
 * @param {Array<string>} lines
 * @return {Array<number>}
 */
function priceLines(lines) {
  return lines
      .map((line, i) => (PRICE.test(line) ? i + 1 : 0))
      .filter((n) => n > 0);
}

// ── 3-4. Items, checked against the receipt ───────────────────────────────

const RECEIPT_SCHEMA = {
  type: "object",
  properties: {
    readable: {type: "boolean"},
    store: {type: "string"},
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          lines: {type: "array", items: {type: "integer"}},
          receiptText: {type: "string"},
          code: {type: "string"},
          description: {type: "string"},
          qty: {type: "integer"},
          total: {type: "number"},
          taxable: {type: "boolean"},
          category: {type: "string", enum: CATEGORIES},
        },
        required: ["lines", "receiptText", "code", "description", "qty",
          "total", "taxable", "category"],
        additionalProperties: false,
      },
    },
    otherLines: {
      type: "array",
      items: {
        type: "object",
        properties: {
          line: {type: "integer"},
          kind: {type: "string", enum: OTHER_LINE_KINDS},
        },
        required: ["line", "kind"],
        additionalProperties: false,
      },
    },
    subtotal: {type: ["number", "null"]},
    tax: {type: ["number", "null"]},
    total: {type: ["number", "null"]},
  },
  required: ["readable", "store", "items", "otherLines", "subtotal", "tax",
    "total"],
  additionalProperties: false,
};

const EXTRACT_INSTRUCTIONS = `You turn grocery receipts into a list of \
items so friends can split the bill. Missing an item ruins the split, so \
account for every line that has a price.

You get the receipt photo and its text, read by OCR and numbered by line \
(L1, L2, ...). Trust the OCR for exact characters and use the photo to \
check layout, pairing and anything the OCR garbled.

For each purchased item:
- lines: every line number the item uses (its name line, a separate price \
or weight line, and any discount/coupon lines applied to it).
- receiptText: the item's name as printed.
- code: the item or PLU number if one is printed, otherwise "".
- description: a readable name; expand obvious abbreviations ("ORG BNNA" -> \
"Organic Bananas") but don't invent brands or sizes.
- qty: units bought (1 for items sold by weight).
- total: the line's price in dollars as printed, after any discounts, \
coupons or instant savings applied to it. Never add sales tax to an item; \
tax is reported separately. Deposits and environmental fees are their own \
items.
- taxable: true only when the receipt marks the item as taxed (an H, HST, \
GST, T, or tax-code letter by the price).
- category: the closest fit.

Every other line with a price (subtotal, taxes, total, payment, change, \
savings summaries, points) goes in otherLines with its line number and kind.

subtotal: the amount before tax (some stores call it "Net Sales"; a "SUB \
TOTAL" printed after the tax line is really the total). tax: all sales \
taxes combined. total: the amount paid. Use null for any that aren't \
printed. store: the store name, or "".

If the photo isn't a receipt or is too blurry to read, set readable to false \
and return no items.`;

/**
 * Checks a parsed receipt against itself.
 * @param {object} receipt The model's answer.
 * @param {Array<string>} lines OCR lines.
 * @return {object} itemsTotal, expected, missedLines and ok.
 */
function checkReceipt(receipt, lines) {
  const {subtotal, tax, total} = receipt;
  const itemsTotal = sum(receipt.items.map((i) => i.total));
  // What the items should add up to. The total paid minus tax is the most
  // reliable figure: stores label "subtotal" inconsistently (Farm Boy prints
  // "SUB TOTAL" for the amount after tax).
  let expected = null;
  if (total != null && tax != null) expected = round2(total - tax);
  else if (subtotal != null) expected = subtotal;
  else if (total != null) expected = total;
  const sumOk = expected == null || Math.abs(itemsTotal - expected) <= 0.02;
  // Catches a "subtotal" that already includes tax.
  const totalsOk = subtotal == null || tax == null || total == null ||
    Math.abs(subtotal + tax - total) <= 0.02;

  const used = new Set([
    ...receipt.items.flatMap((i) => i.lines),
    ...receipt.otherLines.map((o) => o.line),
  ]);
  const missedLines = priceLines(lines).filter((n) => !used.has(n));

  // Tax charged, but nothing marked as taxed: the markers were missed.
  const taxedTotal = sum(receipt.items.filter((i) => i.taxable)
      .map((i) => i.total));
  const untaxedButTaxCharged = (receipt.tax || 0) > 0 && taxedTotal === 0;
  return {
    itemsTotal,
    expected,
    missedLines,
    untaxedButTaxCharged,
    // Tax as a share of the taxed items, e.g. 0.13 for Ontario HST.
    taxRate: taxedTotal > 0 ? round2((receipt.tax || 0) / taxedTotal * 100) /
      100 : null,
    totalsOk,
    ok: sumOk && totalsOk && missedLines.length === 0 &&
      !untaxedButTaxCharged,
  };
}

/**
 * Reads a receipt photo into items, retrying with feedback until the items
 * add up and every priced line is accounted for.
 * @param {object} deps
 * @param {object} deps.openai OpenAI client.
 * @param {object} deps.vision Google Cloud Vision ImageAnnotatorClient.
 * @param {string} deps.model OpenAI model ID.
 * @param {string} [deps.effort] Reasoning effort.
 * @param {Buffer} photo The uploaded photo.
 * @return {Promise<object>} The receipt, its OCR lines, check and usage.
 */
async function readReceipt({openai, vision, model, effort = "medium"}, photo) {
  const images = await prepareImages(photo);
  const lines = await ocrLines(vision, images.ocr);
  const numbered = lines.map((line, i) => `L${i + 1}: ${line}`).join("\n");

  const input = [{
    role: "user",
    content: [
      {
        type: "input_image",
        image_url: `data:image/jpeg;base64,${images.model.toString("base64")}`,
        detail: "original",
      },
      {type: "input_text", text: `OCR text:\n${numbered}`},
    ],
  }];

  const usage = {input: 0, output: 0, attempts: 0};
  let receipt;
  let check;
  for (let attempt = 1; attempt <= 3; attempt++) {
    const response = await openai.responses.create({
      model,
      instructions: EXTRACT_INSTRUCTIONS,
      input,
      reasoning: {effort},
      store: false,
      text: {
        format: {
          type: "json_schema",
          name: "receipt",
          schema: RECEIPT_SCHEMA,
          strict: true,
        },
      },
    });
    usage.attempts = attempt;
    usage.input += response.usage?.input_tokens || 0;
    usage.output += response.usage?.output_tokens || 0;

    receipt = JSON.parse(response.output_text);
    if (!receipt.readable) break;
    check = checkReceipt(receipt, lines);
    if (check.ok) break;

    // Tell the model exactly what doesn't add up and ask again.
    const problems = [];
    if (check.expected != null &&
        Math.abs(check.itemsTotal - check.expected) > 0.02) {
      problems.push(`Your items add up to $${check.itemsTotal.toFixed(2)}, ` +
        `but the receipt's subtotal is $${check.expected.toFixed(2)} ` +
        `(off by $${round2(check.expected - check.itemsTotal).toFixed(2)}).`);
    }
    if (check.missedLines.length) {
      problems.push("These lines have a price but aren't in any item or " +
        "otherLines:\n" +
        check.missedLines.map((n) => `L${n}: ${lines[n - 1]}`).join("\n"));
    }
    if (!check.totalsOk) {
      problems.push(`subtotal ($${receipt.subtotal.toFixed(2)}) plus tax ` +
        `($${receipt.tax.toFixed(2)}) should equal the total ` +
        `($${receipt.total.toFixed(2)}). subtotal is the amount before tax.`);
    }
    if (check.untaxedButTaxCharged) {
      problems.push(`The receipt charges $${receipt.tax.toFixed(2)} tax, ` +
        "but no item is marked taxable. Look again for tax markers " +
        "(H, HST, *, a tax-code letter) beside the prices; OCR may have " +
        "misread them, e.g. \"*HST\" as \"-HST\".");
    }
    input.push(
        {role: "assistant", content: response.output_text},
        {
          role: "user",
          content: `That doesn't check out:\n${problems.join("\n")}\n\n` +
            "Re-read the receipt and send the complete, corrected answer.",
        },
    );
  }

  return {receipt, lines, check, usage};
}

// ── 5. Readable names, with web search ────────────────────────────────────

const NAMES_SCHEMA = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: {type: "string"},
          category: {type: "string", enum: CATEGORIES},
        },
        required: ["name", "category"],
        additionalProperties: false,
      },
    },
  },
  required: ["items"],
  additionalProperties: false,
};

/**
 * Turns receipt abbreviations into real product names, searching the web
 * for items the model doesn't recognize.
 * @param {object} deps
 * @param {object} deps.openai OpenAI client.
 * @param {string} deps.model OpenAI model ID.
 * @param {object} request
 * @param {string} request.store e.g. "Costco".
 * @param {Array<{text: string, code: string}>} request.items As printed.
 * @return {Promise<{items: Array<object>, usage: object}>}
 */
async function tidyNames({openai, model}, {store, items}) {
  const list = items
      .map((item, i) => `${i + 1}. ${item.text}` +
        (item.code ? ` (item #${item.code})` : ""))
      .join("\n");

  const response = await openai.responses.create({
    model,
    reasoning: {effort: "low"},
    store: false,
    tools: [{
      type: "web_search",
      search_context_size: "low",
      user_location: {type: "approximate", country: "CA"},
    }],
    max_tool_calls: 10,
    instructions: `You turn grocery receipt text into the products people \
actually bought. Names on receipts are abbreviated by the store's system, \
and some include the store's item number.

For each item, in the same order, give the product name a shopper would \
recognize (brand and product, plus size if you know it, e.g. "KS ORG EGGS" -> \
"Kirkland Signature Organic Eggs, 24 ct") and its category.

Search the web for every item you can't confidently identify, e.g. the \
store name plus the receipt text, or the store's item number. Don't search \
for items you already know. If you still can't tell what it is, keep the \
receipt text as the name. Never invent a product.

Return exactly ${items.length} items.`,
    input: `Items from a ${store} receipt in Canada:\n${list}`,
    text: {
      format: {
        type: "json_schema",
        name: "item_names",
        schema: NAMES_SCHEMA,
        strict: true,
      },
    },
  });

  const result = JSON.parse(response.output_text);
  if (result.items.length !== items.length) {
    throw new Error(`Expected ${items.length} names, ` +
      `got ${result.items.length}`);
  }
  const searches = (response.output || [])
      .filter((o) => o.type === "web_search_call").length;
  return {
    items: result.items,
    usage: {
      input: response.usage?.input_tokens || 0,
      output: response.usage?.output_tokens || 0,
      searches,
    },
  };
}

module.exports = {
  CATEGORIES,
  prepareImages,
  wordsToLines,
  ocrLines,
  priceLines,
  checkReceipt,
  readReceipt,
  tidyNames,
};
