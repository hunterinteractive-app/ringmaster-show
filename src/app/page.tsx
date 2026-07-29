"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Image from "next/image";
import { supabase } from "@/lib/supabase";

type Screen = "sign-in" | "shows" | "points";
type PortalShow = {
  portal_club_id: string; club_name: string; show_id: string; show_name: string;
  show_date: string | null; show_location: string | null; breed_name: string | null;
  sanction_number: string | null; section_label: string | null; eligible_entry_count: number;
  report_status: "generated" | "failed" | "queued" | "not_ready" | "no_animals_shown"; report_artifact_id: string | null;
};

export default function Home() {
  const [screen, setScreen] = useState<Screen>("sign-in");
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [authMessage, setAuthMessage] = useState("");
  const [pendingEmail, setPendingEmail] = useState("");
  const [verificationType, setVerificationType] = useState<"email" | "magiclink">("magiclink");
  const [authStep, setAuthStep] = useState<"email" | "code">("email");
  const [email, setEmail] = useState("");
  const [portalShows, setPortalShows] = useState<PortalShow[]>([]);
  const [isTester, setIsTester] = useState(false);
  const [clubId, setClubId] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function openPortal(userEmail: string) {
      setLoading(true); setEmail(userEmail);
      await supabase.rpc("record_sweepstakes_portal_legal_acceptance", { p_terms_version: "2026-07-29", p_privacy_version: "2026-07-29" });
      const [{ data: shows, error }, { data: tester }] = await Promise.all([
        supabase.rpc("list_sweepstakes_portal_shows"),
        supabase.rpc("is_sweepstakes_portal_tester"),
      ]);
      if (error) setAuthMessage("We could not load your portal access. Please try again.");
      const rows = (shows ?? []) as PortalShow[];
      setPortalShows(rows); setIsTester(Boolean(tester)); setClubId(rows[0]?.portal_club_id ?? "");
      setScreen("shows"); setLoading(false);
    }
    const loadSession = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (session) await openPortal(session.user.email ?? ""); else setLoading(false);
    };
    void loadSession();
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) void openPortal(session.user.email ?? "");
    });
    return () => subscription.unsubscribe();
  }, []);

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!acceptedTerms) return;
    const signInEmail = String(new FormData(event.currentTarget).get("email") ?? "").trim();
    const { data, error } = await supabase.functions.invoke("sweepstakes-request-code", { body: { email: signInEmail } });
    if (error || !data?.ok) { setAuthMessage(data?.error ?? "We could not send a sign-in code. Please try again."); return; }
    setPendingEmail(signInEmail); setAuthStep("code"); setAuthMessage("We emailed a six-digit code to you.");
    setVerificationType(data.verification_type === "email" ? "email" : "magiclink");
  }

  async function verifyCode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const token = String(new FormData(event.currentTarget).get("code") ?? "").replace(/\D/g, "");
    if (token.length !== 6) { setAuthMessage("Enter the six-digit code from your email."); return; }
    const { error } = await supabase.auth.verifyOtp({ email: pendingEmail, token, type: verificationType });
    setAuthMessage(error ? "That code did not work. Request a new one and try again." : "");
  }

  async function signOut() { await supabase.auth.signOut(); setScreen("sign-in"); setPortalShows([]); setEmail(""); setAuthMessage(""); }
  const clubs = useMemo(() => Array.from(new Map(portalShows.map(show => [show.portal_club_id, show.club_name])).entries()).map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name)), [portalShows]);
  const selectedShows = portalShows.filter(show => !clubId || show.portal_club_id === clubId);
  const selectedClub = clubs.find(club => club.id === clubId)?.name ?? "Your club";

  if (loading) return <main className="loading-page">Loading Sweepstakes Portal…</main>;
  if (screen === "sign-in") return <SignIn acceptedTerms={acceptedTerms} authMessage={authMessage} authStep={authStep} pendingEmail={pendingEmail} onAcceptedTermsChange={setAcceptedTerms} onSignIn={signIn} onVerifyCode={verifyCode} onStartOver={() => { setAuthStep("email"); setAuthMessage(""); }} />;
  return <main className="portal-shell"><header className="topbar"><button className="brand" onClick={() => setScreen("shows")}><Image className="header-logo" src="/ringmaster-show-logo.png" alt="RingMaster Show" width={1536} height={1024} priority /><span><strong>RingMaster</strong><small>Sweepstakes Portal</small></span></button><div className="account"><span className="account-initial">{email.charAt(0).toUpperCase()}</span><span>{email}</span><button className="quiet-button" onClick={signOut}>Sign out</button></div></header><div className="portal-body"><aside className="sidebar"><p className="club-label">YOUR CLUB</p><div className="club-name">{selectedClub}</div><nav aria-label="Portal navigation"><button className={screen === "shows" ? "nav-item active" : "nav-item"} onClick={() => setScreen("shows")}><span>▦</span> Sanctioned shows</button><button className={screen === "points" ? "nav-item active" : "nav-item"} onClick={() => setScreen("points")}><span>◇</span> Points settings</button></nav><div className="support-card"><strong>Need a hand?</strong><p>Questions about a report or a sanction?</p><button>Contact RingMaster support</button></div></aside>{screen === "shows" ? <Shows clubs={clubs} clubId={clubId} isTester={isTester} onClubChange={setClubId} shows={selectedShows} onPoints={() => setScreen("points")} /> : <Points clubName={selectedClub} />}</div></main>;
}

