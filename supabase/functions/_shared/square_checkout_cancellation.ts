import { squareRequest, SquareRequestError } from "./square.ts";

type SquareRequest = typeof squareRequest;

// Unlocking the local cart is permitted only after Square confirms that its
// exact order is canceled. A deleted/missing link alone is not proof of this.
export async function cancelUnpaidSquareLink(
  orderId: string,
  linkId: string,
  accessToken: string,
  request: SquareRequest = squareRequest,
): Promise<void> {
  if (!orderId || !linkId) {
    throw new Error(
      "The Square checkout is incomplete. Please contact support.",
    );
  }
  const orderPath = `/v2/orders/${encodeURIComponent(orderId)}`;
  const readOrder = async () => {
    const result = await request(orderPath, accessToken);
    const order = result.order as Record<string, unknown> | undefined;
    if (!order || order.id !== orderId) {
      throw new Error("Unable to verify this Square order. Please try again.");
    }
    if (
      order.state === "COMPLETED" ||
      (Array.isArray(order.tenders) && order.tenders.length > 0)
    ) {
      throw new Error(
        "Square has a payment in progress or completed for this cart. Check its payment status before making changes.",
      );
    }
    return order;
  };
  const before = await readOrder();
  if (before.state !== "CANCELED") {
    try {
      await request(
        `/v2/online-checkout/payment-links/${encodeURIComponent(linkId)}`,
        accessToken,
        { method: "DELETE" },
      );
    } catch (error) {
      if (
        !(error instanceof SquareRequestError && error.code === "NOT_FOUND")
      ) {
        throw error;
      }
    }
  }
  const after = await readOrder();
  if (after.state !== "CANCELED") {
    throw new Error(
      "Square has not confirmed cancellation yet. Your cart is still protected; please try again.",
    );
  }
}
