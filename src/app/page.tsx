"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Image from "next/image";
import { supabase } from "@/lib/supabase";

type Screen = "sign-in" | "shows" | "points";
type PortalShow = {
  portal_club_id: string; club_name: string; show_id: string; show_name: string;
  show_date: string | null; show_location: string | null; breed_name: string | null;
  sanction_number: string | null; section_label: string | null; eligible_entry_count: number;
  report_status: "generated" | "failed" | "queued" | "not_ready"; report_artifact_id: string | null;
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
  const clubs = useMemo(() => Array.from(new Map(portalShows.map(show => [show.portal_club_id, show.club_name])).entries()).map(([id, name]) => ({ id, name })), [portalShows]);
  const selectedShows = portalShows.filter(show => !clubId || show.portal_club_id === clubId);
  const selectedClub = clubs.find(club => club.id === clubId)?.name ?? "Your club";

  if (loading) return <main className="loading-page">Loading Sweepstakes Portal…</main>;
  if (screen === "sign-in") return <SignIn acceptedTerms={acceptedTerms} authMessage={authMessage} authStep={authStep} pendingEmail={pendingEmail} onAcceptedTermsChange={setAcceptedTerms} onSignIn={signIn} onVerifyCode={verifyCode} onStartOver={() => { setAuthStep("email"); setAuthMessage(""); }} />;
  return <main className="portal-shell"><header className="topbar"><button className="brand" onClick={() => setScreen("shows")}><Image className="header-logo" src="/ringmaster-show-logo.png" alt="RingMaster Show" width={1536} height={1024} priority /><span><strong>RingMaster</strong><small>Sweepstakes Portal</small></span></button><div className="account"><span className="account-initial">{email.charAt(0).toUpperCase()}</span><span>{email}</span><button className="quiet-button" onClick={signOut}>Sign out</button></div></header><div className="portal-body"><aside className="sidebar"><p className="club-label">YOUR CLUB</p><div className="club-name">{selectedClub}</div><nav aria-label="Portal navigation"><button className={screen === "shows" ? "nav-item active" : "nav-item"} onClick={() => setScreen("shows")}><span>▦</span> Sanctioned shows</button><button className={screen === "points" ? "nav-item active" : "nav-item"} onClick={() => setScreen("points")}><span>◇</span> Points settings</button></nav><div className="support-card"><strong>Need a hand?</strong><p>Questions about a report or a sanction?</p><button>Contact RingMaster support</button></div></aside>{screen === "shows" ? <Shows clubs={clubs} clubId={clubId} isTester={isTester} onClubChange={setClubId} shows={selectedShows} onPoints={() => setScreen("points")} /> : <Points clubName={selectedClub} />}</div></main>;
}

function SignIn({ acceptedTerms, authMessage, authStep, pendingEmail, onAcceptedTermsChange, onSignIn, onVerifyCode, onStartOver }: { acceptedTerms: boolean; authMessage: string; authStep: "email" | "code"; pendingEmail: string; onAcceptedTermsChange: (accepted: boolean) => void; onSignIn: (event: FormEvent<HTMLFormElement>) => void; onVerifyCode: (event: FormEvent<HTMLFormElement>) => void; onStartOver: () => void }) { return <main className="sign-in-page"><section className="sign-in-panel"><Image className="login-logo" src="/ringmaster-show-logo.png" alt="RingMaster Show" width={1536} height={1024} priority /><div className="eyebrow">SWEEPSTAKES PORTAL</div><h1>{authStep === "email" ? "Your club's shows, reports, and points." : "Enter your six-digit code."}</h1><p className="lead">{authStep === "email" ? "See your Sweepstakes reports as soon as they are published, and find them anytime you need them." : `We sent a code to ${pendingEmail}.`}</p>{authStep === "email" ? <form onSubmit={onSignIn}><label>Email address<input name="email" type="email" placeholder="you@yourclub.org" required /></label><label className="terms-agreement"><input type="checkbox" checked={acceptedTerms} onChange={(event) => onAcceptedTermsChange(event.target.checked)} required /><span>I have read and agree to the <a href="https://show.ringmasterone.com/terms" target="_blank" rel="noreferrer">RingMaster Show Terms of Service</a> and <a href="https://show.ringmasterone.com/privacy" target="_blank" rel="noreferrer">Privacy Policy</a>.</span></label><button className="primary-button" type="submit" disabled={!acceptedTerms}>Email me a six-digit code</button></form> : <form onSubmit={onVerifyCode}><label>Six-digit code<input className="code-input" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} placeholder="000000" required autoFocus /></label><button className="primary-button" type="submit">Verify code</button><button className="text-button" type="button" onClick={onStartOver}>Use a different email</button></form>}{authMessage && <p className="invitation-note">{authMessage}</p>}<p className="invitation-note">Portal access is separate from RingMaster Show.</p></section><section className="sign-in-art" aria-hidden="true"><div className="art-copy"><span>ONE PLACE FOR</span><strong>Your reports, ready when you are.</strong><p>Track entries for each sanctioned show and download your Sweepstakes reports as soon as they are published.</p></div><div className="art-card"><span className="tiny-dot" /><strong>Reports ready</strong><span>Available after your show is published</span><hr /><small>Find past reports anytime</small></div></section></main>; }

