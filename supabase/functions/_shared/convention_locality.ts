export type ConventionLocality = {
  city: string | null;
  state: string | null;
  status: "resolved" | "state_only" | "unavailable";
};

const unavailable = (): ConventionLocality => ({
  city: null,
  state: null,
  status: "unavailable",
});

// Only extract locality names; never return the echoed coordinates, boundary
// centroids, street information, or the rest of the provider response.
export function censusLocality(payload: unknown): ConventionLocality {
  const geo = (payload as {
    result?: { geographies?: Record<string, Record<string, unknown>[]> };
  } | null)?.result?.geographies;
  if (!geo) return unavailable();
  const state = geo.States?.[0]?.STUSAB;
  if (typeof state !== "string" || !/^[A-Z]{2}$/.test(state)) {
    return unavailable();
  }
  const place = geo["Incorporated Places"]?.[0] ??
    geo["Census Designated Places"]?.[0];
  const name = place?.BASENAME;
  const city = typeof name === "string" ? name.trim() : "";
  if (!city || city.length > 150 || /[\x00-\x1f\x7f]/.test(city)) {
    return { city: null, state, status: "state_only" };
  }
  return { city, state, status: "resolved" };
}

// US Census supports US states/territories without an API key. A failed lookup
// must not prevent an otherwise eligible purchase. No coordinates in logs.
export async function lookupConventionLocality(
  latitude: number,
  longitude: number,
  fetcher: typeof fetch = fetch,
): Promise<ConventionLocality> {
  try {
    const url = new URL(
      "https://geocoding.geo.census.gov/geocoder/geographies/coordinates",
    );
    url.search = new URLSearchParams({
      x: String(longitude),
      y: String(latitude),
      benchmark: "Public_AR_Current",
      vintage: "Current_Current",
      layers: "States,Incorporated Places,Census Designated Places",
      format: "json",
    }).toString();
    const response = await fetcher(url, {
      signal: AbortSignal.timeout(3000),
      headers: { Accept: "application/json" },
      redirect: "error",
    });
    if (!response.ok) {
      await response.body?.cancel();
      return unavailable();
    }
    return censusLocality(await response.json());
  } catch {
    return unavailable();
  }
}
