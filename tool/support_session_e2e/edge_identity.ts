// Local fixture only: exercise the same Auth verification used by payment
// functions without contacting a provider or moving money.
Deno.serve(async (req) => {
  const user = await fetch(Deno.env.get("SUPABASE_URL") + "/auth/v1/user", {
    headers: {
      apikey: Deno.env.get("SUPABASE_ANON_KEY")!,
      Authorization: req.headers.get("Authorization") ?? "",
    },
  });
  if (!user.ok) return new Response("Unauthorized", { status: 401 });
  return Response.json({ authenticated_as: (await user.json()).id });
});
