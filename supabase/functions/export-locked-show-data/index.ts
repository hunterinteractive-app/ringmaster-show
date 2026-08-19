// supabase/functions/export-locked-show-data/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import JSZip from "https://esm.sh/jszip@3.10.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function safeFileName(value: string) {
  return (value || "file")
    .replace(/[^A-Za-z0-9_\-. ]+/g, "_")
    .replace(/\s+/g, " ")
    .replace(/_+/g, "_")
    .replace(/^[_\s.]+|[_\s.]+$/g, "");
}

function jsonFile(zip: JSZip, path: string, data: unknown) {
  zip.file(path, JSON.stringify(data ?? [], null, 2));
}

const pageSize = 1000;

async function selectAllByEq(
  supabase: ReturnType<typeof createClient>,
  table: string,
  column: string,
  value: string,
) {
  const rows: unknown[] = [];
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase
      .from(table)
      .select("*")
      .eq(column, value)
      .range(offset, offset + pageSize - 1);
    if (error) throw error;
    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}

async function selectAllByIn(
  supabase: ReturnType<typeof createClient>,
  table: string,
  column: string,
  values: string[],
) {
  const rows: unknown[] = [];
  // Smaller IN groups keep request URLs below common proxy limits.
  for (let index = 0; index < values.length; index += 100) {
    const group = values.slice(index, index + 100);
    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await supabase
        .from(table)
        .select("*")
        .in(column, group)
        .range(offset, offset + pageSize - 1);
      if (error) throw error;
      const page = data ?? [];
      rows.push(...page);
      if (page.length < pageSize) break;
    }
  }
  return rows;
}