function SignIn({ acceptedTerms, authMessage, authStep, pendingEmail, onAcceptedTermsChange, onSignIn, onVerifyCode, onStartOver }: { acceptedTerms: boolean; authMessage: string; authStep: "email" | "code"; pendingEmail: string; onAcceptedTermsChange: (accepted: boolean) => void; onSignIn: (event: FormEvent<HTMLFormElement>) => void; onVerifyCode: (event: FormEvent<HTMLFormElement>) => void; onStartOver: () => void }) { return <main className="sign-in-page"><section className="sign-in-panel"><Image className="login-logo" src="/ringmaster-show-logo.png" alt="RingMaster Show" width={1536} height={1024} priority /><div className="eyebrow">SWEEPSTAKES PORTAL</div><h1>{authStep === "email" ? "Your club's shows, reports, and points." : "Enter your six-digit code."}</h1><p className="lead">{authStep === "email" ? "See your Sweepstakes reports as soon as they are published, and find them anytime you need them." : `We sent a code to ${pendingEmail}.`}</p>{authStep === "email" ? <form onSubmit={onSignIn}><label>Email address<input name="email" type="email" placeholder="you@yourclub.org" required /></label><label className="terms-agreement"><input type="checkbox" checked={acceptedTerms} onChange={(event) => onAcceptedTermsChange(event.target.checked)} required /><span>I have read and agree to the <a href="https://show.ringmasterone.com/terms" target="_blank" rel="noreferrer">RingMaster Show Terms of Service</a> and <a href="https://show.ringmasterone.com/privacy" target="_blank" rel="noreferrer">Privacy Policy</a>.</span></label><button className="primary-button" type="submit" disabled={!acceptedTerms}>Email me a six-digit code</button></form> : <form onSubmit={onVerifyCode}><label>Six-digit code<input className="code-input" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} placeholder="000000" required autoFocus /></label><button className="primary-button" type="submit">Verify code</button><button className="text-button" type="button" onClick={onStartOver}>Use a different email</button></form>}{authMessage && <p className="invitation-note">{authMessage}</p>}<p className="invitation-note">Portal access is separate from RingMaster Show.</p></section><section className="sign-in-art" aria-hidden="true"><div className="art-copy"><span>ONE PLACE FOR</span><strong>Your reports, ready when you are.</strong><p>Track entries for each sanctioned show and download your Sweepstakes reports as soon as they are published.</p></div><div className="art-card"><span className="tiny-dot" /><strong>Reports ready</strong><span>Available after your show is published</span><hr /><small>Find past reports anytime</small></div></section></main>; }

