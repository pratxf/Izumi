import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { upsertActivityLog } from "../utils/activity_log";

type PhotoDoc = {
  enterpriseId?: string;
  employeeId?: string;
  sessionId?: string | null;
  timestamp?: admin.firestore.Timestamp;
  location?: string;
  category?: string;
  customerName?: string;
  customerPhone?: string;
  notes?: string;
  latitude?: number;
  longitude?: number;
  imageUrl?: string;
  thumbnailUrl?: string;
};

export const onPhotoDocumentCreated = onDocumentCreated(
  {
    document: "photos/{photoId}",
    region: "asia-south1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const photoId = event.params.photoId;
    const photo = snapshot.data() as PhotoDoc;
    if (!photo.enterpriseId || !photo.employeeId) return;

    const detailParts: string[] = [];
    if (photo.location?.trim()) detailParts.push(photo.location.trim());
    if (photo.category?.trim()) detailParts.push(photo.category.trim());
    if (photo.customerName?.trim()) detailParts.push(photo.customerName.trim());

    await upsertActivityLog(admin.firestore(), {
      id: `photo_captured_${photoId}`,
      enterpriseId: photo.enterpriseId,
      employeeId: photo.employeeId,
      sessionId: photo.sessionId ?? null,
      orgId: photo.enterpriseId,
      type: "photo_captured",
      title: "Photo Captured",
      detail: detailParts.length > 0 ? detailParts.join(" \u2022 ") : "Photo uploaded",
      timestamp: photo.timestamp ?? admin.firestore.FieldValue.serverTimestamp(),
      payload: {
        photoId,
        photoUrl: photo.imageUrl ?? null,
        thumbnailUrl: photo.thumbnailUrl ?? null,
      },
      metadata: {
        photoId,
        location: photo.location ?? null,
        category: photo.category ?? null,
        customerName: photo.customerName ?? null,
        customerPhone: photo.customerPhone ?? null,
        notes: photo.notes ?? null,
        latitude: photo.latitude ?? null,
        longitude: photo.longitude ?? null,
        imageUrl: photo.imageUrl ?? null,
        thumbnailUrl: photo.thumbnailUrl ?? null,
      },
    });
  }
);
