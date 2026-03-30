import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

function toNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function buildPreciseDetail(detail: string, latitude: number, longitude: number): string {
  const coordinateLine = `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`;
  if (detail.includes(coordinateLine)) return detail;

  const trimmed = detail.trim();
  if (trimmed.length === 0) return coordinateLine;

  return `${trimmed}\n${coordinateLine}`;
}

export const enrichLocationUpdate = onDocumentCreated(
  {
    document: "activityLogs/{logId}",
    region: "asia-south1",
    retry: false,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    if (!data) return;
    if (data["type"] !== "location_update") return;

    const metadata = data["metadata"];
    if (!metadata || typeof metadata !== "object") return;

    const latitude = toNumber((metadata as Record<string, unknown>)["latitude"]);
    const longitude = toNumber((metadata as Record<string, unknown>)["longitude"]);
    if (latitude == null || longitude == null) return;

    const currentDetail = typeof data["detail"] === "string" ? data["detail"] : "";
    const preciseDetail = buildPreciseDetail(currentDetail, latitude, longitude);
    if (preciseDetail == currentDetail) return;

    logger.info("Enriching location update detail", {
      logId: snapshot.id,
      latitude,
      longitude,
    });

    await db.collection("activityLogs").doc(snapshot.id).update({
      detail: preciseDetail,
      metadata: {
        ...metadata,
        preciseCoordinates: coordinateLineFor(latitude, longitude),
      },
    });
  }
);

function coordinateLineFor(latitude: number, longitude: number): string {
  return `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`;
}
