export interface EmailArtifact {
  id: string;
  report_name: string;
}

export async function isEmptyLegPdf(bytes: Uint8Array): Promise<boolean> {
  const { getDocumentProxy } = await import("npm:unpdf@1.8.1");
  // PDF.js can transfer its input buffer; preserve the bytes for attachments.
  const pdf = await getDocumentProxy(bytes.slice());
  try {
    // The empty-legs builder emits a single page with this exact message.
    if (pdf.numPages !== 1) return false;
    const page = await pdf.getPage(1);
    const content = await page.getTextContent();
    const text = content.items.map((item) => "str" in item ? item.str : "")
      .join(" ").replace(/\s+/g, " ").trim().toLowerCase().replace(/\.$/, "");
    return text === "no leg certificates earned";
  } finally {
    await pdf.loadingTask.destroy();
  }
}

export async function prepareReportEmailFiles<T extends EmailArtifact>(
  artifacts: T[],
  download: (artifact: T) => Promise<Uint8Array>,
) {
  const files: { artifact: T; bytes: Uint8Array }[] = [];
  const skippedArtifactIds: string[] = [];
  for (const artifact of artifacts) {
    const bytes = await download(artifact);
    if (artifact.report_name === "legs" && await isEmptyLegPdf(bytes)) {
      skippedArtifactIds.push(artifact.id);
    } else {
      files.push({ artifact, bytes });
    }
  }
  return { files, skippedArtifactIds };
}
