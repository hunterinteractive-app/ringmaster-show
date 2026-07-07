export default function Home() {
  return (
    <main
      style={{
        minHeight: "100vh",
        padding: "40px",
        fontFamily: "Arial, Helvetica, sans-serif",
        background:
          "linear-gradient(135deg, var(--background), var(--background-mid), var(--background-deep))",
      }}
    >
      <section
        style={{
          maxWidth: "720px",
          padding: "28px",
          borderRadius: "8px",
          background: "var(--surface)",
          color: "var(--foreground)",
        }}
      >
        <h1 style={{color: "var(--primary)"}}>RingMaster Show</h1>
        <p style={{color: "var(--muted)"}}>Rabbit Show Management Platform</p>

        <ul>
          <li>Create Shows</li>
          <li>Manage Exhibitors</li>
          <li>Generate Show Reports</li>
          <li>Track Entries</li>
        </ul>
      </section>
    </main>
  );
}
