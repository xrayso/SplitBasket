const test = require("node:test");
const assert = require("node:assert/strict");
const {
  wordsToLines, priceLines, checkReceipt, foldDiscounts,
} = require("../receipt-reader");

/**
 * Builds an OCR word box, optionally tilted around the origin.
 * @param {string} text
 * @param {number} x Left edge.
 * @param {number} y Top edge.
 * @param {number} degrees Tilt.
 * @return {{text: string, box: Array<{x: number, y: number}>}}
 */
function word(text, x, y, degrees = 0) {
  const w = text.length * 10;
  const h = 20;
  const a = degrees * Math.PI / 180;
  const rot = ({x: px, y: py}) => ({
    x: px * Math.cos(a) - py * Math.sin(a),
    y: px * Math.sin(a) + py * Math.cos(a),
  });
  return {
    text,
    box: [{x, y}, {x: x + w, y}, {x: x + w, y: y + h}, {x, y: y + h}]
        .map(rot),
  };
}

test("rebuilds two-column rows, even from a tilted photo", () => {
  for (const tilt of [0, 6, -6]) {
    const words = [
      word("4.99", 400, 140, tilt),
      word("BANANAS", 20, 100, tilt),
      word("MILK", 20, 140, tilt),
      word("1.99", 400, 100, tilt),
      word("H", 450, 140, tilt),
      word("2%", 70, 140, tilt),
    ];
    assert.deepEqual(wordsToLines(words), [
      "BANANAS   1.99",
      "MILK 2%   4.99 H",
    ], `tilt ${tilt}`);
  }
});

test("finds lines with prices, not dates, times or phone numbers", () => {
  const lines = [
    "FARM BOY #12",
    "2026/09/14 14:13",
    "613-555-1234",
    "ORG BANANAS   2.49",
    "1.234 kg @ $3.99/kg   4.92",
    "COUPON   -1.00",
    "HST 13%   0.65",
    "TOTAL   $8.06",
    "Thank you!",
  ];
  assert.deepEqual(priceLines(lines), [4, 5, 6, 7, 8]);
});

test("passes only when items add up and every priced line is used", () => {
  const lines = ["MILK   4.99", "EGGS   6.49", "SUBTOTAL   11.48",
    "HST   0.00", "TOTAL   11.48"];
  const item = (l, total) => ({lines: [l], total});
  const good = {
    items: [item(1, 4.99), item(2, 6.49)],
    otherLines: [{line: 3}, {line: 4}, {line: 5}],
    subtotal: 11.48, tax: 0, total: 11.48,
  };
  assert.equal(checkReceipt(good, lines).ok, true);

  const missedEggs = {...good, items: [item(1, 4.99)]};
  const check = checkReceipt(missedEggs, lines);
  assert.equal(check.ok, false);
  assert.deepEqual(check.missedLines, [2]);
  assert.equal(check.itemsTotal, 4.99);
  assert.equal(check.expected, 11.48);

  // No subtotal printed: fall back to total minus tax.
  const taxedEggs = [item(1, 4.99), {...item(2, 6.49), taxable: true}];
  const noSubtotal = {...good, items: taxedEggs, subtotal: null,
    total: 12.32, tax: 0.84};
  assert.equal(checkReceipt(noSubtotal, lines).ok, true);
  assert.ok(Math.abs(checkReceipt(noSubtotal, lines).taxRate - 0.13) < 0.005);

  // A "subtotal" that already includes tax (Farm Boy's "SUB TOTAL"), with
  // tax folded into the taxed items so they seem to add up.
  const taxInItems = {...noSubtotal,
    items: [item(1, 4.99), {...item(2, 7.33), taxable: true}],
    subtotal: 12.32};
  const folded = checkReceipt(taxInItems, lines);
  assert.equal(folded.totalsOk, false);
  assert.equal(folded.expected, 11.48);
  assert.equal(folded.ok, false);

  // Tax charged but nothing marked taxed: the markers were missed.
  const noMarkers = {...noSubtotal, items: good.items};
  assert.equal(checkReceipt(noMarkers, lines).untaxedButTaxCharged, true);
  assert.equal(checkReceipt(noMarkers, lines).ok, false);
});

const scanned = (lines, receiptText, code, total, extra = {}) => ({
  lines, receiptText, code, description: receiptText, qty: 1, total,
  discount: 0, taxable: false, category: "other", ...extra,
});

test("folds discounts left as items into the item they're for", () => {
  const items = foldDiscounts([
    scanned([10], "LUBRIDERM", "1234567", 14.99, {taxable: true}),
    scanned([11], "ORG SPINACH", "7654321", 4.99),
    scanned([12], "TPD/1234567", "345678", -4),
    scanned([13], "ORAL-B BRUSH", "1111111", 16.99, {taxable: true}),
    scanned([14], "/ 1111111", "", -4),
    scanned([15], "KS EGGS", "", 9.49),
    scanned([16], "INSTANT SAVINGS", "", -1.5),
  ]);
  assert.deepEqual(items.map((i) => [i.receiptText, i.total, i.discount]), [
    ["LUBRIDERM", 10.99, 4],
    ["ORG SPINACH", 4.99, 0],
    ["ORAL-B BRUSH", 12.99, 4],
    ["KS EGGS", 7.99, 1.5],
  ]);
  assert.deepEqual(items[0].lines, [10, 12]);
  assert.equal(items[0].taxable, true);
});

test("keeps order-wide discounts and returns as their own lines", () => {
  const items = foldDiscounts([
    scanned([3], "EMPLOYEE DISCOUNT 10%", "", -5),
    scanned([5], "MILK", "", 6.49, {discount: 1}),
    scanned([6], "BOTTLE RETURN", "", -0.1),
  ]);
  assert.deepEqual(items.map((i) => [i.receiptText, i.total, i.discount]), [
    ["EMPLOYEE DISCOUNT 10%", -5, 0],
    ["MILK", 6.49, 1],
    ["BOTTLE RETURN", -0.1, 0],
  ]);
});