function Shows({ clubs, clubId, isTester, onClubChange, shows, onPoints }: { clubs: { id: string; name: string }[]; clubId: string; isTester: boolean; onClubChange: (id: string) => void; shows: PortalShow[]; onPoints: () => void }) {
  const [loadingKey, setLoadingKey] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [reportsToView, setReportsToView] = useState<{ title: string; downloads: { name: string; url: string }[] } | null>(null);
  const entries = shows.reduce((sum, show) => sum + Number(show.eligible_entry_count ?? 0), 0);
  const reports = shows.filter(show => show.report_status === "generated").length;
  const keyFor = (show: PortalShow) => `${show.portal_club_id}-${show.show_id}-${show.sanction_number}`;

  async function getReports(show: PortalShow) {
    const { data, error } = await supabase.functions.invoke("sweepstakes-download-reports", { body: { show_id: show.show_id, portal_club_id: show.portal_club_id, sanction_number: show.sanction_number } });
    if (error || !data?.downloads?.length) throw new Error(data?.error ?? "We could not prepare those reports. Please try again.");
    return data.downloads as { name: string; url: string }[];
  }

  async function downloadReports(show: PortalShow) {
    const key = keyFor(show); setLoadingKey(key); setMessage("");
    try {
      const downloads = await getReports(show);
      for (const download of downloads) {
        const response = await fetch(download.url);
        if (!response.ok) throw new Error("One of the report files could not be downloaded. Please try again.");
        const blobUrl = URL.createObjectURL(await response.blob());
        const link = document.createElement("a"); link.href = blobUrl; link.download = download.name;
        document.body.appendChild(link); link.click(); link.remove();
        window.setTimeout(() => URL.revokeObjectURL(blobUrl), 1000);
      }
      setMessage(downloads.length > 1 ? `${downloads.length} reports are downloading.` : "Your report is downloading.");
    } catch (error) { setMessage(error instanceof Error ? error.message : "We could not prepare those reports."); }
    setLoadingKey(null);
  }

  async function viewReports(show: PortalShow) {
    const key = keyFor(show); setLoadingKey(key); setMessage("");
    try { setReportsToView({ title: `${show.show_name} — ${show.section_label || "Reports"}`, downloads: await getReports(show) }); }
    catch (error) { setMessage(error instanceof Error ? error.message : "We could not prepare those reports."); }
    setLoadingKey(null);
  }

  return <section className="content">
    <div className="page-heading"><div><div className="eyebrow">{isTester ? "TESTER PREVIEW" : clubs[0]?.name?.toUpperCase()}</div><h1>Sanctioned shows</h1><p>Only shows sanctioned for your club appear here.</p></div>{isTester && <label className="club-picker">Preview club<select value={clubId} onChange={event => onClubChange(event.target.value)}>{clubs.map(club => <option key={club.id} value={club.id}>{club.name}</option>)}</select></label>}</div>
    <div className="summary-grid"><div className="summary-card"><span>SANCTIONED SHOWS</span><strong>{shows.length}</strong><small>available to this club</small></div><div className="summary-card"><span>ELIGIBLE ENTRIES</span><strong>{entries}</strong><small>across sanctioned shows</small></div><div className="summary-card report-summary"><span>REPORTS READY</span><strong>{reports}</strong><small>available to download</small></div></div>
    <div className="section-heading"><div><h2>Your shows</h2><p>Entry counts update as exhibitors enter the sanctioned breed.</p></div>{message && <p className="download-message">{message}</p>}</div>
    {reportsToView && <section className="report-viewer"><div><strong>{reportsToView.title}</strong><span>Choose a report to view in a new tab.</span></div><div className="report-viewer-links">{reportsToView.downloads.map(report => <a key={report.url} href={report.url} target="_blank" rel="noreferrer">View {report.name} ↗</a>)}<button className="text-button" onClick={() => setReportsToView(null)}>Close</button></div></section>}
    <div className="show-list">{shows.length ? shows.map(show => { const noAnimals = show.report_status === "no_animals_shown"; const ready = show.report_status === "generated"; const key = keyFor(show); return <article className="show-row" key={key}><div className="date-block"><strong>{show.show_date ? new Date(`${show.show_date}T12:00:00`).toLocaleDateString("en-US", { month: "short" }).toUpperCase() : "—"}</strong><span>{show.show_date ? new Date(`${show.show_date}T12:00:00`).getDate() : "—"}</span></div><div className="show-details"><h3>{show.show_name}</h3><p>{show.show_location || "Location to be announced"} <i>•</i> {show.section_label || "All sections"}</p><small>{show.breed_name ? `${show.breed_name} · ` : ""}Sanction {show.sanction_number || "pending"}</small></div><div className="entry-count"><strong>{show.eligible_entry_count}</strong><span>eligible entries</span></div><div className={ready ? "status ready" : "status"}>{ready ? "Ready" : noAnimals ? "No animals shown" : show.report_status === "queued" ? "In progress" : "Not ready"}</div><div className="report-actions"><button className={ready ? "download-button" : "row-action"} disabled={!ready || loadingKey === key} onClick={() => void downloadReports(show)}>{ready ? loadingKey === key ? "Preparing…" : "Download ↓" : noAnimals ? "No report needed" : "Report pending"}</button>{ready && <button className="view-button" disabled={loadingKey === key} onClick={() => void viewReports(show)}>View reports ↗</button>}</div></article>; }) : <div className="empty-state">No sanctioned shows are available for this club yet.</div>}</div>
    <div className="callout"><div><strong>Want to change how points are calculated?</strong><p>Set a new points schedule for future shows without changing reports already issued.</p></div><button className="outline-button" onClick={onPoints}>Manage points <span>→</span></button></div>
  </section>;
}