async function exportTable(
  zip: JSZip,
  supabase: ReturnType<typeof createClient>,
  path: string,
  table: string,
  column: string,
  value: string,
) {
  try {
    const data = await selectAllByEq(supabase, table, column, value);
    jsonFile(zip, path, data);
    return { table, path, count: data.length };
  } catch (e) {
    zip.file(
      `Errors/${table}.txt`,
      `Failed to export ${table}: ${e?.message ?? e}`,
    );
    return { table, path, count: 0, error: e?.message ?? String(e) };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const show_id = body.show_id ?? body.p_show_id;

    if (!show_id) {
      return new Response(JSON.stringify({ error: "Missing show_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authorization = req.headers.get("Authorization") ?? "";
    if (!authorization.toLowerCase().startsWith("bearer ")) {
      return new Response(JSON.stringify({ error: "Authentication required." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "Authentication required." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let accessCheck = await userClient.rpc("user_can_manage_show_settings", {
      p_show_id: show_id,
      p_user_id: userData.user.id,
    });
    if (accessCheck.error?.code === "PGRST202") {
      accessCheck = await userClient.rpc("user_can_manage_show_settings", {
        p_show_id: show_id,
      });
    }
    if (accessCheck.error || accessCheck.data !== true) {
      return new Response(JSON.stringify({ error: "You do not have permission to export this show." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const zip = new JSZip();

    zip.folder("Reports");
    zip.folder("Data Backup");
    zip.folder("Data Backup/settings");
    zip.folder("Data Backup/data");
    zip.folder("Data Backup/results");
    zip.folder("Data Backup/reports");
    zip.folder("Errors");

    const manifest: Record<string, unknown> = {
      export_type: "locked_show_export",
      export_version: 2,
      show_id,
      exported_at: new Date().toISOString(),
      files: [],
      report_files: [],
    };

    const files = manifest.files as unknown[];
    const reportFiles = manifest.report_files as unknown[];

    // ----------------------------
    // Show
    // ----------------------------
    const { data: show, error: showError } = await supabase
      .from("shows")
      .select("*")
      .eq("id", show_id)
      .single();

    if (showError) throw showError;

    if (show?.is_locked !== true && !show?.finalized_at) {
      return new Response(
        JSON.stringify({
          error: "Show must be locked or finalized before export.",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const showName = safeFileName(show?.name ?? "show");

    jsonFile(zip, "Data Backup/show.json", show);
    files.push({ table: "shows", path: "Data Backup/show.json", count: 1 });

    // ----------------------------
    // Direct show_id tables
    // ----------------------------
    const directTables = [
      ["Data Backup/settings/show_sections.json", "show_sections"],
      ["Data Backup/settings/show_rule_settings.json", "show_rule_settings"],
      ["Data Backup/settings/show_fee_settings.json", "show_fee_settings"],
      ["Data Backup/settings/show_payment_settings.json", "show_payment_settings"],
      ["Data Backup/settings/show_sanctions.json", "show_sanctions"],
      ["Data Backup/data/entries.json", "entries"],
      ["Data Backup/data/entry_awards.json", "entry_awards"],
      ["Data Backup/data/judge_assignments.json", "judge_assignments"],
      ["Data Backup/reports/show_finalize_runs.json", "show_finalize_runs"],
    ];

    for (const [path, table] of directTables) {
      const result = await exportTable(
        zip,
        supabase,
        path,
        table,
        "show_id",
        show_id,
      );
      files.push(result);
    }

    // ----------------------------
    // Current report records
    //
    // Report files intentionally remain in Storage.  Downloading and
    // recompressing hundreds of PDFs in one Edge Function request exceeds the
    // worker compute limit and makes a locked-data backup unreliable. Their
    // metadata is present in show_report_artifacts.json, and the PDFs continue
    // to be available individually in Reports & Distribution.
    // ----------------------------
    try {
      const { data: artifacts, error: artifactsError } = await supabase
        .from("show_report_artifacts")
        .select("*")
        .eq("show_id", show_id)
        .eq("is_current", true)
        .eq("artifact_status", "generated")
        .order("report_name", { ascending: true })
        .order("file_name", { ascending: true });

      if (artifactsError) throw artifactsError;

      const currentReports = (artifacts ?? []).map((artifact) => ({
        id: artifact.id,
        report_name: artifact.report_name,
        file_name: artifact.file_name,
        artifact_status: artifact.artifact_status,
        generated_at: artifact.generated_at,
        storage_bucket: artifact.storage_bucket,
        storage_path: artifact.storage_path,
      }));
      jsonFile(zip, "Reports/latest_report_index.json", currentReports);
      zip.file(
        "Reports/README.txt",
        "This backup includes only the latest generated version of each report.\n" +
          "Historical report artifacts are intentionally excluded.\n" +
          "PDF report files remain available through Reports & Distribution.\n" +
          "They are not duplicated here so large locked-show exports remain reliable.\n",
      );
      reportFiles.push(...currentReports);
    } catch (e) {
      zip.file(
        "Errors/report_pdfs.txt",
        `Failed to export PDF reports: ${e?.message ?? e}`,
      );
    }

    // ----------------------------
    // Load entries for related data
    // ----------------------------
    let entries: unknown[] = [];
    try {
      entries = await selectAllByEq(supabase, "entries", "show_id", show_id);
    } catch (entriesError) {
      zip.file(
        "Errors/entries_related.txt",
        `Failed to load entries for related data: ${entriesError?.message ?? entriesError}`,
      );
    }

    const entryRows = entries;

    const entryIds = [
      ...new Set(
        entryRows
          .map((e) => e.id)
          .filter((x) => x !== null && x !== undefined && `${x}`.trim() !== "")
          .map((x) => `${x}`),
      ),
    ];

    const exhibitorIds = [
      ...new Set(
        entryRows
          .map((e) => e.exhibitor_id)
          .filter((x) => x !== null && x !== undefined && `${x}`.trim() !== "")
          .map((x) => `${x}`),
      ),
    ];

    // ----------------------------
    // Exhibitors by entry exhibitor_id
    // ----------------------------
    try {
      if (exhibitorIds.length === 0) {
        jsonFile(zip, "Data Backup/data/exhibitors.json", []);
        files.push({
          table: "exhibitors",
          path: "Data Backup/data/exhibitors.json",
          count: 0,
        });
      } else {
        const data = await selectAllByIn(
          supabase,
          "exhibitors",
          "id",
          exhibitorIds,
        );

        jsonFile(zip, "Data Backup/data/exhibitors.json", data ?? []);
        files.push({
          table: "exhibitors",
          path: "Data Backup/data/exhibitors.json",
          count: Array.isArray(data) ? data.length : 0,
        });
      }
    } catch (e) {
      zip.file(
        "Errors/exhibitors.txt",
        `Failed to export exhibitors: ${e?.message ?? e}`,
      );
    }

    // ----------------------------
    // Optional entry-related tables
    // ----------------------------
    const optionalEntryTables = [
      ["Data Backup/results/results.json", "results"],
    ];

    for (const [path, table] of optionalEntryTables) {
      if (entryIds.length === 0) {
        jsonFile(zip, path, []);
        files.push({ table, path, count: 0 });
        continue;
      }

      try {
        const data = await selectAllByIn(
          supabase,
          table,
          "entry_id",
          entryIds,
        );

        jsonFile(zip, path, data ?? []);
        files.push({
          table,
          path,
          count: Array.isArray(data) ? data.length : 0,
        });
      } catch (e) {
        zip.file(
          `Errors/${table}.txt`,
          `Skipped optional table ${table}: ${e?.message ?? e}`,
        );
      }
    }

    // ----------------------------
    // Section fee settings by section_id
    // ----------------------------
    try {
      const { data: sections, error: sectionsError } = await supabase
        .from("show_sections")
        .select("id")
        .eq("show_id", show_id);

      if (sectionsError) throw sectionsError;

      const sectionIds = (sections ?? [])
        .map((s) => s.id)
        .filter((x) => x !== null && x !== undefined && `${x}`.trim() !== "")
        .map((x) => `${x}`);

      if (sectionIds.length === 0) {
        jsonFile(zip, "Data Backup/settings/show_section_fee_settings.json", []);
        files.push({
          table: "show_section_fee_settings",
          path: "Data Backup/settings/show_section_fee_settings.json",
          count: 0,
        });
      } else {
        const data = await selectAllByIn(
          supabase,
          "show_section_fee_settings",
          "section_id",
          sectionIds,
        );

        jsonFile(zip, "Data Backup/settings/show_section_fee_settings.json", data ?? []);
        files.push({
          table: "show_section_fee_settings",
          path: "Data Backup/settings/show_section_fee_settings.json",
          count: Array.isArray(data) ? data.length : 0,
        });
      }
    } catch (e) {
      zip.file(
        "Errors/show_section_fee_settings.txt",
        `Failed to export show_section_fee_settings: ${e?.message ?? e}`,
      );
    }

    // ----------------------------
    // Manifest
    // ----------------------------
    jsonFile(zip, "manifest.json", manifest);

    const zipBytes = await zip.generateAsync({ type: "uint8array" });
    const fileName = `${showName}_locked_show_export_${Date.now()}.zip`;

    return new Response(zipBytes, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/octet-stream",
        "Content-Disposition": `attachment; filename="${fileName}"`,
      },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({
        error: e?.message ?? String(e),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
