import { PDFDocument } from "npm:pdf-lib@1.17.1";
import { isEmptyLegPdf, prepareReportEmailFiles } from "./report_email_files.ts";

async function pdf(...pages: string[]) {
  const doc = await PDFDocument.create();
  for (const text of pages) doc.addPage().drawText(text);
  return await doc.save();
}
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}

Deno.test("detects only the exact single-page empty legs document", async () => {
  assert(await isEmptyLegPdf(await pdf("No leg certificates earned.")), "placeholder not detected");
  assert(!await isEmptyLegPdf(await pdf("Actual earned certificate")), "earned leg suppressed");
  assert(!await isEmptyLegPdf(await pdf("No leg certificates earned.", "Actual earned certificate")), "mixed document suppressed");
  assert(!await isEmptyLegPdf(await pdf("")), "unrecognized blank PDF suppressed");
});

Deno.test("mixed bundle retains exhibitor report and earned legs byte-for-byte", async () => {
  const empty = await pdf("No leg certificates earned.");
  const earned = await pdf("Actual earned certificate");
  const artifacts = [
    {id: "report", report_name: "exhibitor_report"},
    {id: "empty", report_name: "legs"},
    {id: "earned", report_name: "legs"},
  ];
  const {files, skippedArtifactIds} = await prepareReportEmailFiles(artifacts,
    async (artifact) => artifact.id === "earned" ? earned : empty);
  assert(files.map(f => f.artifact.id).join() === "report,earned", "wrong attachments/order");
  assert(skippedArtifactIds.join() === "empty", "wrong skipped IDs");
  assert(files[1].bytes === earned && earned.byteLength > 0, "PDF inspection altered attachment bytes");
});

Deno.test("legs-only empty bundle produces no files to send", async () => {
  const {files} = await prepareReportEmailFiles([{id: "empty", report_name: "legs"}],
    async () => await pdf("No leg certificates earned."));
  assert(files.length === 0, "empty legs attachment was retained");
});

Deno.test("PDF parse failures do not silently drop potentially earned certificates", async () => {
  let failed = false;
  try {
    await prepareReportEmailFiles([{id: "bad", report_name: "legs"}],
      async () => new TextEncoder().encode("not a PDF"));
  } catch { failed = true; }
  assert(failed, "corrupt PDF accepted");
});
