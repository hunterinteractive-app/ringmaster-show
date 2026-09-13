import { assertEquals } from "jsr:@std/assert@1";
import { queuedPaymentEventResponse } from "./payment_event_response.ts";

for (const status of ["pending", "blocked", "processed"]) {
  Deno.test(`durable ${status} receipt distinguishes completion`, async () => {
    const response = queuedPaymentEventResponse({durably_queued: true, processing_status: status, duplicate: true});
    assertEquals(response.status, 200);
    assertEquals(await response.json(), {received: true, duplicate: true, queued: status !== "processed", processed: status === "processed"});
  });
}
Deno.test("acknowledgement requires durable storage even for a claimed completion", () => {
  for (const value of [undefined, false]) {
    assertEquals(queuedPaymentEventResponse({durably_queued: value, processing_status: "processed"}).status, 503);
  }
});
