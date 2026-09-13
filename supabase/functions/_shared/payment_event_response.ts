/** Successful receipt means durable responsibility, not finished registration. */
export function queuedPaymentEventResponse(event: {
  durably_queued?: boolean; duplicate?: boolean; processing_status?: string;
}): Response {
  if (event.durably_queued !== true) return Response.json({ received: false, retry: true }, { status: 503 });
  return Response.json({ received: true, duplicate: event.duplicate === true,
    queued: event.processing_status !== "processed", processed: event.processing_status === "processed" });
}
