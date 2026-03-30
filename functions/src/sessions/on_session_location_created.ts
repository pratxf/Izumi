import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import { upsertActivityLog } from "../utils/activity_log";

type SessionDoc = {
  enterpriseId?: string;
  employeeId?: string;
};

type SessionLocationDoc = {
  latitude?: number;
  longitude?: number;
  address?: string;
  timestamp?: admin.firestore.Timestamp;
  type?: string;
  title?: string;
  accuracy?: number;
  speed?: number;
  heading?: number;
  activityType?: string;
  activityConfidence?: number;
  distanceKm?: number;
};

export const onSessionLocationCreated = onDocumentCreated(
  {
    document: "sessions/{sessionId}/locations/{locationId}",
    region: "asia-south1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const { sessionId, locationId } = event.params;
    const location = snapshot.data() as SessionLocationDoc;
    const db = admin.firestore();

    const sessionSnap = await db.collection("sessions").doc(sessionId).get();
    if (!sessionSnap.exists) {
      logger.warn("onSessionLocationCreated: Missing session document.", {
        sessionId,
        locationId,
      });
      return;
    }

    const session = sessionSnap.data() as SessionDoc;
    if (!session.enterpriseId || !session.employeeId) {
      logger.warn("onSessionLocationCreated: Missing session identity fields.", {
        sessionId,
        locationId,
      });
      return;
    }

    const lat = typeof location.latitude === "number" ? location.latitude : null;
    const lng = typeof location.longitude === "number" ? location.longitude : null;
    const address = (location.address || "").trim();
    const accuracyMeters = location.accuracy ?? 0;

    await upsertActivityLog(db, {
      id: `location_update_${sessionId}_${locationId}`,
      enterpriseId: session.enterpriseId,
      employeeId: session.employeeId,
      sessionId,
      orgId: session.enterpriseId,
      type: "location_update",
      title: location.title?.trim() || "Location Update",
      detail:
        address ||
        (lat != null && lng != null ? `${lat}, ${lng}` : "Tracked location"),
      timestamp:
        location.timestamp ?? admin.firestore.FieldValue.serverTimestamp(),
      payload: {
        lat,
        lng,
        address,
        accuracyMeters,
      },
      metadata: {
        latitude: lat,
        longitude: lng,
        address,
        sourceLocationType: location.type || "location_update",
        accuracy: accuracyMeters,
        speed: location.speed ?? null,
        heading: location.heading ?? null,
        activityType: location.activityType ?? null,
        activityConfidence: location.activityConfidence ?? null,
        distanceKm: location.distanceKm ?? null,
        sessionLocationId: locationId,
      },
    });
  }
);
