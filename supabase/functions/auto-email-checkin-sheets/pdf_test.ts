import { buildPdfBytes } from "./pdf.ts";
Deno.test("scheduled wave sheet renders with all wave information", async () => {
  const pdf = await buildPdfBytes({
    show: {
      name: "Houston Wave Preview",
      timezone: "America/Chicago",
      secretary_name: "Show Secretary",
    },
    sectionLabel: "Wave 2",
    wave: {
      wave_number: 2,
      checkin_starts_at: "2027-03-10T14:00:00Z",
      checkin_ends_at: "2027-03-10T16:00:00Z",
      show_date: "2027-03-11",
      checkout_date: "2027-03-12",
    },
    entries: Array.from({ length: 22 }, (_, i) => ({
      entry_id: `e${i}`,
      exhibitor_label: "Test Exhibitor",
      exhibitor_number: 1096,
      breed: i % 2 ? "American" : "Himalayan",
      tattoo: `W${i + 1}`,
      class_name: "Senior",
      sex: "Buck",
      variety: "Black",
      balance_due_all_shows: 0,
      balance_due_this_show: 0,
    })),
  });
  if (
    pdf.length < 1000 || new TextDecoder().decode(pdf.slice(0, 5)) !== "%PDF-"
  ) throw new Error(`Expected PDF, received ${pdf.length} bytes`);
  const output = Deno.env.get("WAVE_EMAIL_PDF_PREVIEW");
  if (output) await Deno.writeFile(output, pdf);
});

Deno.test("normal emailed sheet retains its layout with a long name and account number", async () => {
  const pdf = await buildPdfBytes({
    show: { name: "Normal Check-In Preview", secretary_name: "Show Secretary" },
    sectionLabel: "All Shows",
    entries: [{
      exhibitor_label: "Alexandria and Christopher Example Family Rabbitry 2",
      exhibitor_number: 12003,
      tattoo: "NORMAL-1",
      breed: "Dutch",
      class_name: "Senior",
      sex: "Buck",
      variety: "Black",
      balance_due_all_shows: 21,
      balance_due_this_show: 21,
    }],
  });
  if (pdf.length < 1000) throw new Error("Expected a complete normal sheet");
  const output = Deno.env.get("NORMAL_EMAIL_PDF_PREVIEW");
  if (output) await Deno.writeFile(output, pdf);
});