function Points({ clubName }: { clubName: string }) {
  type Placement = { place: number; points: number | string };
  type Award = { code: string; source_type: string; rabbit_points: number | string; cavy_points: number | string; active: boolean };
  type NationalProfile = { breed_name: string; class_points_model: string; multiplier_type: string; placement_depth: number; notes: string | null };
  const [clubId, setClubId] = useState<string | null>(null);
  const [placements, setPlacements] = useState<Placement[]>([]);
  const [awards, setAwards] = useState<Award[]>([]);
  const [nationalProfiles, setNationalProfiles] = useState<NationalProfile[]>([]);
  const [showType, setShowType] = useState<"regular" | "national">("regular");
  const [multiplyByClassSize, setMultiplyByClassSize] = useState(true);
  const [schedules, setSchedules] = useState<{ id: string; effective_on: string }[]>([]);
  const [canManage, setCanManage] = useState(false);
  const [pointMode, setPointMode] = useState<"rabbit" | "cavy" | "none">("none");
  const [showDatePrompt, setShowDatePrompt] = useState(false);
  const [effectiveOn, setEffectiveOn] = useState("");
  const [message, setMessage] = useState("");
  const today = new Date().toISOString().slice(0, 10);

  useEffect(() => { async function load() {
    const { data: club } = await supabase.from("sweepstakes_portal_clubs").select("id").eq("name", clubName).maybeSingle();
    if (!club?.id) { setMessage("This club's points settings are not available yet."); return; }
    setClubId(club.id);
    const [{ data: defaults, error: defaultsError }, { data: rows }, { data: allowed }, { data: pointModeValue }] = await Promise.all([
      supabase.rpc("get_sweepstakes_portal_point_defaults", { p_portal_club_id: club.id }),
      supabase.from("sweepstakes_point_schedules").select("id, effective_on").eq("portal_club_id", club.id).order("effective_on", { ascending: false }),
      supabase.rpc("can_manage_sweepstakes_points", { p_portal_club_id: club.id }),
      supabase.rpc("get_sweepstakes_portal_point_schedule_mode", { p_portal_club_id: club.id }),
    ]);
    if (defaultsError) { setMessage("We could not import the current points settings."); return; }
    const mode = pointModeValue === "rabbit" || pointModeValue === "cavy" ? pointModeValue : "none"; setPlacements(defaults?.placements ?? []); setAwards(defaults?.awards ?? []); setNationalProfiles(defaults?.national_profiles ?? []); setSchedules(rows ?? []); setPointMode(mode); setCanManage(Boolean(allowed) && mode === "rabbit"); if (mode === "none") setMessage("Point schedules are not available for this club yet.");
  } void load(); }, [clubName]);

  function updatePlacement(index: number, value: string) { setPlacements(current => current.map((row, i) => i === index ? { ...row, points: value } : row)); }
  function updateAward(index: number, field: "rabbit_points" | "cavy_points", value: string) { setAwards(current => current.map((row, i) => i === index ? { ...row, [field]: value } : row)); }
  async function saveSchedule(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!clubId || !effectiveOn) return;
    if (effectiveOn < today) { setMessage("Choose today or a future effective date."); return; }
    const { data: { user } } = await supabase.auth.getUser(); if (!user) return;
    const rules = { version: 1, imported_from: "current_database", show_type: showType, class_points_model: multiplyByClassSize ? "MULTIPLIER_BY_CLASS_SIZE" : "FLAT_BY_PLACING", placements: placements.map(row => ({ ...row, points: Number(row.points) })), awards: awards.map(row => ({ ...row, rabbit_points: Number(row.rabbit_points), cavy_points: Number(row.cavy_points) })), national_profiles: showType === "national" ? nationalProfiles : [] };
    const { data, error } = await supabase.from("sweepstakes_point_schedules").upsert({ portal_club_id: clubId, effective_on: effectiveOn, rules, created_by: user.id }, { onConflict: "portal_club_id,effective_on" }).select("id, effective_on").single();
    if (error) { setMessage("We could not save this schedule. Please try again."); return; }
    setSchedules(current => [data, ...current.filter(row => row.id !== data.id)].sort((a, b) => b.effective_on.localeCompare(a.effective_on))); setShowDatePrompt(false); setEffectiveOn(""); setMessage("Points schedule saved.");
  }

  return <section className="content points-page"><div className="page-heading"><div><div className="eyebrow">{clubName.toUpperCase()}</div><h1>Points settings</h1><p>Schedules apply prospectively and never alter a completed show report.</p></div></div><section className="settings-card"><div className="settings-intro"><div><h2>Points schedule</h2><p>Import the current scale, choose the show type, then set the effective date when you save.</p></div></div><div className="schedule-body">{canManage ? <><label className="show-type-picker">Show type<select value={showType} onChange={event => setShowType(event.target.value as "regular" | "national")}><option value="regular">Regular show</option><option value="national">National / Convention show</option></select></label><label className="multiplier-question"><input type="checkbox" checked={multiplyByClassSize} onChange={event => setMultiplyByClassSize(event.target.checked)} /><span><strong>Multiply placement points by the number in the class</strong><small>When unchecked, the class placement points are applied as flat values.</small></span></label>{showType === "national" && <div className="national-profile-note"><strong>National club rules</strong>{nationalProfiles.length ? nationalProfiles.map(profile => <p key={profile.breed_name}><b>{profile.breed_name}</b> — {profile.class_points_model.replaceAll("_", " ").toLowerCase()} · {profile.multiplier_type.replaceAll("_", " ").toLowerCase()}{profile.notes ? ` · ${profile.notes}` : ""}</p>) : <p>No special national profile is currently recorded for this club; the edited schedule below will apply.</p>}</div>}<div className="point-editor"><div><strong>Class placement points</strong><small>Points per placing</small></div>{placements.map((row, index) => <label className="point-input" key={row.place}><span>{row.place}{row.place === 1 ? "st" : row.place === 2 ? "nd" : row.place === 3 ? "rd" : "th"} place</span><input type="number" min="0" step="0.25" value={row.points} onChange={event => updatePlacement(index, event.target.value)} /></label>)}</div><details className="award-editor"><summary>Optional award points</summary><p>These are imported from the current database and are set to zero unless your club chooses to award extra points.</p>{awards.map((award, index) => <div className="award-row" key={award.code}><strong>{award.code}</strong><label>Rabbit<input type="number" min="0" step="0.25" value={award.rabbit_points} onChange={event => updateAward(index, "rabbit_points", event.target.value)} /></label><label>Cavy<input type="number" min="0" step="0.25" value={award.cavy_points} onChange={event => updateAward(index, "cavy_points", event.target.value)} /></label></div>)}</details><div className="settings-footer"><p>Saving opens a confirmation so you can choose the effective date.</p><button className="primary-button" onClick={() => setShowDatePrompt(true)}>Save changes</button></div></> : <div className="settings-note"><span>i</span><p><strong>Read-only access</strong><br />Only the points manager assigned to this club can change its schedule.</p></div>}{message && <p className="schedule-message">{message}</p>}<div className="schedule-list"><strong>Schedule history</strong>{schedules.length ? schedules.map(schedule => <div className="schedule-row" key={schedule.id}><span>{new Date(`${schedule.effective_on}T12:00:00`).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}</span><small>Applies to shows on or after this date</small></div>) : <p>No saved schedules yet.</p>}</div></div></section>{showDatePrompt && <div className="schedule-modal-backdrop" role="presentation"><form className="schedule-modal" onSubmit={saveSchedule}><h2>When should these points take effect?</h2><p>Completed reports will not change. This {showType === "national" ? "National / Convention" : "regular"} schedule will apply to matching shows on or after the date you choose.</p><label>Effective date<input type="date" min={today} value={effectiveOn} onChange={event => setEffectiveOn(event.target.value)} required autoFocus /></label><div><button className="text-button" type="button" onClick={() => setShowDatePrompt(false)}>Cancel</button><button className="primary-button" type="submit">Save schedule</button></div></form></div>}</section>;
}
