// @deno-types="npm:@types/pdfkit@0.13.8"
import PDFDocument from "npm:pdfkit@0.15.0";
import { Buffer } from "node:buffer";
import { waveSheetNote } from "./helpers.ts";

export function safe(row: Record<string, unknown>, key: string): string {
  return (row[key] ?? "").toString().trim();
}

export function money(value: unknown): string {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return "$—";
  return `$${n.toFixed(2)}`;
}

export function exhibitorName(entry: Record<string, unknown>): string {
  return safe(entry, "exhibitor_label") || "(Unknown Exhibitor)";
}

export function groupVarietyLabel(row: Record<string, unknown>): string {
  const groupName = safe(row, "group_name");
  const variety = safe(row, "variety");

  if (groupName && variety) return `${groupName} / ${variety}`;
  if (groupName) return groupName;
  return variety;
}

export function displayAgeClassOnly(raw: string): string {
  const lower = raw.toLowerCase();
  if (lower.includes("senior")) return "Senior";
  if (lower.includes("intermediate")) return "Intermediate";
  if (lower.includes("junior")) return "Junior";
  return raw;
}

export function drawText(
  doc: { text(text: string, options: object): unknown },
  text: string,
  options = {},
) {
  doc.text(text || "", options);
}

export function buildPdfBytes({
  show,
  sectionLabel,
  entries,
  wave,
}: {
  show: Record<string, unknown>;
  sectionLabel: string;
  entries: Record<string, unknown>[];
  wave?: Record<string, unknown>;
}): Promise<Uint8Array> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "LETTER",
      margin: 28,
      bufferPages: true,
    });

    const chunks: Uint8Array[] = [];

    doc.on("data", (chunk: Uint8Array) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    const first = entries[0] ?? {};
    const name = exhibitorName(first);
    const exhibitorNumber = safe(first, "exhibitor_number");
    const exhibitorLabel = exhibitorNumber
      ? `${name}    Exhibitor #: ${exhibitorNumber}`
      : name;
    const allShows = money(first["balance_due_all_shows"]);
    const thisShow = money(first["balance_due_this_show"]);

    doc.fontSize(14).font("Helvetica-Bold").text(
      safe(show, "name") || "RingMaster Show",
      { align: "center" },
    );

    doc.moveDown(0.2);
    doc.fontSize(11).font("Helvetica").text(sectionLabel, { align: "center" });
    doc.moveDown(0.2);
    doc.fontSize(12).font("Helvetica-Bold").text("Exhibitor Check-In Sheet", {
      align: "center",
    });

    doc.moveDown();

    doc.fontSize(11).font("Helvetica-Bold").text("Balance Due", {
      align: "right",
      underline: true,
    });
    doc.fontSize(10).text(`All Shows: ${allShows}`, { align: "right" });
    doc.text(`This Show: ${thisShow}`, { align: "right" });

    doc.moveDown();

    // Keep the normal emailed sheet's name/count bar. Allow a long name and
    // exhibitor number to wrap without clipping or overlapping the entry count.
    const exhibitorY = doc.y;
    const barWidth = wave ? 556 : 540;
    doc.fontSize(11).font("Helvetica-Bold");
    const barHeight = Math.max(
      24,
      doc.heightOfString(exhibitorLabel, { width: 330 }) + 12,
    );
    doc.rect(28, exhibitorY, barWidth, barHeight)
      .fillAndStroke("#e5e5e5", "#000000");
    doc.fillColor("#000000");
    doc.text(exhibitorLabel, 38, exhibitorY + 6, { width: 330 });
    doc.text(`Number Entered  ${entries.length}`, 380, exhibitorY + 6, {
      width: barWidth - 362,
    });
    doc.x = 28;
    doc.y = exhibitorY + barHeight + 8;

    const addressLines = [
      safe(first, "address_line1"),
      safe(first, "address_line2"),
      `${safe(first, "city")}${
        safe(first, "city") && safe(first, "state") ? ", " : ""
      }${safe(first, "state")} ${safe(first, "zip")}`.trim(),
      safe(first, "phone") ? `Phone: ${safe(first, "phone")}` : "",
      safe(first, "email") ? `Email: ${safe(first, "email")}` : "",
    ].filter(Boolean);

    doc.fontSize(9).font("Helvetica");
    for (const line of addressLines) drawText(doc, line);

    doc.moveDown();

    doc.font("Helvetica-Bold").text("Show Secretary:");
    doc.font("Helvetica");
    drawText(doc, safe(show, "secretary_name") || "(Not set)");
    drawText(doc, safe(show, "secretary_phone"));
    drawText(doc, safe(show, "secretary_email"));

    doc.moveDown();

    doc.fontSize(9);
    doc.text(
      "» If there are any problems with your entry as shown below please reach out to the show secretary.",
    );
    doc.text(
      "» No corrections or changes can be made at the judging table or after the show starts.",
    );
    doc.text(
      "» A ? in any column indicates the correct information is not known.",
    );

    if (wave) {
      doc.moveDown(0.5);
      const zone = safe(show, "timezone") || "America/Indiana/Indianapolis";
      const format = (v: unknown) =>
        new Date(String(v)).toLocaleString("en-US", {
          timeZone: zone,
          dateStyle: "medium",
          timeStyle: "short",
        });
      doc.text(
        `Check-in: ${format(wave.checkin_starts_at)} to ${
          format(wave.checkin_ends_at)
        } (${zone})`,
      );
      doc.text(
        `Show date: ${wave.show_date} • Check-out: ${wave.checkout_date}`,
      );
      doc.moveDown(0.4);
      doc.text(waveSheetNote);
    }
    doc.moveDown();

    const startX = 28;
    let y = doc.y;
    const cols = wave
      ? [
        { label: "Section", width: 65 },
        { label: "Ear #", width: 50 },
        { label: "Coop #", width: 45 },
        { label: "Breed", width: 100 },
        { label: "Group / Variety", width: 135 },
        { label: "Class", width: 71 },
        { label: "Sex", width: 55 },
        { label: "Fur", width: 35 },
      ]
      : [
        { label: "Ear #", width: 60 },
        { label: "Coop #", width: 55 },
        { label: "Breed", width: 110 },
        { label: "Group / Variety", width: 150 },
        { label: "Class", width: 70 },
        { label: "Sex", width: 45 },
        { label: "Fur", width: 35 },
      ];

    function row(values: string[], header = false) {
      let x = startX;
      const rowHeight = header ? 22 : 26;

      if (y + rowHeight > 740) {
        doc.addPage();
        y = 28;
        if (wave && !header) row(cols.map((c) => c.label), true);
      }

      for (let i = 0; i < cols.length; i++) {
        doc
          .rect(x, y, cols[i].width, rowHeight)
          .fillAndStroke(header ? "#e5e5e5" : "#ffffff", "#000000");

        doc.fillColor("#000000");
        doc.fontSize(8).font(header ? "Helvetica-Bold" : "Helvetica");
        doc.text(values[i] ?? "", x + 3, y + 6, {
          width: cols[i].width - 6,
          height: rowHeight - 6,
        });

        x += cols[i].width;
      }

      y += rowHeight;
    }

    row(cols.map((c) => c.label), true);

    for (const e of entries) {
      const furMark = safe(e, "is_fur").toLowerCase() === "true" ||
          safe(e, "class_name").toLowerCase().includes("fur")
        ? "X"
        : "";

      row([
        ...(wave
          ? [
            safe(e, "section_display_name") ||
            [safe(e, "section_kind"), safe(e, "section_letter")].filter(Boolean)
              .join(" "),
          ]
          : []),
        safe(e, "animal_name") || safe(e, "tattoo"),
        safe(e, "coop_number"),
        safe(e, "breed"),
        groupVarietyLabel(e),
        displayAgeClassOnly(safe(e, "class_name")),
        safe(e, "sex"),
        furMark,
      ]);
    }

    if (wave) {
      const pages = doc.bufferedPageRange();
      for (let i = pages.start; i < pages.start + pages.count; i++) {
        doc.switchToPage(i);
        doc.fontSize(9).font("Helvetica").text(
          `RingMaster Show • ${sectionLabel} • Page ${i + 1} of ${pages.count}`,
          28,
          750,
          { lineBreak: false },
        );
      }
    } else {
      doc.moveDown();
      doc.fontSize(9).text("RingMaster Show", 28, 760);
    }
    doc.end();
  });
}
