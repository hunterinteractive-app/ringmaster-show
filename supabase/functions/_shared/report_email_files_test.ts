import { PDFDocument } from "npm:pdf-lib@1.17.1";
import { isEmptyLegPdf, prepareReportEmailFiles, reportAttachmentBase64 } from "./report_email_files.ts";

async function pdf(...pages: string[]) {
  const doc = await PDFDocument.create();
  for (const text of pages) doc.addPage().drawText(text);
  return await doc.save();
}
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}

Deno.test("attachment Base64 respects byte views and standard padding", () => {
  for (const text of ["", "f", "fo", "foo", "foob", "fooba", "foobar"]) {
    assert(reportAttachmentBase64(new TextEncoder().encode(text)) === btoa(text),
      "changed Base64 padding or payload");
  }
  const backing = new Uint8Array([99, 0, 128, 255, 42]);
  assert(reportAttachmentBase64(backing.subarray(1, 4)) === "AID/",
    "included bytes outside the attachment view");
});

Deno.test("large leg attachment encodes every byte without changing the input", () => {
  const backing = new Uint8Array(4 * 1024 * 1024 + 9);
  for (let i = 0; i < backing.length; i++) backing[i] = i % 251;
  const bytes = backing.subarray(3, backing.length - 2);
  const decoded = atob(reportAttachmentBase64(bytes));
  assert(decoded.length === bytes.length, "large attachment length changed");
  for (let i = 0; i < bytes.length; i++) {
    assert(decoded.charCodeAt(i) === (i + 3) % 251 && bytes[i] === (i + 3) % 251,
      "large attachment content changed");
  }
});

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