function Shows({ clubs, clubId, isTester, onClubChange, shows, onPoints }: { clubs: { id: string; name: string }[]; clubId: string; isTester: boolean; onClubChange: (id: string) => void; shows: PortalShow[]; onPoints: () => void }) {
  const entries = shows.reduce((sum, show) => sum + Number(show.eligible_entry_count ?? 0), 0); const reports = shows.filter(show => show.report_status === "generated").length;
  return <section className="content"><div className="page-heading"><div><div className="eyebrow">{isTester ? "TESTER PREVIEW" : clubs[0]?.name?.toUpperCase()}</div><h1>Sanctioned shows</h1><p>Only shows sanctioned for your club appear here.</p></div>{isTester && <label className="club-picker">Preview club<select value={clubId} onChange={event => onClubChange(event.target.value)}>{clubs.map(club => <option key={club.id} value={club.id}>{club.name}</option>)}</select></label>}</div><div className="summary-grid"><div className="summary-card"><span>SANCTIONED SHOWS</span><strong>{shows.length}</strong><small>available to this club</small></div><div className="summary-card"><span>ELIGIBLE ENTRIES</span><strong>{entries}</strong><small>across sanctioned shows</small></div><div className="summary-card report-summary"><span>REPORTS READY</span><strong>{reports}</strong><small>available to download</small></div></div><div className="section-heading"><div><h2>Your shows</h2><p>Entry counts update as exhibitors enter the sanctioned breed.</p></div></div><div className="show-list">{shows.length ? shows.map(show => <article className="show-row" key={`${show.portal_club_id}-${show.sanction_number}-${show.show_id}`}><div className="date-block"><strong>{show.show_date ? new Date(`${show.show_date}T12:00:00`).toLocaleDateString("en-US", { month: "short" }).toUpperCase() : "—"}</strong><span>{show.show_date ? new Date(`${show.show_date}T12:00:00`).getDate() : "—"}</span></div><div className="show-details"><h3>{show.show_name}</h3><p>{show.show_location || "Location to be announced"} <i>•</i> {show.section_label || "All sections"}</p><small>{show.breed_name ? `${show.breed_name} · ` : ""}Sanction {show.sanction_number || "pending"}</small></div><div className="entry-count"><strong>{show.eligible_entry_count}</strong><span>eligible entries</span></div><div className={show.report_status === "generated" ? "status ready" : "status"}>{show.report_status === "generated" ? "Ready" : show.report_status === "queued" ? "In progress" : "Not ready"}</div><button className={show.report_status === "generated" ? "download-button" : "row-action"} disabled={show.report_status !== "generated"}>{show.report_status === "generated" ? "Download report ↓" : "Report pending"}</button></article>) : <div className="empty-state">No sanctioned shows are available for this club yet.</div>}</div><div className="callout"><div><strong>Want to change how points are calculated?</strong><p>Set a new points schedule for future shows without changing reports already issued.</p></div><button className="outline-button" onClick={onPoints}>Manage points <span>→</span></button></div></section>;
}

function Points({ clubName }: { clubName: string }) { return <section className="content points-page"><div className="page-heading"><div><div className="eyebrow">{clubName.toUpperCase()}</div><h1>Points settings</h1><p>Schedules apply prospectively and never alter a completed show report.</p></div></div><section className="settings-card"><div className="settings-intro"><h2>Points schedules</h2><p>Point-schedule editing is being connected next. Your existing reports remain unchanged.</p></div></section></section>; }
