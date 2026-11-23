import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  after,
  before,
  beforeEach,
  test,
} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  deleteField,
  documentId,
  doc,
  getDoc,
  getDocs,
  getCountFromServer,
  limit,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  startAfter,
  updateDoc,
  where,
  writeBatch,
} from "firebase/firestore";

const projectId = "demo-aula-presente-firestore-rules-tests";
const currentDirectory = dirname(fileURLToPath(import.meta.url));
const rulesPath = resolve(currentDirectory, "../../firestore.rules");
const [emulatorHost, emulatorPort] = (
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080"
).split(":");

let testEnvironment;

async function assertPermissionDenied(operation) {
  await assert.rejects(operation, (error) => {
    assert.equal(error?.code, "permission-denied");
    assert.equal(
      String(error?.message).includes("maximum of 1000 expressions"),
      false,
      "a Rules expression-limit failure is not a valid permission denial",
    );
    return true;
  });
}

function profile(email, roles = ["student"], extraFields = {}) {
  return {
    name: "Usuario de prueba",
    email,
    studentCode: "STU-001",
    roles,
    ...extraFields,
  };
}

function demoRecord(extraFields = {}) {
  return {
    title: "Registro de prueba",
    description: "Contenido de prueba",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extraFields,
  };
}

function teacherAccessRequest(uid, profileData, extraFields = {}) {
  return {
    uid,
    name: profileData.name,
    email: profileData.email,
    studentCode: profileData.studentCode,
    status: "pending",
    createdAt: serverTimestamp(),
    decidedBy: null,
    decidedAt: null,
    rejectionReason: null,
    ...extraFields,
  };
}

function userContext(uid, email, emailVerified = false) {
  return testEnvironment.authenticatedContext(uid, {
    email,
    email_verified: emailVerified,
  }).firestore();
}

async function seedDemoRecord(uid, recordId = "record-1") {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "users", uid, "demo_records", recordId),
      demoRecord(),
    );
  });
}

async function seedProfile(uid, email, roles = ["student"], extraFields = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "users", uid),
      profile(email, roles, extraFields),
    );
  });
}

async function seedCourse(
  uid,
  courseId,
  blocks = [courseBlock()],
  courseExtraFields = {},
) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(
      doc(db, "courses", courseId),
      courseData(uid, { blocks, extraFields: courseExtraFields }),
    );
    blocks.forEach((block, order) => {
      batch.set(
        doc(db, "courses", courseId, "weekly_blocks", block.id),
        courseBlockDocument(block, order),
      );
    });
    await batch.commit();
  });
}

function attendanceDate(offsetDays = 0) {
  return Timestamp.fromMillis(bogotaToday().toMillis() + offsetDays * 86400000);
}

function attendanceConfig(uid, mode = "meeting", extra = {}) {
  return {
    schemaVersion: 1,
    mode,
    sessionCount: 0,
    lastSessionId: null,
    createdAt: serverTimestamp(),
    createdBy: uid,
    updatedAt: serverTimestamp(),
    updatedBy: uid,
    ...extra,
  };
}

function attendanceSessionData(courseId, ownerUid, occurrenceId, extra = {}) {
  const scheduledDate = attendanceDate(1);
  return {
    schemaVersion: 1,
    courseId,
    ownerUid,
    occurrenceId,
    occurrenceKind: "planned",
    mode: "meeting",
    status: "preparing",
    rosterState: "building",
    scheduledDate,
    effectiveDate: scheduledDate,
    startMinute: 480,
    endMinute: 540,
    timezone: "America/Bogota",
    segmentIds: [],
    rosterCount: 1,
    markedCount: 0,
    unmarkedCount: 1,
    unmarkedConfirmed: false,
    version: 1,
    lastMutationRosterEntryId: null,
    lastMutationKind: null,
    lastEventId: null,
    createdAt: serverTimestamp(),
    createdBy: ownerUid,
    updatedAt: serverTimestamp(),
    updatedBy: ownerUid,
    ...extra,
  };
}

function attendanceRosterEntry(rosterEntryId, extra = {}) {
  return {
    rosterEntryId,
    displayName: "Estudiante de prueba",
    meetingMark: "unmarked",
    justificationStatus: "none",
    justifiedUnits: 0,
    version: 0,
    updatedAt: serverTimestamp(),
    updatedBy: "teacher",
    ...extra,
  };
}

function attendanceRecordData(courseId, sessionId, rosterEntryId, extra = {}) {
  const scheduledDate = attendanceDate(-1);
  return {
    schemaVersion: 1,
    courseId,
    sessionId,
    rosterEntryId,
    visibility: "published",
    mode: "meeting",
    scheduledDate,
    effectiveDate: scheduledDate,
    startMinute: 480,
    endMinute: 540,
    unitCount: 1,
    absentUnits: 0,
    inReviewUnits: 0,
    justifiedUnits: 0,
    result: "present",
    publishedAt: scheduledDate,
    updatedAt: scheduledDate,
    ...extra,
  };
}

async function seedAttendanceConfig(courseId, uid, mode = "meeting", extra = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "courses", courseId, "attendance_config", "current"),
      attendanceConfig(uid, mode, extra),
    );
  });
}

async function seedAttendanceSession(courseId, uid, occurrenceId, extra = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "courses", courseId, "attendance_sessions", occurrenceId),
      attendanceSessionData(courseId, uid, occurrenceId, extra),
    );
  });
}

async function seedAttendanceEnrollment(courseId, studentUid, ownerUid, email, rosterEntryId = email) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const data = enrollmentData(studentUid, ownerUid, email);
    if (rosterEntryId == null) delete data.rosterEntryId;
    else data.rosterEntryId = rosterEntryId;
    await setDoc(
      doc(context.firestore(), "courses", courseId, "enrollments", studentUid),
      data,
    );
  });
}

async function seedAttendanceRecord(courseId, sessionId, rosterEntryId, extra = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(
        context.firestore(),
        "courses",
        courseId,
        "attendance_records",
        `${sessionId}|${rosterEntryId}`,
      ),
      attendanceRecordData(courseId, sessionId, rosterEntryId, extra),
    );
  });
}

function directoryData(uid, email, profileData = profile(email), extra = {}) {
  return {
    uid,
    name: profileData.name,
    email,
    studentCode: profileData.studentCode,
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

async function publishStudent(uid, email, profileData = profile(email)) {
  const student = userContext(uid, email, true);
  await assertSucceeds(setDoc(
    doc(student, "student_directory", email),
    directoryData(uid, email, profileData),
  ));
  return student;
}

function enrollmentData(studentUid, ownerUid, email, profileData = profile(email), extra = {}) {
  return {
    studentUid,
    ownerUid,
    name: profileData.name,
    email,
    studentCode: profileData.studentCode,
    subject: "Bases de Datos",
    group: "Grupo 2",
    period: "2027-1",
    status: "active",
    createdAt: serverTimestamp(),
    rosterEntryId: email,
    effectiveStartDate: Timestamp.fromDate(new Date("2027-01-04T00:00:00.000Z")),
    ...extra,
  };
}

function bogotaToday() {
  const shifted = new Date(Date.now() - 5 * 60 * 60 * 1000);
  return Timestamp.fromDate(new Date(Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  )));
}

function courseRangeAroundBogotaToday() {
  const today = bogotaToday();
  return {
    startDate: Timestamp.fromMillis(today.toMillis() - 14 * 86400000),
    endDate: Timestamp.fromMillis(today.toMillis() + 60 * 86400000),
  };
}

function pendingEnrollmentData(
  courseId,
  ownerUid,
  email,
  course = courseData(ownerUid),
  extra = {},
) {
  return {
    courseId,
    ownerUid,
    subject: course.subject,
    group: course.group,
    period: course.period,
    email,
    studentCode: "STU-001",
    name: "Usuario de prueba",
    status: "pending",
    effectiveStartDate: course.startDate,
    rosterEntryId: email,
    studentUid: null,
    authorizedAt: serverTimestamp(),
    linkedAt: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    lastEventId: null,
    lastStatusChangedAt: null,
    ...extra,
  };
}

async function createPendingEnrollment(db, courseId, email, extra = {}) {
  const courseRef = doc(db, "courses", courseId);
  const pendingRef = doc(db, "courses", courseId, "pending_enrollments", email);
  const courseSnapshot = await getDoc(courseRef);
  if (!courseSnapshot.exists()) throw new Error("missing-course");
  await setDoc(pendingRef, pendingEnrollmentData(
    courseId,
    courseSnapshot.data().ownerUid,
    email,
    courseSnapshot.data(),
    extra,
  ));
  return pendingRef;
}

async function changePendingEnrollmentAtomically(
  db,
  courseId,
  email,
  operationId,
  nextStatus,
  effectiveDate,
  eventOptions = {},
) {
  const pendingRef = doc(db, "courses", courseId, "pending_enrollments", email);
  const eventRef = doc(
    db,
    "courses",
    courseId,
    "pending_enrollments",
    email,
    "status_events",
    operationId,
  );
  return runTransaction(db, async (transaction) => {
    const pendingSnapshot = await transaction.get(pendingRef);
    if (!pendingSnapshot.exists()) throw new Error("missing-pending-enrollment");
    const before = pendingSnapshot.data();
    if (before.status === "linked") return "already-linked";
    transaction.update(pendingRef, {
      status: nextStatus,
      ...(nextStatus === "pending" ? { effectiveStartDate: effectiveDate } : {}),
      ...(nextStatus === "linked" ? { studentUid: "student", linkedAt: serverTimestamp() } : {}),
      updatedAt: serverTimestamp(),
      lastEventId: operationId,
      lastStatusChangedAt: serverTimestamp(),
    });
    transaction.set(eventRef, {
      fromStatus: before.status,
      toStatus: nextStatus,
      effectiveDate,
      ...(!eventOptions.omitFromEffectiveStartDate
        ? { fromEffectiveStartDate: eventOptions.fromEffectiveStartDate ?? before.effectiveStartDate }
        : {}),
      changedAt: serverTimestamp(),
      changedBy: before.ownerUid,
    });
    return nextStatus;
  });
}

async function linkPendingEnrollmentAtomically(
  db,
  courseId,
  email,
  studentUid,
  {
    operationId = "link",
    resolveMatchingJoinRequest = true,
    omitFromEffectiveStartDate = false,
    fromEffectiveStartDate,
  } = {},
) {
  const pendingRef = doc(db, "courses", courseId, "pending_enrollments", email);
  const enrollmentRef = doc(db, "courses", courseId, "enrollments", studentUid);
  const profileRef = doc(db, "users", studentUid);
  const requestRef = doc(db, "courses", courseId, "join_requests", studentUid);
  const eventRef = doc(
    db,
    "courses",
    courseId,
    "pending_enrollments",
    email,
    "status_events",
    operationId,
  );
  return runTransaction(db, async (transaction) => {
    const [pendingSnapshot, enrollmentSnapshot, profileSnapshot, requestSnapshot] = await Promise.all([
      transaction.get(pendingRef),
      transaction.get(enrollmentRef),
      transaction.get(profileRef),
      transaction.get(requestRef),
    ]);
    if (!pendingSnapshot.exists() || !profileSnapshot.exists()) {
      throw new Error("missing-link-source");
    }
    const pending = pendingSnapshot.data();
    if (pending.status === "linked") return "already-linked";
    const profileData = profileSnapshot.data();
    if (!enrollmentSnapshot.exists()) {
      transaction.set(enrollmentRef, {
        studentUid,
      ownerUid: pending.ownerUid,
        name: pending.name,
        email: profileData.email,
        studentCode: profileData.studentCode,
        subject: pending.subject,
        group: pending.group,
        period: pending.period,
        status: "active",
        createdAt: serverTimestamp(),
        rosterEntryId: pending.rosterEntryId,
        effectiveStartDate: pending.effectiveStartDate,
      });
    }
    transaction.update(pendingRef, {
      status: "linked",
      studentUid,
      linkedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      lastEventId: operationId,
      lastStatusChangedAt: serverTimestamp(),
    });
    transaction.set(eventRef, {
      fromStatus: pending.status,
      toStatus: "linked",
      effectiveDate: pending.effectiveStartDate,
      ...(!omitFromEffectiveStartDate
        ? { fromEffectiveStartDate: fromEffectiveStartDate ?? pending.effectiveStartDate }
        : {}),
      changedAt: serverTimestamp(),
      changedBy: studentUid,
    });
    if (
      resolveMatchingJoinRequest
      && requestSnapshot.exists()
      && requestSnapshot.data().status === "pending"
      && requestSnapshot.data().email === pending.email
      && requestSnapshot.data().studentCode === pending.studentCode
      && requestSnapshot.data().subject === pending.subject
      && requestSnapshot.data().group === pending.group
      && requestSnapshot.data().period === pending.period
    ) {
      transaction.update(requestRef, {
        status: "approved",
        decidedBy: pending.ownerUid,
        decidedAt: serverTimestamp(),
        rejectionReason: null,
      });
    }
    return "linked";
  });
}

async function enrollManuallyAndReconcilePending(
  db,
  courseId,
  studentUid,
  email,
  operationId,
) {
  const courseRef = doc(db, "courses", courseId);
  const directoryRef = doc(db, "student_directory", email);
  const pendingRef = doc(db, "courses", courseId, "pending_enrollments", email);
  const enrollmentRef = doc(db, "courses", courseId, "enrollments", studentUid);
  const requestRef = doc(db, "courses", courseId, "join_requests", studentUid);
  const eventRef = doc(
    db,
    "courses",
    courseId,
    "pending_enrollments",
    email,
    "status_events",
    operationId,
  );
  return runTransaction(db, async (transaction) => {
    const [courseSnapshot, directorySnapshot, pendingSnapshot, enrollmentSnapshot, requestSnapshot] = await Promise.all([
      transaction.get(courseRef),
      transaction.get(directoryRef),
      transaction.get(pendingRef),
      transaction.get(enrollmentRef),
      transaction.get(requestRef),
    ]);
    if (!courseSnapshot.exists() || !directorySnapshot.exists() || !pendingSnapshot.exists()) {
      throw new Error("missing-reconcile-source");
    }
    if (enrollmentSnapshot.exists()) return "already-enrolled";
    const course = courseSnapshot.data();
    const pending = pendingSnapshot.data();
    const directory = directorySnapshot.data();
    const studentRequest = requestSnapshot.data();
    transaction.set(enrollmentRef, enrollmentData(
      studentUid,
      course.ownerUid,
      email,
      {
        name: pending.name,
        email: pending.email,
        studentCode: pending.studentCode,
      },
      {
        subject: pending.subject,
        group: pending.group,
        period: pending.period,
        effectiveStartDate: pending.effectiveStartDate,
      },
    ));
    transaction.update(pendingRef, {
      status: "linked",
      studentUid,
      linkedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      lastEventId: operationId,
      lastStatusChangedAt: serverTimestamp(),
    });
    transaction.set(eventRef, {
      fromStatus: pending.status,
      toStatus: "linked",
      effectiveDate: pending.effectiveStartDate,
      fromEffectiveStartDate: pending.effectiveStartDate,
      changedAt: serverTimestamp(),
      changedBy: course.ownerUid,
    });
    if (requestSnapshot.exists() && studentRequest.status === "pending") {
      transaction.update(requestRef, {
        status: "approved",
        decidedBy: course.ownerUid,
        decidedAt: serverTimestamp(),
        rejectionReason: null,
      });
    }
    return directory.uid;
  });
}

function courseInviteData(courseId, course = courseData(), extra = {}) {
  return {
    courseId,
    subject: course.subject,
    group: course.group,
    period: course.period,
    createdAt: serverTimestamp(),
    ...extra,
  };
}

function joinRequestData(studentUid, email, code, extra = {}) {
  const studentProfile = profile(email);
  return {
    studentUid,
    name: studentProfile.name,
    email: studentProfile.email,
    studentCode: studentProfile.studentCode,
    subject: "Bases de Datos",
    group: "Grupo 2",
    period: "2027-1",
    invitationCode: code,
    status: "pending",
    createdAt: serverTimestamp(),
    decidedBy: null,
    decidedAt: null,
    rejectionReason: null,
    ...extra,
  };
}

async function createInvitationAtomically(db, courseId, code, validForSeconds = 1209600) {
  const courseRef = doc(db, "courses", courseId);
  const currentRef = doc(db, "courses", courseId, "invitation", "current");
  const inviteRef = doc(db, "course_invites", code);
  return runTransaction(db, async (transaction) => {
    const [course, current] = await Promise.all([
      transaction.get(courseRef),
      transaction.get(currentRef),
    ]);
    if (!course.exists()) throw new Error("missing-course");
    const currentData = {
      code,
      status: "active",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      validForSeconds,
    };
    transaction.set(currentRef, currentData);
    transaction.set(inviteRef, courseInviteData(courseId, course.data()));
    return currentData;
  });
}

async function renewInvitationAtomically(db, courseId, code, validForSeconds = 1209600) {
  const currentRef = doc(db, "courses", courseId, "invitation", "current");
  const inviteRef = doc(db, "course_invites", code);
  const courseRef = doc(db, "courses", courseId);
  return runTransaction(db, async (transaction) => {
    const [course, current] = await Promise.all([
      transaction.get(courseRef),
      transaction.get(currentRef),
    ]);
    if (!course.exists() || !current.exists()) throw new Error("missing-invite");
    transaction.set(currentRef, {
      code,
      status: "active",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      validForSeconds,
    });
    transaction.set(inviteRef, courseInviteData(courseId, course.data()));
    return "renewed";
  });
}

async function changeInvitationAtomically(db, courseId, change) {
  const courseRef = doc(db, "courses", courseId);
  const currentRef = doc(db, "courses", courseId, "invitation", "current");
  return runTransaction(db, async (transaction) => {
    const course = await transaction.get(courseRef);
    const current = await transaction.get(currentRef);
    if (!course.exists() || !current.exists()) throw new Error("missing-invitation");
    transaction.update(currentRef, { ...change, updatedAt: serverTimestamp() });
  });
}

async function submitJoinRequestAtomically(db, courseId, studentUid, code) {
  const inviteRef = doc(db, "course_invites", code);
  const enrollmentRef = doc(db, "courses", courseId, "enrollments", studentUid);
  const requestRef = doc(db, "courses", courseId, "join_requests", studentUid);
  const profileRef = doc(db, "users", studentUid);
  return runTransaction(db, async (transaction) => {
    const [invite, enrollment, existing, studentProfile] = await Promise.all([
      transaction.get(inviteRef),
      transaction.get(enrollmentRef),
      transaction.get(requestRef),
      transaction.get(profileRef),
    ]);
    if (!invite.exists()) throw new Error("invite-unavailable");
    if (enrollment.exists()) return "already-enrolled";
    if (existing.exists()) return existing.data().status;
    transaction.set(
      requestRef,
      joinRequestData(studentUid, studentProfile.data().email, code, {
        subject: invite.data().subject,
        group: invite.data().group,
        period: invite.data().period,
      }),
    );
    return "created";
  });
}

async function decideJoinRequestAtomically(
  db,
  courseId,
  studentUid,
  deciderUid,
  { status, reason = null } = {},
) {
  const courseRef = doc(db, "courses", courseId);
  const requestRef = doc(db, "courses", courseId, "join_requests", studentUid);
  const enrollmentRef = doc(db, "courses", courseId, "enrollments", studentUid);
  return runTransaction(db, async (transaction) => {
    const [course, request, enrollment] = await Promise.all([
      transaction.get(courseRef),
      transaction.get(requestRef),
      transaction.get(enrollmentRef),
    ]);
    if (!course.exists() || !request.exists()) throw new Error("missing-request");
    if (request.data().status !== "pending") return "already-resolved";
    if (status === "approved" && !enrollment.exists()) {
      transaction.set(enrollmentRef, {
        studentUid,
        ownerUid: course.data().ownerUid,
        name: request.data().name,
        email: request.data().email,
        studentCode: request.data().studentCode,
        subject: course.data().subject,
        group: course.data().group,
        period: course.data().period,
        status: "active",
        createdAt: serverTimestamp(),
        rosterEntryId: request.data().email,
        effectiveStartDate: course.data().startDate,
      });
    }
    transaction.update(requestRef, {
      status,
      decidedBy: deciderUid,
      decidedAt: serverTimestamp(),
      rejectionReason: reason,
    });
    return status;
  });
}

async function enrollManuallyAndResolvePending(db, courseId, studentUid, email) {
  const courseRef = doc(db, "courses", courseId);
  const directoryRef = doc(db, "student_directory", email);
  const enrollmentRef = doc(db, "courses", courseId, "enrollments", studentUid);
  const requestRef = doc(db, "courses", courseId, "join_requests", studentUid);
  return runTransaction(db, async (transaction) => {
    const [course, directory, enrollment, request] = await Promise.all([
      transaction.get(courseRef),
      transaction.get(directoryRef),
      transaction.get(enrollmentRef),
      transaction.get(requestRef),
    ]);
    if (!course.exists() || !directory.exists()) throw new Error("missing-source");
    if (enrollment.exists()) return "already-enrolled";
    const directoryEntry = directory.data();
    transaction.set(enrollmentRef, enrollmentData(
      studentUid,
      course.data().ownerUid,
      email,
      {
        name: directoryEntry.name,
        email: directoryEntry.email,
        studentCode: directoryEntry.studentCode,
      },
      {
        subject: course.data().subject,
        group: course.data().group,
        period: course.data().period,
      },
    ));
    if (request.exists() && request.data().status === "pending") {
      transaction.update(requestRef, {
        status: "approved",
        decidedBy: "teacher-a",
        decidedAt: serverTimestamp(),
        rejectionReason: null,
      });
    }
    return "created";
  });
}

async function seedInvitationDisabled(courseId, code, { createdAt, status = "active" } = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const courseSnapshot = await getDoc(doc(db, "courses", courseId));
    const timestamp = createdAt ?? Timestamp.now();
    await setDoc(doc(db, "courses", courseId, "invitation", "current"), {
      code,
      status,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    await setDoc(doc(db, "course_invites", code), {
      courseId,
      subject: courseSnapshot.data().subject,
      group: courseSnapshot.data().group,
      period: courseSnapshot.data().period,
      createdAt: timestamp,
    });
  });
}

async function enrollIdempotently(db, courseId, studentUid, payload) {
  const enrollmentRef = doc(db, "courses", courseId, "enrollments", studentUid);
  const directoryRef = doc(db, "student_directory", payload.email);
  const courseRef = doc(db, "courses", courseId);
  return runTransaction(db, async (transaction) => {
    const [course, directory, existing] = await Promise.all([
      transaction.get(courseRef),
      transaction.get(directoryRef),
      transaction.get(enrollmentRef),
    ]);
    if (!course.exists() || !directory.exists()) throw new Error("missing-source");
    if (existing.exists()) return "already-enrolled";
    transaction.set(enrollmentRef, payload);
    return "created";
  });
}

async function changeEnrollmentStatusAtomically(
  db,
  courseId,
  studentUid,
  operationId,
  nextStatus,
  { changedBy = "teacher", eventPatch = {}, enrollmentPatch = {} } = {},
) {
  const enrollmentRef = doc(db, "courses", courseId, "enrollments", studentUid);
  const eventRef = doc(
    db,
    "courses",
    courseId,
    "enrollments",
    studentUid,
    "status_events",
    operationId,
  );
  return runTransaction(db, async (transaction) => {
    const enrollmentSnapshot = await transaction.get(enrollmentRef);
    if (!enrollmentSnapshot.exists()) throw new Error("missing-enrollment");
    const currentEnrollment = enrollmentSnapshot.data();
    const currentStatus = currentEnrollment.status;
    const effectiveDate = eventPatch.effectiveDate
      ?? currentEnrollment.effectiveStartDate
      ?? bogotaToday();
    transaction.update(enrollmentRef, {
      status: nextStatus,
      lastStatusEventId: operationId,
      lastStatusChangedAt: serverTimestamp(),
      ...enrollmentPatch,
    });
    transaction.set(eventRef, {
      fromStatus: currentStatus,
      toStatus: nextStatus,
      effectiveDate,
      changedAt: serverTimestamp(),
      changedBy,
      ...eventPatch,
    });
    return nextStatus;
  });
}

async function seedTeacherAccessRequest(uid, profileData, extraFields = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "teacher_access_requests", uid),
      {
        uid,
        name: profileData.name,
        email: profileData.email,
        studentCode: profileData.studentCode,
        status: "pending",
        createdAt: Timestamp.fromMillis(1_700_000_000_000),
        decidedBy: null,
        decidedAt: null,
        rejectionReason: null,
        ...extraFields,
      },
    );
  });
}

function courseBlock({
  id = "block_20270104_00001",
  weekday = 1,
  startTime = "08:00",
  endTime = "09:30",
  room = "Aula 101",
} = {}) {
  return { id, weekday, startTime, endTime, room };
}

function courseData(uid, { blocks = [courseBlock()], extraFields = {} } = {}) {
  return {
    ownerUid: uid,
    subject: "Bases de Datos",
    group: "Grupo 2",
    period: "2027-1",
    program: "Ingeniería de Sistemas",
    timezone: "America/Bogota",
    startDate: Timestamp.fromDate(new Date("2027-01-04T00:00:00.000Z")),
    endDate: Timestamp.fromDate(new Date("2027-01-31T00:00:00.000Z")),
    weeklyBlockIds: blocks.map((block) => block.id),
    status: "planned",
    schemaVersion: 1,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extraFields,
  };
}

function courseBlockDocument(block, order, extraFields = {}) {
  const toMinutes = (value) => {
    const [hours, minutes] = value.split(":").map(Number);
    return hours * 60 + minutes;
  };
  return {
    weekday: block.weekday,
    startMinute: toMinutes(block.startTime),
    endMinute: toMinutes(block.endTime),
    room: block.room,
    order,
    ...extraFields,
  };
}

async function createCourseAtomically(
  db,
  reference,
  payload,
  blocks,
  {
    omitOrders = [],
    childOverrides = {},
    extraChildren = [],
    omitAttendanceConfig = false,
    attendanceMode = "meeting",
  } = {},
) {
  return runTransaction(db, async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists()) throw new Error("course-already-exists");
    transaction.set(reference, payload);
    if (!omitAttendanceConfig) {
      transaction.set(doc(
        db,
        "courses",
        reference.id,
        "attendance_config",
        "current",
      ), attendanceConfigData(payload.ownerUid, attendanceMode));
    }
    const writtenBlockIds = new Set();
    blocks.forEach((block, order) => {
      if (omitOrders.includes(order) || writtenBlockIds.has(block.id)) return;
      writtenBlockIds.add(block.id);
      transaction.set(
        doc(db, "courses", reference.id, "weekly_blocks", block.id),
        courseBlockDocument(block, order, childOverrides[order] ?? {}),
      );
    });
    for (const child of extraChildren) {
      transaction.set(
        doc(db, "courses", reference.id, "weekly_blocks", child.id),
        child.data,
      );
    }
    return "created";
  });
}

function attendanceConfigData(uid, mode = "meeting") {
  return {
    schemaVersion: 1,
    mode,
    sessionCount: 0,
    createdAt: serverTimestamp(),
    createdBy: uid,
    updatedAt: serverTimestamp(),
    updatedBy: uid,
    lastSessionId: null,
  };
}

async function writeCourse(db, courseId, uid, options = {}) {
  const {
    blocks = [courseBlock()],
    extraFields = {},
    ...writeOptions
  } = options;
  return createCourseAtomically(
    db,
    doc(db, "courses", courseId),
    courseData(uid, { blocks, extraFields }),
    blocks,
    writeOptions,
  );
}

function firestoreValueEqual(left, right) {
  if (left instanceof Timestamp && right instanceof Timestamp) {
    return left.isEqual(right);
  }
  if (Array.isArray(left) && Array.isArray(right)) {
    return (
      left.length === right.length &&
      left.every((value, index) => firestoreValueEqual(value, right[index]))
    );
  }
  if (
    left &&
    right &&
    typeof left === "object" &&
    typeof right === "object"
  ) {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    return (
      leftKeys.length === rightKeys.length &&
      leftKeys.every(
        (key, index) =>
          key === rightKeys[index] &&
          firestoreValueEqual(left[key], right[key]),
      )
    );
  }
  return left === right;
}

async function createCourseIdempotently(db, reference, payload, blocks) {
  return runTransaction(db, async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists()) {
      const stored = existing.data();
      const storedBlockIds = stored.weeklyBlockIds;
      const childSnapshots = [];
      for (const blockId of storedBlockIds) {
        childSnapshots.push(
          await transaction.get(
            doc(db, "courses", reference.id, "weekly_blocks", blockId),
          ),
        );
      }
      const comparableKeys = [
        "subject",
        "group",
        "period",
        "program",
        "timezone",
        "startDate",
        "endDate",
        "weeklyBlockIds",
        "status",
        "schemaVersion",
      ];
      if (
        stored.ownerUid !== payload.ownerUid ||
        comparableKeys.some((key) => !firestoreValueEqual(stored[key], payload[key]))
      ) {
        throw new Error("idempotency-conflict");
      }
      for (let order = 0; order < payload.weeklyBlockIds.length; order++) {
        const blockId = payload.weeklyBlockIds[order];
        const child = childSnapshots[order];
        if (
          !child.exists() ||
          !firestoreValueEqual(
            child.data(),
            courseBlockDocument(blocks[order], order),
          )
        ) {
          throw new Error("idempotency-conflict");
        }
      }
      return "already-created";
    }

    const childSnapshots = [];
    for (const block of blocks) {
      childSnapshots.push(
        await transaction.get(
          doc(db, "courses", reference.id, "weekly_blocks", block.id),
        ),
      );
    }
    if (childSnapshots.some((child) => child.exists())) {
      throw new Error("idempotency-conflict");
    }

    transaction.set(reference, payload);
    blocks.forEach((block, order) => {
      transaction.set(
        doc(db, "courses", reference.id, "weekly_blocks", block.id),
        courseBlockDocument(block, order),
      );
    });
    return "created";
  });
}

async function createOwnTeacherAccessRequest(uid, email) {
  const db = userContext(uid, email, true);
  const ownProfile = profile(email);
  await assertSucceeds(setDoc(doc(db, "users", uid), ownProfile));
  await assertSucceeds(
    setDoc(
      doc(db, "teacher_access_requests", uid),
      teacherAccessRequest(uid, ownProfile),
    ),
  );
  return { db, ownProfile };
}

function adminDecision(status, adminUid, rejectionReason = null) {
  return {
    status,
    decidedBy: adminUid,
    decidedAt: serverTimestamp(),
    rejectionReason,
  };
}

before(async () => {
  const rules = await readFile(rulesPath, "utf8");
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: emulatorHost,
      port: Number(emulatorPort),
      rules,
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

after(async () => {
  await testEnvironment?.cleanup();
});

test("sin sesión se rechaza la lectura y escritura de perfiles y registros", async () => {
  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  const profileRef = doc(anonymous, "users", "alice");
  const recordRef = doc(anonymous, "users", "alice", "demo_records", "r1");

  await assertFails(getDoc(profileRef));
  await assertFails(setDoc(profileRef, profile("alice@example.test")));
  await assertFails(getDoc(recordRef));
  await assertFails(setDoc(recordRef, demoRecord()));
});

test("permite crear y leer el perfil propio antes de verificar el correo", async () => {
  const db = userContext("alice", "alice@example.test");
  const profileRef = doc(db, "users", "alice");

  await assertSucceeds(
    setDoc(profileRef, profile("alice@example.test")),
  );
  const snapshot = await assertSucceeds(getDoc(profileRef));
  assert.equal(snapshot.data().roles[0], "student");
});

test("rechaza la lectura directa y la lista de perfiles ajenos", async () => {
  const alice = userContext("alice", "alice@example.test");
  await assertSucceeds(
    setDoc(doc(alice, "users", "alice"), profile("alice@example.test")),
  );

  const bob = userContext("bob", "bob@example.test", true);
  await assertFails(getDoc(doc(bob, "users", "alice")));
  await assertFails(getDocs(collection(bob, "users")));
});

for (const role of ["teacher", "admin"]) {
  test(`rechaza crear un perfil inicial con rol ${role}`, async () => {
    const db = userContext("alice", "alice@example.test");
    await assertFails(
      setDoc(
        doc(db, "users", "alice"),
        profile("alice@example.test", [role]),
      ),
    );
  });

  test(`rechaza cambiar el rol propio a ${role}`, async () => {
    const db = userContext("alice", "alice@example.test");
    const profileRef = doc(db, "users", "alice");
    await assertSucceeds(
      setDoc(profileRef, profile("alice@example.test")),
    );

    await assertFails(updateDoc(profileRef, { roles: ["student", role] }));
  });
}

test("el correo del perfil debe coincidir con el correo del token al crear", async () => {
  const db = userContext("alice", "alice@example.test");
  await assertFails(
    setDoc(
      doc(db, "users", "alice"),
      profile("otro-correo@example.test"),
    ),
  );
});

test("el correo actualizado debe coincidir con el token verificado", async () => {
  const db = userContext("alice", "alice@example.test", true);
  const profileRef = doc(db, "users", "alice");
  await assertSucceeds(
    setDoc(profileRef, profile("alice@example.test")),
  );

  await assertFails(updateDoc(profileRef, { email: "otro@example.test" }));
});

test("permite CRUD propio verificado con serverTimestamp", async () => {
  const db = userContext("alice", "alice@example.test", true);
  const recordRef = doc(db, "users", "alice", "demo_records", "r1");

  await assertSucceeds(setDoc(recordRef, demoRecord()));
  const created = await assertSucceeds(getDoc(recordRef));
  assert.equal(created.data().title, "Registro de prueba");
  assert.ok(created.data().createdAt instanceof Timestamp);
  assert.ok(created.data().updatedAt instanceof Timestamp);

  const ownRecords = await assertSucceeds(
    getDocs(collection(db, "users", "alice", "demo_records")),
  );
  assert.equal(ownRecords.size, 1);

  await assertSucceeds(
    updateDoc(recordRef, {
      title: "Registro editado",
      description: "Descripción editada",
      updatedAt: serverTimestamp(),
    }),
  );
  const updated = await assertSucceeds(getDoc(recordRef));
  assert.equal(updated.data().title, "Registro editado");
  assert.deepEqual(updated.data().createdAt, created.data().createdAt);
  assert.ok(updated.data().updatedAt instanceof Timestamp);

  await assertSucceeds(deleteDoc(recordRef));
  const deleted = await assertSucceeds(getDoc(recordRef));
  assert.equal(deleted.exists(), false);
});

test("rechaza CRUD de registros propios mientras el correo no está verificado", async () => {
  await seedDemoRecord("alice");
  const db = userContext("alice", "alice@example.test");
  const recordRef = doc(db, "users", "alice", "demo_records", "record-1");

  await assertFails(getDoc(recordRef));
  await assertFails(getDocs(collection(db, "users", "alice", "demo_records")));
  await assertFails(
    setDoc(doc(db, "users", "alice", "demo_records", "new-record"), demoRecord()),
  );
  await assertFails(
    updateDoc(recordRef, {
      title: "Edición sin verificar",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(recordRef));
});

test("rechaza leer, listar y modificar registros bajo el UID de otra persona", async () => {
  const alice = userContext("alice", "alice@example.test", true);
  const aliceRecord = doc(alice, "users", "alice", "demo_records", "r1");
  await assertSucceeds(setDoc(aliceRecord, demoRecord()));

  const bob = userContext("bob", "bob@example.test", true);
  const foreignRecord = doc(bob, "users", "alice", "demo_records", "r1");
  await assertFails(getDoc(foreignRecord));
  await assertFails(
    getDocs(collection(bob, "users", "alice", "demo_records")),
  );
  await assertFails(
    setDoc(
      doc(bob, "users", "alice", "demo_records", "bob-record"),
      demoRecord(),
    ),
  );
  await assertFails(
    updateDoc(foreignRecord, {
      title: "Cambio ajeno",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(foreignRecord));
});

test("rechaza campos no permitidos en perfiles y registros", async () => {
  const db = userContext("alice", "alice@example.test", true);
  await assertFails(
    setDoc(
      doc(db, "users", "alice"),
      profile("alice@example.test", ["student"], { isAdmin: true }),
    ),
  );

  await assertFails(
    setDoc(
      doc(db, "users", "alice", "demo_records", "extra-field"),
      demoRecord({ ownerUid: "alice" }),
    ),
  );

  const recordRef = doc(db, "users", "alice", "demo_records", "r1");
  await assertSucceeds(setDoc(recordRef, demoRecord()));
  await assertFails(
    updateDoc(recordRef, {
      ownerUid: "alice",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("rechaza modificar createdAt al editar un registro", async () => {
  const db = userContext("alice", "alice@example.test", true);
  const recordRef = doc(db, "users", "alice", "demo_records", "r1");
  await assertSucceeds(setDoc(recordRef, demoRecord()));
  const created = await assertSucceeds(getDoc(recordRef));

  await assertFails(
    updateDoc(recordRef, {
      createdAt: Timestamp.fromMillis(1),
      updatedAt: serverTimestamp(),
    }),
  );
  const afterRejectedUpdate = await assertSucceeds(getDoc(recordRef));
  assert.deepEqual(afterRejectedUpdate.data().createdAt, created.data().createdAt);
});

test("un usuario verificado puede crear y consultar solo su solicitud propia", async () => {
  const { db, ownProfile } = await createOwnTeacherAccessRequest(
    "applicant",
    "applicant@example.test",
  );
  const requestRef = doc(db, "teacher_access_requests", "applicant");
  const ownRequest = await assertSucceeds(getDoc(requestRef));

  assert.equal(ownRequest.data().uid, "applicant");
  assert.equal(ownRequest.data().name, ownProfile.name);
  assert.equal(ownRequest.data().email, ownProfile.email);
  assert.equal(ownRequest.data().studentCode, ownProfile.studentCode);
  assert.equal(ownRequest.data().status, "pending");
  assert.ok(ownRequest.data().createdAt instanceof Timestamp);
  assert.equal(ownRequest.data().decidedBy, null);
  assert.equal(ownRequest.data().decidedAt, null);
  assert.equal(ownRequest.data().rejectionReason, null);

  await assertFails(getDocs(collection(db, "teacher_access_requests")));
  await assertFails(deleteDoc(requestRef));

  const nullableCodeUid = "without-student-code";
  const nullableCodeEmail = "without-code@example.test";
  const nullableCodeDb = userContext(
    nullableCodeUid,
    nullableCodeEmail,
    true,
  );
  const nullableCodeProfile = profile(nullableCodeEmail, ["student"], {
    studentCode: null,
  });
  await assertSucceeds(
    setDoc(doc(nullableCodeDb, "users", nullableCodeUid), nullableCodeProfile),
  );
  await assertSucceeds(
    setDoc(
      doc(nullableCodeDb, "teacher_access_requests", nullableCodeUid),
      teacherAccessRequest(nullableCodeUid, nullableCodeProfile),
    ),
  );
});

test("crear solicitud exige sesión verificada, perfil, rol sin teacher y snapshot exacto", async () => {
  const unverified = userContext("unverified", "unverified@example.test");
  const unverifiedProfile = profile("unverified@example.test");
  await assertSucceeds(
    setDoc(doc(unverified, "users", "unverified"), unverifiedProfile),
  );
  await assertFails(
    setDoc(
      doc(unverified, "teacher_access_requests", "unverified"),
      teacherAccessRequest("unverified", unverifiedProfile),
    ),
  );

  const noProfile = userContext("missing-profile", "missing@example.test", true);
  await assertFails(
    setDoc(
      doc(noProfile, "teacher_access_requests", "missing-profile"),
      teacherAccessRequest(
        "missing-profile",
        profile("missing@example.test"),
      ),
    ),
  );

  const teacherUid = "already-teacher";
  const teacherEmail = "teacher@example.test";
  const teacherProfile = profile(teacherEmail, ["student", "teacher"]);
  await seedProfile(teacherUid, teacherEmail, ["student", "teacher"]);
  const teacher = userContext(teacherUid, teacherEmail, true);
  await assertFails(
    setDoc(
      doc(teacher, "teacher_access_requests", teacherUid),
      teacherAccessRequest(teacherUid, teacherProfile),
    ),
  );

  const changedSnapshot = userContext("changed", "changed@example.test", true);
  const actualProfile = profile("changed@example.test");
  await assertSucceeds(
    setDoc(doc(changedSnapshot, "users", "changed"), actualProfile),
  );
  await assertFails(
    setDoc(
      doc(changedSnapshot, "teacher_access_requests", "changed"),
      teacherAccessRequest("changed", {
        ...actualProfile,
        name: "Nombre alterado",
      }),
    ),
  );
});

test("crear solicitud rechaza extras, UID ajeno, decisión inicial o timestamp del cliente", async () => {
  const uid = "invalid-request";
  const email = "invalid@example.test";
  const db = userContext(uid, email, true);
  const ownProfile = profile(email);
  await assertSucceeds(setDoc(doc(db, "users", uid), ownProfile));
  const requestRef = doc(db, "teacher_access_requests", uid);

  await assertFails(
    setDoc(
      requestRef,
      teacherAccessRequest(uid, ownProfile, { extra: "no permitido" }),
    ),
  );
  await assertFails(
    setDoc(
      requestRef,
      teacherAccessRequest(uid, ownProfile, { uid: "another-user" }),
    ),
  );
  await assertFails(
    setDoc(
      requestRef,
      teacherAccessRequest(uid, ownProfile, { status: "approved" }),
    ),
  );
  await assertFails(
    setDoc(
      requestRef,
      teacherAccessRequest(uid, ownProfile, { decidedBy: "admin" }),
    ),
  );
  await assertFails(
    setDoc(
      requestRef,
      teacherAccessRequest(uid, ownProfile, {
        createdAt: Timestamp.fromMillis(1_700_000_000_000),
      }),
    ),
  );
});

test("solicitudes no se pueden duplicar, sobrescribir ni decidir por el propietario", async () => {
  const uid = "duplicate";
  const email = "duplicate@example.test";
  const { db, ownProfile } = await createOwnTeacherAccessRequest(uid, email);
  const requestRef = doc(db, "teacher_access_requests", uid);

  await assertFails(
    setDoc(
      requestRef,
      teacherAccessRequest(uid, ownProfile, { status: "rejected" }),
    ),
  );
  await assertFails(
    updateDoc(requestRef, {
      status: "rejected",
      decidedBy: uid,
      decidedAt: serverTimestamp(),
      rejectionReason: "Motivo",
    }),
  );
});

test("admin verificado puede listar solicitudes pendientes con el índice y sigue sin listar users", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const firstProfile = profile("first@example.test");
  const secondProfile = profile("second@example.test");
  await seedTeacherAccessRequest("first", firstProfile);
  await seedTeacherAccessRequest("second", secondProfile, {
    createdAt: Timestamp.fromMillis(1_700_000_001_000),
  });
  await seedTeacherAccessRequest("resolved", profile("resolved@example.test"), {
    status: "rejected",
    decidedBy: "admin",
    decidedAt: Timestamp.fromMillis(1_700_000_002_000),
    rejectionReason: "Solicitud resuelta",
  });

  const admin = userContext("admin", "admin@example.test", true);
  const requests = await assertSucceeds(
    getDocs(
      query(
        collection(admin, "teacher_access_requests"),
        where("status", "==", "pending"),
        orderBy("createdAt", "asc"),
      ),
    ),
  );
  assert.equal(requests.size, 2);
  assert.equal(requests.docs[0].id, "first");
  assert.equal(requests.docs[1].id, "second");
  await assertSucceeds(
    getDoc(doc(admin, "teacher_access_requests", "first")),
  );
  await assertFails(
    getDoc(doc(admin, "teacher_access_requests", "resolved")),
  );
  await assertFails(getDocs(collection(admin, "teacher_access_requests")));
  await assertFails(getDocs(collection(admin, "users")));
});

test("admin solo puede obtener perfiles vinculados a una solicitud pendiente y coincidente", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);

  const pendingUid = "pending-profile";
  const pendingEmail = "pending-profile@example.test";
  const pendingProfile = profile(pendingEmail);
  await seedProfile(pendingUid, pendingEmail);
  await seedTeacherAccessRequest(pendingUid, pendingProfile);

  const noRequestUid = "profile-without-request";
  await seedProfile(noRequestUid, `${noRequestUid}@example.test`);

  const resolvedUid = "profile-with-resolved-request";
  const resolvedProfile = profile(`${resolvedUid}@example.test`);
  await seedProfile(resolvedUid, resolvedProfile.email);
  await seedTeacherAccessRequest(resolvedUid, resolvedProfile, {
    status: "approved",
    decidedBy: "admin",
    decidedAt: Timestamp.fromMillis(1_700_000_000_000),
  });

  const mismatchedUid = "profile-with-mismatched-request";
  const mismatchedProfile = profile(`${mismatchedUid}@example.test`);
  await seedProfile(mismatchedUid, mismatchedProfile.email);
  await seedTeacherAccessRequest(mismatchedUid, mismatchedProfile, {
    uid: "another-user",
  });

  const admin = userContext("admin", "admin@example.test", true);
  await assertSucceeds(getDoc(doc(admin, "users", "admin")));
  const pendingSnapshot = await assertSucceeds(
    getDoc(doc(admin, "users", pendingUid)),
  );
  assert.equal(pendingSnapshot.data().email, pendingEmail);
  await assertFails(getDoc(doc(admin, "users", noRequestUid)));
  await assertFails(getDoc(doc(admin, "users", resolvedUid)));
  await assertFails(getDoc(doc(admin, "users", mismatchedUid)));
  await assertFails(getDocs(collection(admin, "users")));
});

test("correo verificado sin rol admin no puede listar ni decidir solicitudes", async () => {
  await seedProfile("plain-user", "plain@example.test", ["student"]);
  await seedProfile("unverified-admin", "unverified-admin@example.test", ["admin"]);
  const targetProfile = profile("target@example.test");
  await seedProfile("target", targetProfile.email);
  await seedTeacherAccessRequest("target", targetProfile);

  const plainUser = userContext("plain-user", "plain@example.test", true);
  await assertFails(
    getDocs(collection(plainUser, "teacher_access_requests")),
  );
  await assertFails(
    getDoc(doc(plainUser, "teacher_access_requests", "target")),
  );
  await assertFails(
    updateDoc(
      doc(plainUser, "teacher_access_requests", "target"),
      adminDecision("rejected", "plain-user", "Motivo válido"),
    ),
  );

  const unverifiedAdmin = userContext(
    "unverified-admin",
    "unverified-admin@example.test",
    false,
  );
  await assertFails(
    getDocs(collection(unverifiedAdmin, "teacher_access_requests")),
  );
  await assertFails(
    getDoc(doc(unverifiedAdmin, "teacher_access_requests", "target")),
  );
});

test("una aprobación aislada o un cambio aislado de roles se rechazan", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const targetUid = "candidate";
  const targetEmail = "candidate@example.test";
  const targetProfile = profile(targetEmail);
  await seedProfile(targetUid, targetEmail);
  await seedTeacherAccessRequest(targetUid, targetProfile);

  const admin = userContext("admin", "admin@example.test", true);
  const requestRef = doc(admin, "teacher_access_requests", targetUid);
  const profileRef = doc(admin, "users", targetUid);

  await assertFails(
    updateDoc(
      requestRef,
      adminDecision("approved", "admin"),
    ),
  );
  await assertFails(updateDoc(profileRef, { roles: ["student", "teacher"] }));

  let stillPending;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    stillPending = await getDoc(
      doc(context.firestore(), "teacher_access_requests", targetUid),
    );
  });
  assert.equal(stillPending.data().status, "pending");
});

test("aprobación atómica agrega solo teacher y conserva roles y perfil", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const targetUid = "candidate";
  const targetEmail = "candidate@example.test";
  const targetProfile = profile(targetEmail, ["student", "admin"]);
  await seedProfile(targetUid, targetEmail, ["student", "admin"]);
  await seedTeacherAccessRequest(targetUid, targetProfile);

  const admin = userContext("admin", "admin@example.test", true);
  const batch = writeBatch(admin);
  batch.update(
    doc(admin, "teacher_access_requests", targetUid),
    adminDecision("approved", "admin"),
  );
  batch.update(doc(admin, "users", targetUid), {
    roles: ["student", "admin", "teacher"],
  });
  await assertSucceeds(batch.commit());

  let stored;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [savedProfile, savedRequest] = await Promise.all([
      getDoc(doc(db, "users", targetUid)),
      getDoc(doc(db, "teacher_access_requests", targetUid)),
    ]);
    stored = { profile: savedProfile.data(), request: savedRequest.data() };
  });
  assert.deepEqual(stored.profile.roles, ["student", "admin", "teacher"]);
  assert.equal(stored.profile.name, targetProfile.name);
  assert.equal(stored.profile.email, targetProfile.email);
  assert.equal(stored.profile.studentCode, targetProfile.studentCode);
  assert.equal(stored.request.status, "approved");
  assert.equal(stored.request.decidedBy, "admin");
  assert.ok(stored.request.decidedAt instanceof Timestamp);
  assert.equal(stored.request.rejectionReason, null);
});

test("transacción de aprobación confirma antes de perder lectura admin del detalle", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const targetUid = "approval-after-commit";
  const targetEmail = "approval-after-commit@example.test";
  const targetProfile = profile(targetEmail);
  await seedProfile(targetUid, targetEmail);
  await seedTeacherAccessRequest(targetUid, targetProfile);

  const admin = userContext("admin", "admin@example.test", true);
  const requestRef = doc(admin, "teacher_access_requests", targetUid);
  const profileRef = doc(admin, "users", targetUid);
  const committedStatus = await assertSucceeds(
    runTransaction(admin, async (transaction) => {
      const adminProfile = await transaction.get(doc(admin, "users", "admin"));
      const requestSnapshot = await transaction.get(requestRef);
      const requesterProfile = await transaction.get(profileRef);
      assert.equal(adminProfile.data().roles.includes("admin"), true);
      assert.equal(requestSnapshot.data().status, "pending");

      const roles = requesterProfile.data().roles;
      transaction.update(requestRef, adminDecision("approved", "admin"));
      transaction.update(profileRef, { roles: [...roles, "teacher"] });
      return "approved";
    }),
  );
  assert.equal(committedStatus, "approved");

  const pending = await assertSucceeds(
    getDocs(
      query(
        collection(admin, "teacher_access_requests"),
        where("status", "==", "pending"),
        orderBy("createdAt", "asc"),
      ),
    ),
  );
  assert.equal(pending.docs.some((request) => request.id === targetUid), false);
  await assertFails(getDoc(requestRef));

  const applicant = userContext(targetUid, targetEmail, true);
  const applicantRequest = await assertSucceeds(
    getDoc(doc(applicant, "teacher_access_requests", targetUid)),
  );
  const applicantProfile = await assertSucceeds(
    getDoc(doc(applicant, "users", targetUid)),
  );
  assert.equal(applicantRequest.data().status, "approved");
  assert.deepEqual(applicantProfile.data().roles, ["student", "teacher"]);
});

test("aprobación atómica rechaza roles añadidos o eliminados y self-approval", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const targetUid = "candidate";
  const targetEmail = "candidate@example.test";
  const targetProfile = profile(targetEmail);
  await seedProfile(targetUid, targetEmail);
  await seedTeacherAccessRequest(targetUid, targetProfile);

  const admin = userContext("admin", "admin@example.test", true);
  const requestRef = doc(admin, "teacher_access_requests", targetUid);
  const profileRef = doc(admin, "users", targetUid);
  const approvalWithReason = writeBatch(admin);
  approvalWithReason.update(
    requestRef,
    adminDecision("approved", "admin", "No debe incluir motivo"),
  );
  approvalWithReason.update(profileRef, { roles: ["student", "teacher"] });
  await assertFails(approvalWithReason.commit());

  const extraAdminRole = writeBatch(admin);
  extraAdminRole.update(requestRef, adminDecision("approved", "admin"));
  extraAdminRole.update(profileRef, {
    roles: ["student", "teacher", "admin"],
  });
  await assertFails(extraAdminRole.commit());

  const removedRole = writeBatch(admin);
  removedRole.update(requestRef, adminDecision("approved", "admin"));
  removedRole.update(profileRef, { roles: ["teacher"] });
  await assertFails(removedRole.commit());

  const selfUid = "self-admin";
  const selfEmail = "self-admin@example.test";
  await seedProfile(selfUid, selfEmail, ["admin"]);
  await seedTeacherAccessRequest(selfUid, profile(selfEmail, ["admin"]));
  const selfAdmin = userContext(selfUid, selfEmail, true);
  const selfBatch = writeBatch(selfAdmin);
  selfBatch.update(
    doc(selfAdmin, "teacher_access_requests", selfUid),
    adminDecision("approved", selfUid),
  );
  selfBatch.update(doc(selfAdmin, "users", selfUid), {
    roles: ["admin", "teacher"],
  });
  await assertFails(selfBatch.commit());
});

test("una solicitud no se aprueba si el perfil cambió desde su creación", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const targetUid = "changed-candidate";
  const targetEmail = "changed@example.test";
  const targetProfile = profile(targetEmail);
  const applicant = userContext(targetUid, targetEmail, true);
  await assertSucceeds(setDoc(doc(applicant, "users", targetUid), targetProfile));
  await assertSucceeds(
    setDoc(
      doc(applicant, "teacher_access_requests", targetUid),
      teacherAccessRequest(targetUid, targetProfile),
    ),
  );
  await assertSucceeds(
    updateDoc(doc(applicant, "users", targetUid), { name: "Nombre actualizado" }),
  );

  const admin = userContext("admin", "admin@example.test", true);
  const batch = writeBatch(admin);
  batch.update(
    doc(admin, "teacher_access_requests", targetUid),
    adminDecision("approved", "admin"),
  );
  batch.update(doc(admin, "users", targetUid), {
    roles: ["student", "teacher"],
  });
  await assertFails(batch.commit());
});

test("admin puede rechazar con motivo de 1 a 500 caracteres y no cambia roles", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const targetUid = "rejected-candidate";
  const targetEmail = "rejected@example.test";
  const targetProfile = profile(targetEmail);
  await seedProfile(targetUid, targetEmail);
  await seedTeacherAccessRequest(targetUid, targetProfile);

  const admin = userContext("admin", "admin@example.test", true);
  await assertSucceeds(
    updateDoc(
      doc(admin, "teacher_access_requests", targetUid),
      adminDecision("rejected", "admin", "Falta documentación"),
    ),
  );

  let stored;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [savedProfile, savedRequest] = await Promise.all([
      getDoc(doc(db, "users", targetUid)),
      getDoc(doc(db, "teacher_access_requests", targetUid)),
    ]);
    stored = { profile: savedProfile.data(), request: savedRequest.data() };
  });
  assert.deepEqual(stored.profile.roles, ["student"]);
  assert.equal(stored.request.status, "rejected");
  assert.equal(stored.request.decidedBy, "admin");
  assert.equal(stored.request.rejectionReason, "Falta documentación");
  assert.ok(stored.request.decidedAt instanceof Timestamp);
  await assertFails(
    updateDoc(
      doc(admin, "teacher_access_requests", targetUid),
      adminDecision("approved", "admin"),
    ),
  );
});

test("transacción de rechazo confirma antes de perder lectura admin del detalle", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const targetUid = "rejection-after-commit";
  const targetEmail = "rejection-after-commit@example.test";
  await seedProfile(targetUid, targetEmail);
  await seedTeacherAccessRequest(targetUid, profile(targetEmail));

  const admin = userContext("admin", "admin@example.test", true);
  const requestRef = doc(admin, "teacher_access_requests", targetUid);
  const profileRef = doc(admin, "users", targetUid);
  const committedStatus = await assertSucceeds(
    runTransaction(admin, async (transaction) => {
      const adminProfile = await transaction.get(doc(admin, "users", "admin"));
      const requestSnapshot = await transaction.get(requestRef);
      await transaction.get(profileRef);
      assert.equal(adminProfile.data().roles.includes("admin"), true);
      assert.equal(requestSnapshot.data().status, "pending");

      transaction.update(
        requestRef,
        adminDecision("rejected", "admin", "Falta documentación"),
      );
      return "rejected";
    }),
  );
  assert.equal(committedStatus, "rejected");

  const pending = await assertSucceeds(
    getDocs(
      query(
        collection(admin, "teacher_access_requests"),
        where("status", "==", "pending"),
        orderBy("createdAt", "asc"),
      ),
    ),
  );
  assert.equal(pending.docs.some((request) => request.id === targetUid), false);
  await assertFails(getDoc(requestRef));

  const applicant = userContext(targetUid, targetEmail, true);
  const applicantRequest = await assertSucceeds(
    getDoc(doc(applicant, "teacher_access_requests", targetUid)),
  );
  const applicantProfile = await assertSucceeds(
    getDoc(doc(applicant, "users", targetUid)),
  );
  assert.equal(applicantRequest.data().status, "rejected");
  assert.equal(applicantRequest.data().rejectionReason, "Falta documentación");
  assert.deepEqual(applicantProfile.data().roles, ["student"]);
});

test("una decisión de usuario sin rol admin se deniega y deja la solicitud pendiente", async () => {
  await seedProfile("ordinary-user", "ordinary@example.test", ["student"]);
  const targetUid = "denied-decision-target";
  const targetEmail = "denied-target@example.test";
  await seedProfile(targetUid, targetEmail);
  await seedTeacherAccessRequest(targetUid, profile(targetEmail));

  const ordinaryUser = userContext("ordinary-user", "ordinary@example.test", true);
  const requestRef = doc(ordinaryUser, "teacher_access_requests", targetUid);
  await assertFails(
    runTransaction(ordinaryUser, async (transaction) => {
      await transaction.get(doc(ordinaryUser, "users", "ordinary-user"));
      await transaction.get(requestRef);
      transaction.update(
        requestRef,
        adminDecision("rejected", "ordinary-user", "Motivo válido"),
      );
    }),
  );

  let storedRequest;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    storedRequest = await getDoc(
      doc(context.firestore(), "teacher_access_requests", targetUid),
    );
  });
  assert.equal(storedRequest.data().status, "pending");
  await assertFails(getDoc(requestRef));
});

test("rechazo exige motivo válido y no admite cambiar roles en la misma operación", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const admin = userContext("admin", "admin@example.test", true);
  const candidates = [
    { uid: "missing-reason", reason: null },
    { uid: "empty-reason", reason: "" },
    { uid: "long-reason", reason: "x".repeat(501) },
  ];

  for (const candidate of candidates) {
    const email = `${candidate.uid}@example.test`;
    const candidateProfile = profile(email);
    await seedProfile(candidate.uid, email);
    await seedTeacherAccessRequest(candidate.uid, candidateProfile);
    await assertFails(
      updateDoc(
        doc(admin, "teacher_access_requests", candidate.uid),
        adminDecision("rejected", "admin", candidate.reason),
      ),
    );
  }

  const withMaximumReason = "maximum-reason";
  const maximumProfile = profile(`${withMaximumReason}@example.test`);
  await seedProfile(withMaximumReason, maximumProfile.email);
  await seedTeacherAccessRequest(withMaximumReason, maximumProfile);
  await assertSucceeds(
    updateDoc(
      doc(admin, "teacher_access_requests", withMaximumReason),
      adminDecision("rejected", "admin", "x".repeat(500)),
    ),
  );

  const withMinimumReason = "minimum-reason";
  const minimumProfile = profile(`${withMinimumReason}@example.test`);
  await seedProfile(withMinimumReason, minimumProfile.email);
  await seedTeacherAccessRequest(withMinimumReason, minimumProfile);
  await assertSucceeds(
    updateDoc(
      doc(admin, "teacher_access_requests", withMinimumReason),
      adminDecision("rejected", "admin", "x"),
    ),
  );

  const atomicUid = "rejection-role-attack";
  const atomicProfile = profile(`${atomicUid}@example.test`);
  await seedProfile(atomicUid, atomicProfile.email);
  await seedTeacherAccessRequest(atomicUid, atomicProfile);
  const batch = writeBatch(admin);
  batch.update(
    doc(admin, "teacher_access_requests", atomicUid),
    adminDecision("rejected", "admin", "No cumple requisitos"),
  );
  batch.update(doc(admin, "users", atomicUid), {
    roles: ["student", "teacher"],
  });
  await assertFails(batch.commit());
});

test("la decisión conserva snapshot y creación, y solo el admin asignado puede decidir", async () => {
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedProfile("other-admin", "other-admin@example.test", ["admin"]);
  const targetUid = "immutable-request";
  const targetEmail = "immutable@example.test";
  const targetProfile = profile(targetEmail);
  await seedProfile(targetUid, targetEmail);
  await seedTeacherAccessRequest(targetUid, targetProfile);

  const admin = userContext("admin", "admin@example.test", true);
  const requestRef = doc(admin, "teacher_access_requests", targetUid);
  await assertFails(
    updateDoc(requestRef, {
      ...adminDecision("rejected", "admin", "Motivo válido"),
      name: "Snapshot alterado",
    }),
  );
  await assertFails(
    updateDoc(requestRef, {
      ...adminDecision("rejected", "admin", "Motivo válido"),
      createdAt: Timestamp.fromMillis(2_000_000_000_000),
    }),
  );
  await assertFails(
    updateDoc(requestRef, {
      ...adminDecision("rejected", "other-admin", "Motivo válido"),
    }),
  );

  const otherAdmin = userContext(
    "other-admin",
    "other-admin@example.test",
    true,
  );
  await assertFails(
    updateDoc(
      doc(otherAdmin, "teacher_access_requests", targetUid),
      adminDecision("rejected", "admin", "Motivo válido"),
    ),
  );
});

test("docente verificado crea su curso y puede leer IDs ausentes para idempotencia", async () => {
  const uid = "course-owner";
  await seedProfile(uid, "teacher@example.test", ["student", "teacher"]);
  const db = userContext(uid, "teacher@example.test", true);
  const missingCourseRef = doc(db, "courses", "missing-course-id");

  // The stable-ID transaction reads first so it can decide create vs retry.
  await assertSucceeds(getDoc(missingCourseRef));
  await assertSucceeds(writeCourse(db, missingCourseRef.id, uid));
  const ownCourse = await assertSucceeds(getDoc(missingCourseRef));
  assert.equal(ownCourse.data().ownerUid, uid);
  assert.equal(ownCourse.data().status, "planned");
  assert.equal(ownCourse.data().createdAt instanceof Timestamp, true);
  assert.equal(ownCourse.data().updatedAt instanceof Timestamp, true);
});

test("cursos rechaza sesión ausente, correo pendiente, estudiante y admin sin teacher", async () => {
  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, "courses", "missing")));
  await assertFails(
    setDoc(doc(anonymous, "courses", "anonymous-course"), courseData("anonymous")),
  );

  await seedProfile("unverified", "unverified@example.test", ["teacher"]);
  const unverified = userContext("unverified", "unverified@example.test", false);
  await assertFails(getDoc(doc(unverified, "courses", "missing")));
  await assertFails(
    setDoc(
      doc(unverified, "courses", "unverified-course"),
      courseData("unverified"),
    ),
  );

  await seedProfile("student", "student@example.test", ["student"]);
  const student = userContext("student", "student@example.test", true);
  await assertFails(getDoc(doc(student, "courses", "missing")));
  await assertFails(
    setDoc(doc(student, "courses", "student-course"), courseData("student")),
  );

  await seedProfile("admin-only", "admin@example.test", ["admin"]);
  const admin = userContext("admin-only", "admin@example.test", true);
  await assertFails(getDoc(doc(admin, "courses", "missing")));
  await assertFails(
    setDoc(
      doc(admin, "courses", "admin-course"),
      courseData("admin-only"),
    ),
  );

  await seedProfile("teacher-bad-email", "stored@example.test", ["teacher"]);
  const mismatchedTeacher = userContext(
    "teacher-bad-email",
    "token@example.test",
    true,
  );
  await assertFails(getDoc(doc(mismatchedTeacher, "courses", "missing")));

  await seedProfile("teacher-extra-field", "extra@example.test", ["teacher"], {
    unexpected: true,
  });
  const invalidProfileTeacher = userContext(
    "teacher-extra-field",
    "extra@example.test",
    true,
  );
  await assertFails(getDoc(doc(invalidProfileTeacher, "courses", "missing")));
});

test("course owner is derived from the authenticated UID and foreign courses stay private", async () => {
  const ownerUid = "course-owner";
  const otherUid = "other-teacher";
  await seedProfile(ownerUid, "owner@example.test", ["teacher"]);
  await seedProfile(otherUid, "other@example.test", ["teacher"]);
  await seedCourse(otherUid, "foreign-course-id");
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(
      doc(db, "courses", "orphan-course", "weekly_blocks", "block_20270104_00001"),
      courseBlockDocument(courseBlock(), 0),
    );
  });

  const owner = userContext(ownerUid, "owner@example.test", true);
  await assertFails(
    setDoc(
      doc(owner, "courses", "spoofed-owner-course"),
      courseData("someone-else"),
    ),
  );
  await assertFails(getDoc(doc(owner, "courses", "foreign-course-id")));
  await assertFails(
    getDoc(
      doc(
        owner,
        "courses",
        "foreign-course-id",
        "weekly_blocks",
        "block_20270104_00001",
      ),
    ),
  );
  await assertFails(
    getDoc(
      doc(
        owner,
        "courses",
        "orphan-course",
        "weekly_blocks",
        "block_20270104_00001",
      ),
    ),
  );
  await assertFails(getDocs(collection(owner, "courses")));

  await assertSucceeds(writeCourse(owner, "own-course-id", ownerUid));
  const ownOnlyQuery = query(
    collection(owner, "courses"),
    where("ownerUid", "==", ownerUid),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  );
  const ownCourses = await assertSucceeds(getDocs(ownOnlyQuery));
  assert.deepEqual(ownCourses.docs.map((course) => course.id), ["own-course-id"]);
  const ownBlocks = await assertSucceeds(
    getDocs(collection(owner, "courses", "own-course-id", "weekly_blocks")),
  );
  assert.equal(ownBlocks.size, 1);
  assert.equal(ownBlocks.docs[0].data().order, 0);
  await assertFails(
    getDoc(
      doc(
        owner,
        "courses",
        "own-course-id",
        "weekly_blocks",
        "missing-child-id-00001",
      ),
    ),
  );
  await assertSucceeds(
    getDoc(
      doc(owner, "courses", "absent-parent-id", "weekly_blocks", "missing-child-id-00001"),
    ),
  );

  await assertFails(
    updateDoc(doc(owner, "courses", "own-course-id"), {
      subject: "Modified",
    }),
  );
  await assertFails(deleteDoc(doc(owner, "courses", "own-course-id")));
});

test("course document accepts eight valid blocks and consecutive meetings", async () => {
  const uid = "max-block-teacher";
  await seedProfile(uid, "max@example.test", ["teacher"]);
  const db = userContext(uid, "max@example.test", true);
  const blocks = [
    courseBlock({ id: "block_20270104_00001", weekday: 1 }),
    courseBlock({
      id: "block_20270104_00002",
      weekday: 1,
      startTime: "09:30",
      endTime: "10:00",
    }),
    courseBlock({ id: "block_20270105_00001", weekday: 2 }),
    courseBlock({ id: "block_20270106_00001", weekday: 3 }),
    courseBlock({ id: "block_20270107_00001", weekday: 4 }),
    courseBlock({ id: "block_20270108_00001", weekday: 5 }),
    courseBlock({ id: "block_20270109_00001", weekday: 6 }),
    courseBlock({ id: "block_20270110_00001", weekday: 7 }),
  ];

  await assertSucceeds(
    writeCourse(db, "eight-weekly-block-course", uid, { blocks }),
  );
});

test("course creation requires every listed child and rejects malformed or extra children", async () => {
  const uid = "atomic-course-teacher";
  await seedProfile(uid, "atomic@example.test", ["teacher"]);
  const db = userContext(uid, "atomic@example.test", true);
  const blocks = [
    courseBlock({ id: "block_20270104_00001", weekday: 1 }),
    courseBlock({ id: "block_20270105_00001", weekday: 2 }),
  ];

  await assertFails(
    writeCourse(db, "incomplete-course-parent", uid, {
      blocks,
      omitOrders: [1],
    }),
  );
  await assertFails(
    writeCourse(db, "malformed-course-child", uid, {
      childOverrides: { 0: { unexpected: "field" } },
    }),
  );
  await assertFails(
    writeCourse(db, "invalid-course-minute", uid, {
      childOverrides: { 0: { startMinute: 1440 } },
    }),
  );
  await assertFails(
    writeCourse(db, "invalid-course-end-minute", uid, {
      childOverrides: { 0: { endMinute: 480 } },
    }),
  );
  await assertFails(
    writeCourse(db, "invalid-course-room", uid, {
      childOverrides: { 0: { room: "r".repeat(61) } },
    }),
  );
  await assertFails(
    writeCourse(db, "invalid-course-order", uid, {
      childOverrides: { 0: { order: 1 } },
    }),
  );
  await assertFails(
    writeCourse(db, "extra-course-child", uid, {
      extraChildren: [
        {
          id: "extra-weekly-block-child-id",
          data: courseBlockDocument(courseBlock(), 1),
        },
      ],
    }),
  );
});

test("stable-ID course transaction retries are idempotent and reject a payload conflict", async () => {
  const uid = "idempotent-course-teacher";
  await seedProfile(uid, "idempotent@example.test", ["teacher"]);
  const db = userContext(uid, "idempotent@example.test", true);
  const reference = doc(db, "courses", "stable-course-operation-id");
  const blocks = [courseBlock()];
  const payload = courseData(uid);

  const firstResult = await assertSucceeds(
    createCourseIdempotently(db, reference, payload, blocks),
  );
  assert.equal(firstResult, "created");
  const committed = await getDoc(reference);
  const createdAt = committed.data().createdAt;
  assert.ok(createdAt instanceof Timestamp);
  assert.ok(committed.data().startDate instanceof Timestamp);
  assert.ok(committed.data().endDate instanceof Timestamp);

  const retryResult = await assertSucceeds(
    createCourseIdempotently(db, reference, courseData(uid), blocks),
  );
  assert.equal(retryResult, "already-created");
  const afterRetry = await getDoc(reference);
  assert.deepEqual(afterRetry.data().createdAt, createdAt);

  await assert.rejects(
    createCourseIdempotently(
      db,
      reference,
      courseData(uid, { extraFields: { subject: "Otra asignatura" } }),
      blocks,
    ),
    /idempotency-conflict/,
  );

  const differentBlocks = [
    courseBlock({ id: "block_20270104_00002" }),
  ];
  await assert.rejects(
    createCourseIdempotently(
      db,
      reference,
      courseData(uid, { blocks: differentBlocks }),
      differentBlocks,
    ),
    /idempotency-conflict/,
  );
  const afterBlockIdConflict = await getDoc(reference);
  assert.deepEqual(afterBlockIdConflict.data().weeklyBlockIds, blocks.map((block) => block.id));
  assert.deepEqual(afterBlockIdConflict.data().createdAt, createdAt);
  const originalBlock = await getDoc(
    doc(db, "courses", reference.id, "weekly_blocks", blocks[0].id),
  );
  assert.deepEqual(originalBlock.data(), courseBlockDocument(blocks[0], 0));
});

test("course rules validate blocks at first, middle and last positions", async () => {
  const uid = "invalid-block-teacher";
  await seedProfile(uid, "invalid@example.test", ["teacher"]);
  const db = userContext(uid, "invalid@example.test", true);
  const validBlocks = [
    courseBlock({ id: "block_20270104_00001", weekday: 1 }),
    courseBlock({ id: "block_20270105_00001", weekday: 2 }),
    courseBlock({ id: "block_20270106_00001", weekday: 3 }),
  ];

  for (const position of [0, 1, 2]) {
    const invalidBlocks = validBlocks.map((block) => ({ ...block }));
    invalidBlocks[position].weekday = 8;
    await assertFails(
      writeCourse(db, `invalid-block-position-${position}`, uid, {
        blocks: invalidBlocks,
        childOverrides: { [position]: { weekday: 8 } },
      }),
    );
  }
});

test("course rules reject extra fields, invalid dates, empty calendars and schedule overlaps", async () => {
  const uid = "invalid-course-teacher";
  await seedProfile(uid, "invalid-course@example.test", ["teacher"]);
  const db = userContext(uid, "invalid-course@example.test", true);

  await assertFails(
    writeCourse(db, "extra-field-course", uid, {
      extraFields: { enrollmentCount: 10 },
    }),
  );
  await assertFails(
    writeCourse(db, "empty-course-calendar", uid, { blocks: [] }),
  );
  await assertFails(
    writeCourse(db, "blank-course-subject", uid, {
      extraFields: { subject: "   " },
    }),
  );
  await assertFails(
    writeCourse(db, "invalid-block-id-course", uid, {
      blocks: [courseBlock({ id: "short" })],
    }),
  );
  await assertFails(
    writeCourse(db, "non-midnight-course", uid, {
      extraFields: {
        startDate: Timestamp.fromDate(new Date("2027-01-04T01:00:00.000Z")),
      },
    }),
  );
  await assertFails(
    writeCourse(db, "too-long-course", uid, {
      extraFields: {
        endDate: Timestamp.fromDate(new Date("2028-01-05T00:00:00.000Z")),
      },
    }),
  );
  await assertFails(
    writeCourse(db, "no-occurrence-course", uid, {
      blocks: [courseBlock({ weekday: 3 })],
      extraFields: {
        startDate: Timestamp.fromDate(new Date("2027-01-04T00:00:00.000Z")),
        endDate: Timestamp.fromDate(new Date("2027-01-05T00:00:00.000Z")),
      },
    }),
  );
  await assertFails(
    writeCourse(db, "overlap-course", uid, {
      blocks: [
        courseBlock({ id: "block_20270104_00001", weekday: 1 }),
        courseBlock({
          id: "block_20270104_00002",
          weekday: 1,
          startTime: "09:00",
          endTime: "10:00",
        }),
      ],
    }),
  );
  await assertFails(
    writeCourse(db, "duplicate-id-course", uid, {
      blocks: [
        courseBlock({ id: "block_20270104_00001", weekday: 1 }),
        courseBlock({ id: "block_20270104_00001", weekday: 2 }),
      ],
    }),
  );
});

test("course occurrence rules accept the exact weekday in a single-day range", async () => {
  const uid = "single-day-course-teacher";
  await seedProfile(uid, "single-day@example.test", ["teacher"]);
  const db = userContext(uid, "single-day@example.test", true);
  const monday = Timestamp.fromDate(new Date("2027-01-04T00:00:00.000Z"));
  const oneDay = { startDate: monday, endDate: monday };

  await assertSucceeds(
    writeCourse(db, "single-day-monday-course", uid, {
      blocks: [courseBlock({ id: "block_single_day_monday_01", weekday: 1 })],
      extraFields: oneDay,
    }),
  );
  await assertFails(
    writeCourse(db, "single-day-wrong-weekday-course", uid, {
      blocks: [courseBlock({ id: "block_single_day_tuesday_01", weekday: 2 })],
      extraFields: oneDay,
    }),
  );
});

test("course writes require matching server timestamps and cannot edit or delete", async () => {
  const uid = "timestamps-course-teacher";
  await seedProfile(uid, "timestamp@example.test", ["teacher"]);
  const db = userContext(uid, "timestamp@example.test", true);

  await assertFails(
    writeCourse(db, "client-time-course", uid, {
      extraFields: {
        createdAt: Timestamp.fromMillis(1_800_000_000_000),
        updatedAt: Timestamp.fromMillis(1_800_000_000_000),
      },
    }),
  );

  const reference = doc(db, "courses", "immutable-course");
  await assertSucceeds(writeCourse(db, reference.id, uid));
  await assertFails(updateDoc(reference, { ownerUid: "different-owner" }));
  await assertFails(deleteDoc(reference));
});

test("conjunto 3: estudiante verificado publica su entrada exacta, sin exigir migración del perfil", async () => {
  const uid = "existing-student";
  const email = "existing@example.test";
  await seedProfile(uid, email);
  const student = await publishStudent(uid, email);
  const entry = await assertSucceeds(getDoc(doc(student, "student_directory", email)));
  assert.equal(entry.data().uid, uid);
  assert.equal(entry.data().email, email);
  assert.equal(entry.data().updatedAt instanceof Timestamp, true);

  await assertSucceeds(setDoc(
    doc(student, "student_directory", email),
    directoryData(uid, email, profile(email)),
  ));
  await assertSucceeds(deleteDoc(doc(student, "student_directory", email)));
  await assertFails(getDocs(collection(student, "student_directory")));
  await assertFails(getDocs(collection(student, "users")));
});

test("conjunto 3: directorio impide publicación ajena, sin verificar o falsificada", async () => {
  const uid = "student";
  const email = "student@example.test";
  await seedProfile(uid, email);
  const unverified = userContext(uid, email, false);
  const verified = userContext(uid, email, true);
  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  const reference = doc(verified, "student_directory", email);

  await assertPermissionDenied(setDoc(doc(anonymous, "student_directory", email), directoryData(uid, email)));
  await assertPermissionDenied(setDoc(doc(unverified, "student_directory", email), directoryData(uid, email)));
  await assertPermissionDenied(setDoc(reference, directoryData("other", email)));
  await assertPermissionDenied(setDoc(reference, directoryData(uid, email, profile(email), { name: "Suplantación" })));
  await assertPermissionDenied(setDoc(reference, directoryData(uid, email, profile(email), { email: "other@example.test" })));
  await assertPermissionDenied(setDoc(reference, directoryData(uid, email, profile(email), { extra: true })));
  await assertPermissionDenied(setDoc(reference, directoryData(uid, email, profile(email), { updatedAt: Timestamp.now() })));
  await assertPermissionDenied(setDoc(doc(verified, "student_directory", "other@example.test"), directoryData(uid, "other@example.test")));
  await assertSucceeds(setDoc(reference, directoryData(uid, email)));
  await assertPermissionDenied(updateDoc(reference, { uid: "other", updatedAt: serverTimestamp() }));
  await assertPermissionDenied(deleteDoc(doc(userContext("other", "other@example.test", true), "student_directory", email)));
});

test("conjunto 3: docente conoce correo exacto, pero no enumera el directorio ni lee entradas obsoletas", async () => {
  const studentUid = "student";
  const oldEmail = "old@example.test";
  await seedProfile(studentUid, oldEmail);
  await publishStudent(studentUid, oldEmail);
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("admin", "admin@example.test", ["admin"]);
  const teacher = userContext("teacher", "teacher@example.test", true);
  const admin = userContext("admin", "admin@example.test", true);
  const entry = doc(teacher, "student_directory", oldEmail);
  assert.equal((await assertSucceeds(getDoc(entry))).data().uid, studentUid);
  assert.equal((await assertSucceeds(getDoc(doc(teacher, "student_directory", "unknown@example.test")))).exists(), false);
  await assertFails(getDocs(collection(teacher, "student_directory")));
  await assertFails(getDoc(doc(admin, "student_directory", oldEmail)));
  await assertFails(getDoc(doc(userContext("teacher", "teacher@example.test", false), "student_directory", oldEmail)));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", studentUid), profile("new@example.test"));
  });
  await assertFails(getDoc(entry));
});

test("conjunto 3: nuevo titular verificado recupera correo liberado sin tomar una entrada vigente", async () => {
  const oldUid = "old-holder";
  const newUid = "new-holder";
  const releasedEmail = "released@example.test";
  const nextEmail = "next@example.test";
  await seedProfile(oldUid, releasedEmail, ["student"], { name: "Titular anterior" });
  await seedProfile(newUid, releasedEmail, ["student"], { name: "Nuevo titular" });
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  const oldProfile = profile(releasedEmail, ["student"], { name: "Titular anterior" });
  const newProfile = profile(releasedEmail, ["student"], { name: "Nuevo titular" });
  const old = await publishStudent(oldUid, releasedEmail, oldProfile);
  const fresh = userContext(newUid, releasedEmail, true);
  const teacher = userContext("teacher", "teacher@example.test", true);
  const oldPath = doc(old, "student_directory", releasedEmail);
  const newPath = doc(fresh, "student_directory", releasedEmail);

  await assertPermissionDenied(setDoc(newPath, directoryData(newUid, releasedEmail, newProfile)));
  assert.equal((await assertSucceeds(getDoc(doc(teacher, "student_directory", releasedEmail)))).data().uid, oldUid);

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", oldUid), profile(nextEmail, ["student"], { name: "Titular anterior" }));
  });
  await assertFails(getDoc(doc(teacher, "student_directory", releasedEmail)));
  await assertSucceeds(setDoc(newPath, directoryData(newUid, releasedEmail, newProfile)));
  const recovered = await assertSucceeds(getDoc(doc(teacher, "student_directory", releasedEmail)));
  assert.equal(recovered.data().uid, newUid);
  assert.equal(recovered.data().name, "Nuevo titular");
  await assertPermissionDenied(deleteDoc(oldPath));
  await assertPermissionDenied(setDoc(oldPath, directoryData(oldUid, releasedEmail, oldProfile)));
  await assertSucceeds(setDoc(newPath, directoryData(newUid, releasedEmail, newProfile)));
});

test("conjunto 3: inscripción válida expone solo curso y bloques al estudiante inscrito", async () => {
  const teacherUid = "teacher-a";
  const studentUid = "student-a";
  const teacherEmail = "teacher-a@example.test";
  const studentEmail = "student-a@example.test";
  const courseId = "course-a";
  await seedProfile(teacherUid, teacherEmail, ["teacher"]);
  await seedProfile(studentUid, studentEmail);
  await seedCourse(teacherUid, courseId);
  const teacher = userContext(teacherUid, teacherEmail, true);
  const student = await publishStudent(studentUid, studentEmail);
  const block = courseBlock().id;
  const payload = enrollmentData(studentUid, teacherUid, studentEmail);
  const enrolledRef = doc(teacher, "courses", courseId, "enrollments", studentUid);

  await assertFails(getDoc(doc(student, "courses", courseId)));
  await assertFails(getDoc(doc(student, "courses", courseId, "weekly_blocks", block)));
  assert.equal(await assertSucceeds(enrollIdempotently(teacher, courseId, studentUid, payload)), "created");
  assert.equal((await assertSucceeds(getDoc(enrolledRef))).data().status, "active");
  const own = await assertSucceeds(getDocs(collection(teacher, "courses", courseId, "enrollments")));
  assert.deepEqual(own.docs.map((entry) => entry.id), [studentUid]);
  assert.equal((await assertSucceeds(getDoc(doc(student, "courses", courseId)))).data().subject, "Bases de Datos");
  assert.equal((await assertSucceeds(getDoc(doc(student, "courses", courseId, "weekly_blocks", block)))).data().weekday, 1);
  assert.equal((await assertSucceeds(getDocs(collection(student, "courses", courseId, "weekly_blocks")))).size, 1);
  await assertFails(updateDoc(doc(student, "courses", courseId), { subject: "Ataque" }));
  await assertFails(setDoc(doc(student, "courses", courseId, "weekly_blocks", "forged"), courseBlockDocument(courseBlock(), 0)));
  await assertFails(getDocs(collection(student, "courses")));
});

test("conjunto 6: alta confirmada desde correo exacto habilita curso y horario sin duplicar", async () => {
  const courseId = "course-excel";
  const teacherEmail = "teacher-a@example.test";
  const selectedEmail = "selected@example.test";
  const unselectedEmail = "unselected@example.test";
  await seedProfile("teacher-a", teacherEmail, ["teacher"]);
  await seedProfile("selected", selectedEmail);
  await seedProfile("unselected", unselectedEmail);
  await seedCourse("teacher-a", courseId);
  const teacher = userContext("teacher-a", teacherEmail, true);
  const selected = await publishStudent("selected", selectedEmail);
  const unselected = await publishStudent("unselected", unselectedEmail);
  const blockId = courseBlock().id;

  assert.equal((await assertSucceeds(getDoc(doc(teacher, "student_directory", selectedEmail)))).data().uid, "selected");
  await assertPermissionDenied(getDoc(doc(selected, "courses", courseId)));
  await assertPermissionDenied(getDoc(doc(selected, "courses", courseId, "weekly_blocks", blockId)));
  await assertPermissionDenied(getDoc(doc(unselected, "courses", courseId)));

  assert.equal(await assertSucceeds(enrollManuallyAndResolvePending(teacher, courseId, "selected", selectedEmail)), "created");
  const enrollmentRef = doc(teacher, "courses", courseId, "enrollments", "selected");
  const createdAt = (await assertSucceeds(getDoc(enrollmentRef))).data().createdAt;
  assert.equal((await assertSucceeds(getDoc(doc(selected, "courses", courseId)))).data().subject, "Bases de Datos");
  assert.equal((await assertSucceeds(getDoc(doc(selected, "courses", courseId, "weekly_blocks", blockId)))).data().weekday, 1);
  await assertPermissionDenied(getDoc(doc(unselected, "courses", courseId)));

  assert.equal(await assertSucceeds(enrollManuallyAndResolvePending(teacher, courseId, "selected", selectedEmail)), "already-enrolled");
  assert.deepEqual((await assertSucceeds(getDoc(enrollmentRef))).data().createdAt, createdAt);
  assert.equal((await assertSucceeds(getDocs(collection(teacher, "courses", courseId, "enrollments")))).size, 1);
});

test("conjunto 3: la consulta de grupo exige UID propio y no expone otras inscripciones", async () => {
  await seedProfile("teacher-a", "teacher-a@example.test", ["teacher"]);
  await seedProfile("teacher-b", "teacher-b@example.test", ["teacher"]);
  await seedProfile("student-a", "student-a@example.test");
  await seedProfile("student-b", "student-b@example.test");
  await seedCourse("teacher-a", "course-a");
  await seedCourse("teacher-b", "course-b");
  const teacherA = userContext("teacher-a", "teacher-a@example.test", true);
  const teacherB = userContext("teacher-b", "teacher-b@example.test", true);
  const studentA = await publishStudent("student-a", "student-a@example.test");
  await publishStudent("student-b", "student-b@example.test");
  await assertSucceeds(setDoc(doc(teacherA, "courses", "course-a", "enrollments", "student-a"), enrollmentData("student-a", "teacher-a", "student-a@example.test")));
  await assertSucceeds(setDoc(doc(teacherB, "courses", "course-b", "enrollments", "student-b"), enrollmentData("student-b", "teacher-b", "student-b@example.test")));
  const ownQuery = query(
    collectionGroup(studentA, "enrollments"),
    where("studentUid", "==", "student-a"),
    where("status", "==", "active"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  );
  const own = await assertSucceeds(getDocs(ownQuery));
  assert.deepEqual(own.docs.map((entry) => entry.id), ["student-a"]);
  await assertFails(getDocs(collectionGroup(studentA, "enrollments")));
  await assertFails(getDocs(query(collectionGroup(studentA, "enrollments"), where("studentUid", "==", "student-b"))));
  await assertFails(getDoc(doc(studentA, "courses", "course-b")));
  await assertFails(getDoc(doc(studentA, "courses", "course-b", "weekly_blocks", courseBlock().id)));
  await assertFails(getDoc(doc(studentA, "courses", "course-b", "enrollments", "student-b")));
  await assertFails(getDocs(collection(studentA, "courses", "course-a", "enrollments")));
});

test("conjunto 3: otro docente, estudiante y admin no pueden crear ni alterar matrículas", async () => {
  const courseId = "course-a";
  await seedProfile("teacher-a", "teacher-a@example.test", ["teacher"]);
  await seedProfile("teacher-b", "teacher-b@example.test", ["teacher"]);
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher-a", courseId);
  const teacherA = userContext("teacher-a", "teacher-a@example.test", true);
  const teacherB = userContext("teacher-b", "teacher-b@example.test", true);
  const admin = userContext("admin", "admin@example.test", true);
  const student = await publishStudent("student", "student@example.test");
  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  const payload = enrollmentData("student", "teacher-a", "student@example.test");
  const path = ["courses", courseId, "enrollments", "student"];
  await assertPermissionDenied(setDoc(doc(student, ...path), payload));
  await assertPermissionDenied(setDoc(doc(teacherB, ...path), payload));
  await assertPermissionDenied(setDoc(doc(admin, ...path), payload));
  await assertPermissionDenied(setDoc(doc(anonymous, ...path), payload));
  await assertFails(getDocs(collection(teacherB, "courses", courseId, "enrollments")));
  await assertSucceeds(setDoc(doc(teacherA, ...path), payload));
  await assertPermissionDenied(updateDoc(doc(teacherA, ...path), { name: "Otro" }));
  await assertFails(deleteDoc(doc(teacherA, ...path)));
  await assertFails(updateDoc(doc(student, ...path), { status: "inactive" }));
  await assertFails(deleteDoc(doc(student, ...path)));
});

test("conjunto 3: matrícula exige directorio y snapshots íntegros sin campos extra", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const base = enrollmentData("student", "teacher", "student@example.test");
  const ref = doc(teacher, "courses", "course", "enrollments", "student");
  await assertPermissionDenied(setDoc(ref, base));
  await publishStudent("student", "student@example.test");
  const invalid = [
    { studentUid: "other" }, { ownerUid: "other" }, { name: "Nombre falso" },
    { email: "other@example.test" }, { studentCode: "STU-999" },
    { subject: "Otra materia" }, { group: "Otro grupo" }, { period: "2030-1" },
    { status: "pending" }, { createdAt: Timestamp.now() }, { roles: ["teacher"] },
  ];
  for (const variant of invalid) {
    await assertPermissionDenied(setDoc(ref, { ...base, ...variant }));
  }
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", "student"), profile("student@example.test", ["teacher"]));
  });
  await assertPermissionDenied(setDoc(ref, base));
});

test("conjunto 3: reintento es único; paginación, conteos y roles combinados conservan acceso", async () => {
  await seedProfile("teacher", "teacher@example.test", ["student", "teacher"]);
  await seedProfile("other-teacher", "other-teacher@example.test", ["teacher"]);
  await seedProfile("student-a", "student-a@example.test", ["student", "teacher"]);
  await seedProfile("student-b", "student-b@example.test");
  await seedCourse("teacher", "course-a");
  await seedCourse("other-teacher", "course-b");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const otherTeacher = userContext("other-teacher", "other-teacher@example.test", true);
  const studentA = await publishStudent("student-a", "student-a@example.test");
  await publishStudent("student-b", "student-b@example.test");
  const payloadA = enrollmentData("student-a", "teacher", "student-a@example.test");
  const payloadB = enrollmentData("student-b", "teacher", "student-b@example.test");
  assert.equal(await assertSucceeds(enrollIdempotently(teacher, "course-a", "student-a", payloadA)), "created");
  const enrolledRef = doc(teacher, "courses", "course-a", "enrollments", "student-a");
  const originalAt = (await getDoc(enrolledRef)).data().createdAt;
  assert.equal(await assertSucceeds(enrollIdempotently(teacher, "course-a", "student-a", payloadA)), "already-enrolled");
  await assertPermissionDenied(setDoc(enrolledRef, payloadA));
  assert.deepEqual((await getDoc(enrolledRef)).data().createdAt, originalAt);
  await assertSucceeds(enrollIdempotently(teacher, "course-a", "student-b", payloadB));
  const students = collection(teacher, "courses", "course-a", "enrollments");
  const first = await assertSucceeds(getDocs(query(students, orderBy("createdAt", "desc"), orderBy(documentId(), "desc"), limit(1))));
  const second = await assertSucceeds(getDocs(query(students, orderBy("createdAt", "desc"), orderBy(documentId(), "desc"), startAfter(first.docs[0]), limit(1))));
  assert.equal(first.size + second.size, 2);
  assert.equal((await assertSucceeds(getCountFromServer(students))).data().count, 2);

  await assertSucceeds(enrollIdempotently(otherTeacher, "course-b", "student-a", enrollmentData("student-a", "other-teacher", "student-a@example.test")));
  const ownCourses = await assertSucceeds(getDocs(query(collectionGroup(studentA, "enrollments"), where("studentUid", "==", "student-a"), where("status", "==", "active"), orderBy("createdAt", "desc"), orderBy(documentId(), "desc"))));
  assert.equal(ownCourses.size, 2);
  await assertSucceeds(getDoc(doc(studentA, "courses", "course-a")));
  await assertSucceeds(getDoc(doc(studentA, "courses", "course-b")));
});

test("conjunto 3: código opcional, perfil obsoleto y verificación controlan la matrícula", async () => {
  const teacherUid = "teacher";
  const teacherEmail = "teacher@example.test";
  const studentUid = "student";
  const studentEmail = "student@example.test";
  const noCode = profile(studentEmail, ["student"], { studentCode: null });
  await seedProfile(teacherUid, teacherEmail, ["teacher"]);
  await seedProfile(studentUid, studentEmail, ["student"], { studentCode: null });
  await seedCourse(teacherUid, "course");
  const teacher = userContext(teacherUid, teacherEmail, true);
  await publishStudent(studentUid, studentEmail, noCode);
  const ref = doc(teacher, "courses", "course", "enrollments", studentUid);
  const payload = enrollmentData(studentUid, teacherUid, studentEmail, noCode);
  await assertSucceeds(setDoc(ref, payload));

  const studentUnverified = userContext(studentUid, studentEmail, false);
  await assertFails(getDoc(doc(studentUnverified, "courses", "course")));
  await assertFails(getDoc(doc(studentUnverified, "courses", "course", "enrollments", studentUid)));
  await assertFails(getDocs(query(collectionGroup(studentUnverified, "enrollments"), where("studentUid", "==", studentUid))));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", studentUid), profile(studentEmail, ["student"], { name: "Nombre actualizado", studentCode: null }));
  });
  await assertFails(getDoc(doc(teacher, "student_directory", studentEmail)));
  await assertPermissionDenied(setDoc(doc(teacher, "courses", "course", "enrollments", "another"), enrollmentData("another", teacherUid, studentEmail, noCode)));
  const student = userContext(studentUid, studentEmail, true);
  await assertSucceeds(setDoc(doc(student, "student_directory", studentEmail), directoryData(studentUid, studentEmail, profile(studentEmail, ["student"], { name: "Nombre actualizado", studentCode: null }))));
  assert.equal((await assertSucceeds(getDoc(doc(teacher, "student_directory", studentEmail)))).data().name, "Nombre actualizado");
});

const inviteCodeA = "ABCDEFGHJKLMNPQR";
const inviteCodeB = "23456789ABCDEFGH";

test("conjunto 4: recorrido Dart usa índice permitido y nunca lee current privado como estudiante", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student-a", "student-a@example.test");
  await seedProfile("student-b", "student-b@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const studentA = userContext("student-a", "student-a@example.test", true);
  const studentB = userContext("student-b", "student-b@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  const preview = await assertSucceeds(getDoc(doc(studentA, "course_invites", inviteCodeA)));
  assert.equal(preview.data().courseId, "course");
  const privateCurrent = doc(studentA, "courses", "course", "invitation", "current");
  // These are the two reads the previous Dart lookup/submission incorrectly made.
  await assertPermissionDenied(getDoc(privateCurrent));
  await assertPermissionDenied(runTransaction(studentA, (transaction) => transaction.get(privateCurrent)));
  assert.equal(await assertSucceeds(submitJoinRequestAtomically(studentA, "course", "student-a", inviteCodeA)), "created");
  await assertSucceeds(renewInvitationAtomically(teacher, "course", inviteCodeB));
  await assertPermissionDenied(getDoc(doc(studentB, "course_invites", inviteCodeA)));
  assert.equal((await assertSucceeds(getDoc(doc(studentB, "course_invites", inviteCodeB)))).data().courseId, "course");
  assert.equal(await assertSucceeds(submitJoinRequestAtomically(studentB, "course", "student-b", inviteCodeB)), "created");
});

test("conjunto 4: invitación del propietario y consulta exacta exponen solo la ficha mínima", async () => {
  await seedProfile("teacher-a", "teacher-a@example.test", ["teacher"]);
  await seedProfile("teacher-b", "teacher-b@example.test", ["teacher"]);
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedProfile("student-a", "student-a@example.test");
  await seedCourse("teacher-a", "course-a");
  const teacherA = userContext("teacher-a", "teacher-a@example.test", true);
  const teacherB = userContext("teacher-b", "teacher-b@example.test", true);
  const admin = userContext("admin", "admin@example.test", true);
  const student = userContext("student-a", "student-a@example.test", true);

  await assertSucceeds(createInvitationAtomically(teacherA, "course-a", inviteCodeA));
  const current = await assertSucceeds(
    getDoc(doc(teacherA, "courses", "course-a", "invitation", "current")),
  );
  assert.deepEqual(Object.keys(current.data()).sort(), [
    "code", "createdAt", "status", "updatedAt", "validForSeconds",
  ]);
  assert.equal(current.data().code, inviteCodeA);
  assert.equal(current.data().status, "active");

  const preview = await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeA)));
  assert.deepEqual(Object.keys(preview.data()).sort(), [
    "courseId", "createdAt", "group", "period", "subject",
  ]);
  assert.equal(preview.data().courseId, "course-a");
  assert.equal(preview.data().subject, "Bases de Datos");
  await assertFails(getDocs(collection(student, "course_invites")));
  await assertFails(getDoc(doc(student, "courses", "course-a")));
  await assertFails(
    getDoc(doc(student, "courses", "course-a", "weekly_blocks", courseBlock().id)),
  );
  await assertFails(getDocs(collection(student, "courses", "course-a", "enrollments")));
  await assertFails(
    getDoc(doc(teacherB, "courses", "course-a", "invitation", "current")),
  );
  await assertFails(
    getDoc(doc(admin, "courses", "course-a", "invitation", "current")),
  );
  await assertFails(getDoc(doc(admin, "course_invites", inviteCodeA)));
});

test("conjunto 4: las invitaciones exigen curso propio y una colisión no sobrescribe", async () => {
  await seedProfile("teacher-a", "teacher-a@example.test", ["teacher"]);
  await seedProfile("teacher-b", "teacher-b@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedCourse("teacher-a", "course-a");
  await seedCourse("teacher-b", "course-b");
  const teacherA = userContext("teacher-a", "teacher-a@example.test", true);
  const teacherB = userContext("teacher-b", "teacher-b@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const admin = userContext("admin", "admin@example.test", true);

  await assertSucceeds(createInvitationAtomically(teacherA, "course-a", inviteCodeA));
  await assertSucceeds(createInvitationAtomically(teacherB, "course-b", inviteCodeB));
  await assertPermissionDenied(createInvitationAtomically(teacherB, "course-b", inviteCodeA));
  const original = await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeA)));
  assert.equal(original.data().courseId, "course-a");
  assert.equal(
    (await assertSucceeds(getDoc(doc(teacherB, "courses", "course-b", "invitation", "current")))).data().code,
    inviteCodeB,
  );
  await assertFails(createInvitationAtomically(student, "course-a", inviteCodeB));
  await assertFails(createInvitationAtomically(admin, "course-a", inviteCodeB));
  await assertFails(
    setDoc(doc(teacherB, "courses", "course-a", "invitation", "current"), {
      code: inviteCodeB,
      status: "active",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("conjunto 4: renovación/desactivación invalidan códigos anteriores y expiración usa hora de servidor", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const expiredCode = "JKLMNPQRSTUVWXYZ";
  const expiredAt = Timestamp.fromMillis(Date.now() - 15 * 24 * 60 * 60 * 1000);
  await seedInvitationDisabled("course", expiredCode, { createdAt: expiredAt });
  await assertFails(getDoc(doc(student, "course_invites", expiredCode)));
  await assert.rejects(
    submitJoinRequestAtomically(student, "course", "student", expiredCode),
  );

  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeA)));
  await assertSucceeds(renewInvitationAtomically(teacher, "course", inviteCodeB));
  await assertFails(getDoc(doc(student, "course_invites", inviteCodeA)));
  await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeB)));
  await assert.rejects(
    submitJoinRequestAtomically(student, "course", "student", inviteCodeA),
  );

  await assertSucceeds(updateDoc(
    doc(teacher, "courses", "course", "invitation", "current"),
    { status: "inactive", updatedAt: serverTimestamp() },
  ));
  await assertFails(getDoc(doc(student, "course_invites", inviteCodeB)));
  await assert.rejects(
    submitJoinRequestAtomically(student, "course", "student", inviteCodeB),
  );
  await assertFails(
    deleteDoc(doc(teacher, "course_invites", inviteCodeB)),
  );
});

test("conjunto 4: el estudiante verificado crea y consulta su solicitud sin duplicar", async () => {
  await seedProfile("teacher-a", "teacher-a@example.test", ["teacher"]);
  await seedProfile("student-a", "student-a@example.test");
  await seedProfile("student-b", "student-b@example.test");
  await seedProfile("teacher-b", "teacher-b@example.test", ["teacher"]);
  await seedCourse("teacher-a", "course-a");
  const teacherA = userContext("teacher-a", "teacher-a@example.test", true);
  const teacherB = userContext("teacher-b", "teacher-b@example.test", true);
  const studentA = userContext("student-a", "student-a@example.test", true);
  const studentB = userContext("student-b", "student-b@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacherA, "course-a", inviteCodeA));

  assert.equal(
    await assertSucceeds(
      submitJoinRequestAtomically(studentA, "course-a", "student-a", inviteCodeA),
    ),
    "created",
  );
  assert.equal(
    await assertSucceeds(
      submitJoinRequestAtomically(studentA, "course-a", "student-a", inviteCodeA),
    ),
    "pending",
  );
  assert.equal(
    await assertSucceeds(
      submitJoinRequestAtomically(studentB, "course-a", "student-b", inviteCodeA),
    ),
    "created",
  );
  const ownRequestRef = doc(studentA, "courses", "course-a", "join_requests", "student-a");
  const own = await assertSucceeds(getDoc(ownRequestRef));
  assert.equal(own.data().studentUid, "student-a");
  assert.equal(own.data().subject, "Bases de Datos");
  assert.equal(own.data().group, "Grupo 2");
  assert.equal(own.data().period, "2027-1");
  assert.equal(own.data().status, "pending");
  await assertFails(
    getDoc(doc(studentA, "courses", "course-a", "join_requests", "student-b")),
  );
  await assertFails(setDoc(ownRequestRef, joinRequestData("student-a", "student-a@example.test", inviteCodeA)));

  const teacherQueue = await assertSucceeds(
    getDocs(query(
      collection(teacherA, "courses", "course-a", "join_requests"),
      where("status", "==", "pending"),
      orderBy("createdAt", "desc"),
      orderBy(documentId(), "desc"),
    )),
  );
  assert.equal(teacherQueue.size, 2);
  await assertFails(
    getDocs(collection(teacherA, "courses", "course-a", "join_requests")),
  );
  await assertFails(
    getDocs(query(
      collection(teacherB, "courses", "course-a", "join_requests"),
      where("status", "==", "pending"),
    )),
  );
  const ownRequests = await assertSucceeds(
    getDocs(query(
      collectionGroup(studentA, "join_requests"),
      where("studentUid", "==", "student-a"),
      orderBy("createdAt", "desc"),
      orderBy(documentId(), "desc"),
    )),
  );
  assert.deepEqual(ownRequests.docs.map((request) => request.id), ["student-a"]);
  await assertFails(getDocs(collectionGroup(studentA, "join_requests")));
  await assertFails(
    getDocs(query(collectionGroup(studentA, "join_requests"), where("studentUid", "==", "student-b"))),
  );
});

test("conjunto 4: autenticación, rol, código, perfil y campos de solicitud se validan", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedProfile("teacher-2", "teacher-2@example.test", ["teacher"]);
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const unverified = userContext("student", "student@example.test", false);
  const wrongEmail = userContext("student", "changed@example.test", true);
  const teacher2 = userContext("teacher-2", "teacher-2@example.test", true);
  const admin = userContext("admin", "admin@example.test", true);
  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  const requestRef = (db) => doc(db, "courses", "course", "join_requests", "student");

  await assertFails(setDoc(requestRef(anonymous), joinRequestData("student", "student@example.test", inviteCodeA)));
  await assertFails(setDoc(requestRef(unverified), joinRequestData("student", "student@example.test", inviteCodeA)));
  await assertFails(setDoc(requestRef(wrongEmail), joinRequestData("student", "changed@example.test", inviteCodeA)));
  await assertFails(setDoc(requestRef(teacher2), joinRequestData("teacher-2", "teacher-2@example.test", inviteCodeA)));
  await assertFails(setDoc(requestRef(admin), joinRequestData("admin", "admin@example.test", inviteCodeA)));

  const invalidRequests = [
    { name: "Nombre falso" },
    { email: "other@example.test" },
    { studentCode: "STU-OTHER" },
    { subject: "Otra materia" },
    { group: "Otro grupo" },
    { period: "2030-1" },
    { invitationCode: "INVALIDO" },
    { status: "approved" },
    { decidedBy: "student" },
    { decidedAt: Timestamp.now() },
    { rejectionReason: "No debe elegir una decisión" },
    { role: "teacher" },
  ];
  for (const variant of invalidRequests) {
    await assertFails(
      setDoc(
        requestRef(student),
        joinRequestData("student", "student@example.test", inviteCodeA, variant),
      ),
    );
  }
  assert.equal((await assertSucceeds(getDoc(requestRef(student)))).exists(), false);
});

test("conjunto 4: una invitación no crea solicitud para quien ya está inscrito", async () => {
  const studentProfile = profile("student@example.test");
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = await publishStudent("student", "student@example.test", studentProfile);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(
    setDoc(
      doc(teacher, "courses", "course", "enrollments", "student"),
      enrollmentData("student", "teacher", "student@example.test", studentProfile),
    ),
  );
  await assertFails(
    setDoc(
      doc(student, "courses", "course", "join_requests", "student"),
      joinRequestData("student", "student@example.test", inviteCodeA),
    ),
  );
});

test("conjunto 4: aprobar crea matrícula y decisión en una transacción; ambos son inmutables", async () => {
  await seedProfile("teacher-a", "teacher-a@example.test", ["teacher"]);
  await seedProfile("student-a", "student-a@example.test");
  await seedCourse("teacher-a", "course-a");
  const teacher = userContext("teacher-a", "teacher-a@example.test", true);
  const student = userContext("student-a", "student-a@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacher, "course-a", inviteCodeA));
  await assertSucceeds(submitJoinRequestAtomically(student, "course-a", "student-a", inviteCodeA));
  const requestRef = doc(teacher, "courses", "course-a", "join_requests", "student-a");
  const enrollmentRef = doc(teacher, "courses", "course-a", "enrollments", "student-a");

  await assertFails(updateDoc(requestRef, {
    status: "approved",
    decidedBy: "teacher-a",
    decidedAt: serverTimestamp(),
    rejectionReason: null,
  }));
  await assertPermissionDenied(setDoc(
    enrollmentRef,
    enrollmentData("student-a", "teacher-a", "student-a@example.test"),
  ));
  assert.equal(
    await assertSucceeds(decideJoinRequestAtomically(
      teacher, "course-a", "student-a", "teacher-a", { status: "approved" },
    )),
    "approved",
  );
  assert.equal((await assertSucceeds(getDoc(requestRef))).data().status, "approved");
  assert.equal((await assertSucceeds(getDoc(enrollmentRef))).data().status, "active");
  await assertSucceeds(getDoc(doc(student, "courses", "course-a")));
  assert.equal(
    await assertSucceeds(decideJoinRequestAtomically(
      teacher, "course-a", "student-a", "teacher-a", { status: "rejected", reason: "otra" },
    )),
    "already-resolved",
  );
  await assertFails(updateDoc(requestRef, {
    status: "rejected",
    decidedBy: "teacher-a",
    decidedAt: serverTimestamp(),
    rejectionReason: "reabierta",
  }));
  await assertFails(updateDoc(enrollmentRef, { status: "inactive" }));
});

test("conjunto 4: rechazar conserva motivo y no concede acceso ni crea matrícula", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  const requestRef = doc(teacher, "courses", "course", "join_requests", "student");
  const enrollmentRef = doc(student, "courses", "course", "enrollments", "student");
  await assertFails(updateDoc(requestRef, {
    status: "rejected",
    decidedBy: "teacher",
    decidedAt: serverTimestamp(),
    rejectionReason: "",
  }));
  await assertSucceeds(decideJoinRequestAtomically(
    teacher, "course", "student", "teacher", { status: "rejected", reason: "Cupo completo" },
  ));
  const result = await assertSucceeds(getDoc(doc(student, "courses", "course", "join_requests", "student")));
  assert.equal(result.data().status, "rejected");
  assert.equal(result.data().rejectionReason, "Cupo completo");
  assert.equal((await assertSucceeds(getDoc(enrollmentRef))).exists(), false);
  await assertFails(getDoc(doc(student, "courses", "course")));
  await assertFails(updateDoc(requestRef, {
    status: "approved",
    decidedBy: "teacher",
    decidedAt: serverTimestamp(),
    rejectionReason: null,
  }));
});

test("conjunto 4: la aprobación que conserva matrícula manual resuelve pending sin duplicarla", async () => {
  const studentProfile = profile("student@example.test");
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = await publishStudent("student", "student@example.test", studentProfile);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "courses", "course", "enrollments", "student"),
      enrollmentData("student", "teacher", "student@example.test", studentProfile),
    );
  });
  const original = (await assertSucceeds(getDoc(enrollmentRef))).data();
  await assertSucceeds(decideJoinRequestAtomically(
    teacher, "course", "student", "teacher", { status: "approved" },
  ));
  const saved = (await assertSucceeds(getDoc(enrollmentRef))).data();
  assert.deepEqual(saved, original);
  assert.equal(
    (await assertSucceeds(getDoc(doc(teacher, "courses", "course", "join_requests", "student")))).data().status,
    "approved",
  );
});

test("conjunto 4: inscripción manual durante pending requiere resolver ambas escrituras juntas", async () => {
  await seedProfile("teacher-a", "teacher-a@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher-a", "course-a");
  const teacher = userContext("teacher-a", "teacher-a@example.test", true);
  const student = await publishStudent("student", "student@example.test");
  await assertSucceeds(createInvitationAtomically(teacher, "course-a", inviteCodeA));
  await assertSucceeds(submitJoinRequestAtomically(student, "course-a", "student", inviteCodeA));
  const payload = enrollmentData("student", "teacher-a", "student@example.test");
  await assertPermissionDenied(enrollIdempotently(teacher, "course-a", "student", payload));
  assert.equal(
    await assertSucceeds(enrollManuallyAndResolvePending(
      teacher, "course-a", "student", "student@example.test",
    )),
    "created",
  );
  assert.equal(
    (await assertSucceeds(getDoc(doc(student, "courses", "course-a", "join_requests", "student")))).data().status,
    "approved",
  );
  assert.equal(
    (await assertSucceeds(getDoc(doc(student, "courses", "course-a", "enrollments", "student")))).data().status,
    "active",
  );
});

test("conjunto 4: matrícula posterior al rechazo conserva la decisión histórica", async () => {
  const studentProfile = profile("student@example.test");
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = await publishStudent("student", "student@example.test", studentProfile);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  await assertSucceeds(decideJoinRequestAtomically(
    teacher, "course", "student", "teacher", { status: "rejected", reason: "Revisar grupo" },
  ));
  await assertSucceeds(enrollManuallyAndResolvePending(
    teacher, "course", "student", "student@example.test",
  ));
  assert.equal(
    (await assertSucceeds(getDoc(doc(student, "courses", "course", "join_requests", "student")))).data().status,
    "rejected",
  );
  assert.equal(
    (await assertSucceeds(getDoc(doc(student, "courses", "course", "enrollments", "student")))).data().status,
    "active",
  );
});

test("conjunto 4: dos decisiones concurrentes no pueden aprobar y rechazar la misma solicitud", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  const outcomes = await Promise.allSettled([
    decideJoinRequestAtomically(teacher, "course", "student", "teacher", { status: "approved" }),
    decideJoinRequestAtomically(teacher, "course", "student", "teacher", { status: "rejected", reason: "No" }),
  ]);
  const request = (await assertSucceeds(getDoc(doc(student, "courses", "course", "join_requests", "student")))).data();
  assert.ok(["approved", "rejected"].includes(request.status));
  assert.ok(outcomes.some((outcome) =>
    outcome.status === "fulfilled" && ["approved", "rejected", "already-resolved"].includes(outcome.value),
  ));
  const enrollment = await assertSucceeds(
    getDoc(doc(student, "courses", "course", "enrollments", "student")),
  );
  assert.equal(enrollment.exists(), request.status === "approved");
});


test("conjunto 4 ampliado: editar pausar reactivar y desactivar conservan código e historia", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student-a", "student-a@example.test");
  await seedProfile("student-b", "student-b@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const studentA = userContext("student-a", "student-a@example.test", true);
  const studentB = userContext("student-b", "student-b@example.test", true);
  const currentRef = doc(teacher, "courses", "course", "invitation", "current");
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA, 3600));
  const original = (await getDoc(currentRef)).data();
  await assertSucceeds(submitJoinRequestAtomically(studentA, "course", "student-a", inviteCodeA));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {validForSeconds: 7200}));
  const edited = (await getDoc(currentRef)).data();
  assert.equal(edited.code, original.code);
  assert.deepEqual(edited.createdAt, original.createdAt);
  assert.equal(edited.validForSeconds, 7200);
  // A preview was already open when the teacher paused it.
  await assertSucceeds(getDoc(doc(studentB, "course_invites", inviteCodeA)));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {status: "paused"}));
  await assertPermissionDenied(getDoc(doc(studentB, "course_invites", inviteCodeA)));
  await assertPermissionDenied(submitJoinRequestAtomically(studentB, "course", "student-b", inviteCodeA));
  // Decisions remain available for a request sent while the code was valid.
  await assertSucceeds(decideJoinRequestAtomically(teacher, "course", "student-a", "teacher", {status: "approved"}));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {validForSeconds: 10800}));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {status: "active"}));
  await assertSucceeds(getDoc(doc(studentB, "course_invites", inviteCodeA)));
  await assertSucceeds(submitJoinRequestAtomically(studentB, "course", "student-b", inviteCodeA));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {status: "inactive"}));
  await assertPermissionDenied(getDoc(doc(studentB, "course_invites", inviteCodeA)));
  await assertPermissionDenied(changeInvitationAtomically(teacher, "course", {status: "active"}));
  await assertPermissionDenied(changeInvitationAtomically(teacher, "course", {status: "paused"}));
  await assertPermissionDenied(changeInvitationAtomically(teacher, "course", {validForSeconds: 14400}));
  assert.equal((await getDoc(doc(studentA, "courses", "course", "join_requests", "student-a"))).data().status, "approved");
  assert.equal((await getDoc(doc(studentA, "courses", "course", "enrollments", "student-a"))).data().status, "active");
  assert.equal((await getDoc(doc(studentB, "courses", "course", "join_requests", "student-b"))).data().status, "pending");
  await assertSucceeds(renewInvitationAtomically(teacher, "course", inviteCodeB, 86400));
  await assertPermissionDenied(getDoc(doc(studentB, "course_invites", inviteCodeA)));
  await assertSucceeds(getDoc(doc(studentB, "course_invites", inviteCodeB)));
});

test("conjunto 4 ampliado: vigencia finita tipos timestamps y fuente única", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  for (const invalid of [0, -1, 3599, 7776001, "3600", null, 3600.5]) {
    await assertPermissionDenied(createInvitationAtomically(teacher, "course", inviteCodeA, invalid));
  }
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA, 3600));
  const currentRef = doc(teacher, "courses", "course", "invitation", "current");
  for (const change of [
    {validForSeconds: 3599}, {validForSeconds: 7776001}, {validForSeconds: "7200"},
    {expiresAt: Timestamp.now()}, {createdAt: Timestamp.now()},
    {updatedAt: Timestamp.fromMillis(1)}, {ownerUid: "other"},
  ]) {
    await assertPermissionDenied(updateDoc(currentRef, {...change, ...(change.updatedAt ? {} : {updatedAt: serverTimestamp()})}));
  }
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {validForSeconds: 7776000}));
  assert.equal((await getDoc(currentRef)).data().validForSeconds, 7776000);
  assert.equal((await getDoc(currentRef)).data().code, inviteCodeA);
});

test("conjunto 4 ampliado: legacy mantiene 14 días y se edita sin migración destructiva", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const createdAt = Timestamp.fromMillis(Date.now() - 13 * 86400000);
  await seedInvitationDisabled("course", inviteCodeA, {createdAt});
  await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeA)));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {status: "paused"}));
  await assertPermissionDenied(getDoc(doc(student, "course_invites", inviteCodeA)));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {status: "active"}));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {validForSeconds: 30 * 86400}));
  const current = (await getDoc(doc(teacher, "courses", "course", "invitation", "current"))).data();
  assert.equal(current.code, inviteCodeA);
  assert.deepEqual(current.createdAt, createdAt);
  await assertSucceeds(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
});

test("conjunto 4 ampliado: vencido no admite solicitudes edición ni reactivación", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const createdAt = Timestamp.fromMillis(Date.now() - 15 * 86400000);
  await seedInvitationDisabled("course", inviteCodeA, {createdAt, status: "paused"});
  await assertPermissionDenied(changeInvitationAtomically(teacher, "course", {status: "active"}));
  await assertPermissionDenied(changeInvitationAtomically(teacher, "course", {validForSeconds: 30 * 86400}));
  await assertPermissionDenied(getDoc(doc(student, "course_invites", inviteCodeA)));
  await assertPermissionDenied(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {status: "inactive"}));
  await assertSucceeds(renewInvitationAtomically(teacher, "course", inviteCodeB));
  await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeB)));
});

test("conjunto 4 ampliado: ficha abierta se revalida tras renovar desactivar o acortar", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeA)));
  await assertSucceeds(renewInvitationAtomically(teacher, "course", inviteCodeB));
  await assertPermissionDenied(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  await assertSucceeds(getDoc(doc(student, "course_invites", inviteCodeB)));
  await assertSucceeds(changeInvitationAtomically(teacher, "course", {status: "inactive"}));
  await assertPermissionDenied(submitJoinRequestAtomically(student, "course", "student", inviteCodeB));
  // Current one-hour lifetime elapsed after the earlier preview. Server time wins.
  await seedInvitationDisabled("course", inviteCodeA, {createdAt: Timestamp.fromMillis(Date.now() - 2 * 3600000)});
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), "courses", "course", "invitation", "current"), {validForSeconds: 3600});
  });
  await assertPermissionDenied(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  assert.equal((await getDoc(doc(student, "courses", "course", "join_requests", "student"))).exists(), false);
});

test("conjunto 4 ampliado: otro docente admin y estudiante no gestionan invitaciones ajenas", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("other", "other@example.test", ["teacher"]);
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  for (const [uid, email] of [["other","other@example.test"], ["admin","admin@example.test"], ["student","student@example.test"]]) {
    const db = userContext(uid, email, true);
    for (const change of [{status:"paused"}, {status:"inactive"}, {status:"active"}, {validForSeconds:7200}]) {
      await assertPermissionDenied(updateDoc(doc(db, "courses", "course", "invitation", "current"), {...change, updatedAt:serverTimestamp()}));
    }
    await assertPermissionDenied(renewInvitationAtomically(db, "course", inviteCodeB));
  }
});

test("conjunto 5: retiro y reincorporación guardan historial atómico y revocan acceso", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course", [courseBlock()], courseRangeAroundBogotaToday());
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = await publishStudent("student", "student@example.test");
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  const blockId = courseBlock().id;
  await assertSucceeds(setDoc(
    enrollmentRef,
    enrollmentData("student", "teacher", "student@example.test", profile("student@example.test"), {
      effectiveStartDate: bogotaToday(),
    }),
  ));
  const createdAt = (await getDoc(enrollmentRef)).data().createdAt;

  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher, "course", "student", "withdraw-1", "withdrawn",
  ));
  const withdrawn = (await assertSucceeds(getDoc(enrollmentRef))).data();
  const withdrawalEvent = (await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
    "withdraw-1",
  )))).data();
  assert.equal(withdrawn.status, "withdrawn");
  assert.equal(withdrawn.lastStatusEventId, "withdraw-1");
  assert.deepEqual(withdrawn.createdAt, createdAt);
  assert.equal(withdrawalEvent.fromStatus, "active");
  assert.equal(withdrawalEvent.toStatus, "withdrawn");
  assert.equal(withdrawalEvent.changedBy, "teacher");
  assert.deepEqual(withdrawn.lastStatusChangedAt, withdrawalEvent.changedAt);
  await assertPermissionDenied(getDoc(doc(student, "courses", "course")));
  await assertPermissionDenied(getDoc(doc(student, "courses", "course", "weekly_blocks", blockId)));
  assert.equal((await assertSucceeds(getDocs(query(
    collectionGroup(student, "enrollments"),
    where("studentUid", "==", "student"),
    where("status", "==", "active"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  )))).size, 0);
  assert.equal((await assertSucceeds(getDoc(doc(
    student,
    "courses",
    "course",
    "enrollments",
    "student",
  )))).data().status, "withdrawn");
  await assertPermissionDenied(getDoc(doc(
    student,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
    "withdraw-1",
  )));

  const activeTeacherList = await assertSucceeds(getDocs(query(
    collection(teacher, "courses", "course", "enrollments"),
    where("status", "==", "active"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  )));
  const withdrawnTeacherList = await assertSucceeds(getDocs(query(
    collection(teacher, "courses", "course", "enrollments"),
    where("status", "==", "withdrawn"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  )));
  assert.equal(activeTeacherList.size, 0);
  assert.equal(withdrawnTeacherList.size, 1);
  assert.equal((await assertSucceeds(getCountFromServer(query(
    collection(teacher, "courses", "course", "enrollments"),
    where("status", "==", "active"),
  )))).data().count, 0);

  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher, "course", "student", "reinstate-1", "active",
  ));
  const activeAgain = (await assertSucceeds(getDoc(enrollmentRef))).data();
  assert.equal(activeAgain.status, "active");
  assert.equal(activeAgain.lastStatusEventId, "reinstate-1");
  assert.deepEqual(activeAgain.createdAt, createdAt);
  assert.equal((await assertSucceeds(getDoc(doc(student, "courses", "course")))).data().subject, "Bases de Datos");
  assert.equal((await assertSucceeds(getDoc(doc(student, "courses", "course", "weekly_blocks", blockId)))).data().weekday, 1);
  await assertPermissionDenied(changeEnrollmentStatusAtomically(
    teacher, "course", "student", "withdraw-1", "withdrawn",
  ));
  assert.equal((await assertSucceeds(getDoc(enrollmentRef))).data().status, "active");
  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher, "course", "student", "withdraw-2", "withdrawn",
  ));
  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher, "course", "student", "reinstate-2", "active",
  ));
  const twiceActive = (await assertSucceeds(getDoc(enrollmentRef))).data();
  assert.equal(twiceActive.status, "active");
  assert.equal(twiceActive.lastStatusEventId, "reinstate-2");
  assert.deepEqual(twiceActive.createdAt, createdAt);
  const history = await assertSucceeds(getDocs(collection(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
  )));
  assert.deepEqual(new Set(history.docs.map((event) => event.id)), new Set([
    "withdraw-1",
    "reinstate-1",
    "withdraw-2",
    "reinstate-2",
  ]));
  const eventsById = Object.fromEntries(history.docs.map((event) => [event.id, event.data()]));
  assert.deepEqual(
    ["withdraw-1", "reinstate-1", "withdraw-2", "reinstate-2"].map((id) => [
      eventsById[id].fromStatus,
      eventsById[id].toStatus,
    ]),
    [
      ["active", "withdrawn"],
      ["withdrawn", "active"],
      ["active", "withdrawn"],
      ["withdrawn", "active"],
    ],
  );
  await assertPermissionDenied(getDocs(collection(
    student,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
  )));
  await assertPermissionDenied(updateDoc(doc(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
    "withdraw-1",
  ), { toStatus: "active" }));
  await assertPermissionDenied(deleteDoc(doc(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
    "withdraw-1",
  )));
  await assertPermissionDenied(deleteDoc(enrollmentRef));
});

test("conjunto 5: solo el docente verificado dueño puede cambiar el estado", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("other-teacher", "other-teacher@example.test", ["teacher"]);
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course", [courseBlock()], courseRangeAroundBogotaToday());
  const teacher = userContext("teacher", "teacher@example.test", true);
  const otherTeacher = userContext("other-teacher", "other-teacher@example.test", true);
  const admin = userContext("admin", "admin@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const unverifiedTeacher = userContext("teacher", "teacher@example.test", false);
  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  await publishStudent("student", "student@example.test");
  await assertSucceeds(setDoc(enrollmentRef, enrollmentData(
    "student",
    "teacher",
    "student@example.test",
    profile("student@example.test"),
    { effectiveStartDate: bogotaToday() },
  )));

  for (const [db, actor] of [
    [otherTeacher, "other-teacher"],
    [admin, "admin"],
    [student, "student"],
    [unverifiedTeacher, "teacher"],
    [anonymous, "anonymous"],
  ]) {
    await assertPermissionDenied(changeEnrollmentStatusAtomically(
      db,
      "course",
      "student",
      `denied-${actor}`,
      "withdrawn",
      { changedBy: actor },
    ));
  }
  await assertPermissionDenied(updateDoc(enrollmentRef, { status: "withdrawn" }));
  await assertPermissionDenied(setDoc(doc(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
    "event-alone",
  ), {
    fromStatus: "active",
    toStatus: "withdrawn",
    effectiveDate: bogotaToday(),
    changedAt: serverTimestamp(),
    changedBy: "teacher",
  }));
  assert.equal((await assertSucceeds(getDoc(enrollmentRef))).data().status, "active");
  assert.equal((await assertSucceeds(getDocs(collection(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
  )))).size, 0);
});

test("conjunto 5: cambios rechazan eventos falsos, snapshots alterados y transiciones inválidas", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course", [courseBlock()], courseRangeAroundBogotaToday());
  const teacher = userContext("teacher", "teacher@example.test", true);
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  await publishStudent("student", "student@example.test");
  await assertSucceeds(setDoc(enrollmentRef, enrollmentData(
    "student",
    "teacher",
    "student@example.test",
    profile("student@example.test"),
    { effectiveStartDate: bogotaToday() },
  )));

  const invalidChanges = [
    { nextStatus: "active", operationId: "same-status" },
    { nextStatus: "pending", operationId: "invalid-status" },
    { nextStatus: "withdrawn", operationId: "wrong-actor", options: { eventPatch: { changedBy: "student" } } },
    { nextStatus: "withdrawn", operationId: "wrong-origin", options: { eventPatch: { fromStatus: "withdrawn" } } },
    { nextStatus: "withdrawn", operationId: "client-time", options: { eventPatch: { changedAt: Timestamp.now() } } },
    { nextStatus: "withdrawn", operationId: "extra-event", options: { eventPatch: { reason: "extra" } } },
    { nextStatus: "withdrawn", operationId: "changed-created", options: { enrollmentPatch: { createdAt: Timestamp.now() } } },
    { nextStatus: "withdrawn", operationId: "changed-name", options: { enrollmentPatch: { name: "Identidad alterada" } } },
    { nextStatus: "withdrawn", operationId: "changed-owner", options: { enrollmentPatch: { ownerUid: "other" } } },
    { nextStatus: "withdrawn", operationId: "wrong-event-id", options: { enrollmentPatch: { lastStatusEventId: "different" } } },
    { nextStatus: "withdrawn", operationId: "client-change-time", options: { enrollmentPatch: { lastStatusChangedAt: Timestamp.now() } } },
  ];
  for (const invalid of invalidChanges) {
    await assertPermissionDenied(changeEnrollmentStatusAtomically(
      teacher,
      "course",
      "student",
      invalid.operationId,
      invalid.nextStatus,
      invalid.options,
    ));
  }
  await assertPermissionDenied(setDoc(
    enrollmentRef,
    enrollmentData("student", "teacher", "student@example.test", profile("student@example.test"), {
      status: "withdrawn",
    }),
  ));
  await assertPermissionDenied(setDoc(
    doc(teacher, "courses", "course", "enrollments", "student-2"),
    enrollmentData("student-2", "teacher", "student@example.test", profile("student@example.test"), {
      lastStatusEventId: "forged",
      lastStatusChangedAt: serverTimestamp(),
    }),
  ));
  assert.equal((await assertSucceeds(getDoc(enrollmentRef))).data().status, "active");
  assert.equal((await assertSucceeds(getDocs(collection(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
    "status_events",
  )))).size, 0);
});

test("conjunto 5: código y aprobación no reactivan un enrollment retirado", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course", [courseBlock()], courseRangeAroundBogotaToday());
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = await publishStudent("student", "student@example.test");
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  await assertSucceeds(setDoc(enrollmentRef, enrollmentData(
    "student",
    "teacher",
    "student@example.test",
    profile("student@example.test"),
    { effectiveStartDate: bogotaToday() },
  )));
  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher, "course", "student", "withdraw-before-code", "withdrawn",
  ));

  assert.equal(await assertSucceeds(submitJoinRequestAtomically(
    student, "course", "student", inviteCodeA,
  )), "already-enrolled");
  assert.equal((await assertSucceeds(getDoc(doc(
    student,
    "courses",
    "course",
    "join_requests",
    "student",
  )))).exists(), false);

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "courses", "course", "join_requests", "student"),
      joinRequestData("student", "student@example.test", inviteCodeA),
    );
  });
  await assertPermissionDenied(decideJoinRequestAtomically(
    teacher,
    "course",
    "student",
    "teacher",
    { status: "approved" },
  ));
  assert.equal((await assertSucceeds(getDoc(enrollmentRef))).data().status, "withdrawn");
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "join_requests",
    "student",
  )))).data().status, "pending");
  await assertPermissionDenied(setDoc(
    enrollmentRef,
    enrollmentData("student", "teacher", "student@example.test"),
  ));
});

test("conjunto 7: docente autoriza pendientes y collectionGroup exige identidad y filtros completos", async () => {
  const owner = userContext("teacher", "teacher@example.test", true);
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student-a", "student-a@example.test");
  await seedProfile("student-b", "student-b@example.test", ["student"], {
    studentCode: "STU-002",
  });
  await seedProfile("outsider", "outsider@example.test", ["student"], {
    studentCode: "STU-003",
  });
  await seedCourse("teacher", "course-a");
  const studentA = userContext("student-a", "student-a@example.test", true);
  const studentB = userContext("student-b", "student-b@example.test", true);
  const outsider = userContext("outsider", "outsider@example.test", true);
  const unverified = userContext("student-a", "student-a@example.test", false);

  await assertSucceeds(createPendingEnrollment(owner, "course-a", "student-a@example.test"));
  await assertSucceeds(createPendingEnrollment(owner, "course-a", "student-b@example.test", {
    studentCode: "STU-002",
    name: "Otra estudiante",
  }));
  await assertPermissionDenied(createPendingEnrollment(owner, "course-a", "mismatch@example.test", {
    email: "other@example.test",
  }));

  const ownCourseQueue = query(
    collection(owner, "courses", "course-a", "pending_enrollments"),
    where("status", "==", "pending"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  );
  assert.equal((await assertSucceeds(getDocs(ownCourseQueue))).size, 2);

  const ownStudentQueue = query(
    collectionGroup(studentA, "pending_enrollments"),
    where("email", "==", "student-a@example.test"),
    where("studentCode", "==", "STU-001"),
    where("status", "==", "pending"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  );
  const visible = await assertSucceeds(getDocs(ownStudentQueue));
  assert.equal(visible.size, 1);
  assert.equal(visible.docs[0].id, "student-a@example.test");
  assert.equal(
    (await assertSucceeds(getDoc(doc(
      studentA,
      "courses",
      "course-a",
      "pending_enrollments",
      "student-a@example.test",
    )))).data().status,
    "pending",
  );
  await assertPermissionDenied(getDoc(doc(
    studentA,
    "courses",
    "course-a",
    "pending_enrollments",
    "student-b@example.test",
  )));

  const studentWithoutEmail = query(
    collectionGroup(studentA, "pending_enrollments"),
    where("studentCode", "==", "STU-001"),
    where("status", "==", "pending"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  );
  const studentWithoutCode = query(
    collectionGroup(studentA, "pending_enrollments"),
    where("email", "==", "student-a@example.test"),
    where("status", "==", "pending"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  );
  const studentWithoutStatus = query(
    collectionGroup(studentA, "pending_enrollments"),
    where("email", "==", "student-a@example.test"),
    where("studentCode", "==", "STU-001"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  );
  await assertPermissionDenied(getDocs(studentWithoutEmail));
  await assertPermissionDenied(getDocs(studentWithoutCode));
  await assertPermissionDenied(getDocs(studentWithoutStatus));
  await assertPermissionDenied(getDocs(query(
    collectionGroup(studentB, "pending_enrollments"),
    where("email", "==", "student-a@example.test"),
    where("studentCode", "==", "STU-001"),
    where("status", "==", "pending"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  )));
  await assertPermissionDenied(getDocs(query(
    collectionGroup(unverified, "pending_enrollments"),
    where("email", "==", "student-a@example.test"),
    where("studentCode", "==", "STU-001"),
    where("status", "==", "pending"),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
  )));
  await assertPermissionDenied(getDocs(collection(
    outsider,
    "courses",
    "course-a",
    "pending_enrollments",
  )));
});

test("conjunto 7: cambios pending requieren evento atómico y permiten cancelar tramo futuro hoy", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("future-student", "future-student@example.test");
  await seedProfile("old-student", "old-student@example.test", ["student"], {
    studentCode: "STU-004",
  });
  await seedCourse("teacher", "future-course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const futureStudent = userContext("future-student", "future-student@example.test", true);
  const today = bogotaToday();
  const tomorrow = Timestamp.fromMillis(today.toMillis() + 86400000);
  const courseStart = Timestamp.fromDate(new Date("2027-01-04T00:00:00.000Z"));
  const futureRef = doc(
    teacher,
    "courses",
    "future-course",
    "pending_enrollments",
    "future-student@example.test",
  );
  await assertSucceeds(createPendingEnrollment(teacher, "future-course", "future-student@example.test"));
  await assertPermissionDenied(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "missing-original-start",
    "withdrawn",
    today,
    { omitFromEffectiveStartDate: true },
  ));
  await assertPermissionDenied(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "wrong-original-start",
    "withdrawn",
    today,
    { fromEffectiveStartDate: Timestamp.fromMillis(courseStart.toMillis() + 86400000) },
  ));

  await assertPermissionDenied(setDoc(doc(
    teacher,
    "courses",
    "future-course",
    "pending_enrollments",
    "future-student@example.test",
    "status_events",
    "orphan-event",
  ), {
    fromStatus: "pending",
    toStatus: "withdrawn",
    effectiveDate: today,
    changedAt: serverTimestamp(),
    changedBy: "teacher",
  }));
  await assertPermissionDenied(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "past-before-authorization",
    "withdrawn",
    Timestamp.fromMillis(today.toMillis() - 86400000),
  ));
  await assertPermissionDenied(updateDoc(futureRef, {
    status: "withdrawn",
  }));
  await assertSucceeds(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "cancel-future-pending-today",
    "withdrawn",
    today,
  ));
  await assertPermissionDenied(linkPendingEnrollmentAtomically(
    futureStudent,
    "future-course",
    "future-student@example.test",
    "future-student",
    { operationId: "link" },
  ));
  assert.equal((await assertSucceeds(getDoc(doc(
    futureStudent,
    "courses",
    "future-course",
    "enrollments",
    "future-student",
  )))).exists(), false);
  await assertPermissionDenied(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "reopen-after-future-start",
    "pending",
    Timestamp.fromMillis(courseStart.toMillis() + 86400000),
  ));
  await assertSucceeds(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "reopen-on-start",
    "pending",
    courseStart,
  ));
  // This transaction writes pending + event but deliberately omits the
  // canonical enrollment; the reciprocal link rule must reject it.
  await assertPermissionDenied(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "link",
    "linked",
    courseStart,
  ));
  await assertPermissionDenied(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "future-withdrawal-date",
    "withdrawn",
    tomorrow,
  ));
  await assertSucceeds(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "future-student@example.test",
    "cancel-reopened-future-pending-today",
    "withdrawn",
    today,
  ));
  const pending = (await assertSucceeds(getDoc(futureRef))).data();
  assert.equal(pending.status, "withdrawn");
  assert.equal(pending.effectiveStartDate.toMillis(), courseStart.toMillis());
  const events = await assertSucceeds(getDocs(collection(
    teacher,
    "courses",
    "future-course",
    "pending_enrollments",
    "future-student@example.test",
    "status_events",
  )));
  assert.equal(events.size, 3);
  await assertPermissionDenied(updateDoc(doc(
    teacher,
    "courses",
    "future-course",
    "pending_enrollments",
    "future-student@example.test",
    "status_events",
    "cancel-future-pending-today",
  ), { toStatus: "pending" }));

  await assertSucceeds(createPendingEnrollment(teacher, "future-course", "old-student@example.test", {
    studentCode: "STU-004",
  }));
  await assertPermissionDenied(changePendingEnrollmentAtomically(
    teacher,
    "future-course",
    "old-student@example.test",
    "no-future-date",
    "withdrawn",
    tomorrow,
  ));
  assert.equal(
    (await assertSucceeds(getDoc(doc(
      teacher,
      "courses",
      "future-course",
      "pending_enrollments",
      "old-student@example.test",
    )))).data().status,
    "pending",
  );
});

test("conjunto 7: altas, retiros y reincorporaciones conservan fecha efectiva sin retiros futuros", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedCourse("teacher", "course", [courseBlock()], {
    startDate: Timestamp.fromDate(new Date("2027-01-04T00:00:00.000Z")),
    endDate: Timestamp.fromDate(new Date("2027-01-31T00:00:00.000Z")),
  });
  const teacher = userContext("teacher", "teacher@example.test", true);
  const courseStart = Timestamp.fromDate(new Date("2027-01-04T00:00:00.000Z"));
  const today = bogotaToday();
  const tomorrow = Timestamp.fromMillis(today.toMillis() + 86400000);
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "future-student");
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "courses", "course", "enrollments", "future-student"),
      enrollmentData(
        "future-student",
        "teacher",
        "future-student@example.test",
        profile("future-student@example.test"),
        { effectiveStartDate: courseStart },
      ),
    );
  });

  await assertPermissionDenied(changeEnrollmentStatusAtomically(
    teacher,
    "course",
    "future-student",
    "withdraw-before-created",
    "withdrawn",
    { eventPatch: { effectiveDate: Timestamp.fromMillis(today.toMillis() - 86400000) } },
  ));
  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher,
    "course",
    "future-student",
    "withdraw-future-enrollment-today",
    "withdrawn",
    { eventPatch: { effectiveDate: today } },
  ));
  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher,
    "course",
    "future-student",
    "restore-on-course-start",
    "active",
    { eventPatch: { effectiveDate: courseStart } },
  ));
  await assertPermissionDenied(changeEnrollmentStatusAtomically(
    teacher,
    "course",
    "future-student",
    "future-retirement-date",
    "withdrawn",
    { eventPatch: { effectiveDate: tomorrow } },
  ));
  await assertSucceeds(changeEnrollmentStatusAtomically(
    teacher,
    "course",
    "future-student",
    "withdraw-again-today",
    "withdrawn",
    { eventPatch: { effectiveDate: today } },
  ));
  assert.equal((await assertSucceeds(getDoc(enrollmentRef))).data().status, "withdrawn");
});

test("conjunto 7: link estudiantil concilia pending y solo resuelve solicitud C4 coincidente", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedProfile("mismatch", "mismatch@example.test", ["student"], {
    studentCode: "STU-005",
  });
  await seedCourse("teacher", "course", [courseBlock()], courseRangeAroundBogotaToday());
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const mismatch = userContext("mismatch", "mismatch@example.test", true);
  const courseRef = doc(teacher, "courses", "course");
  const course = (await assertSucceeds(getDoc(courseRef))).data();

  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(createPendingEnrollment(teacher, "course", "student@example.test"));
  const originalStartDate = (await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "pending_enrollments",
    "student@example.test",
  )))).data().effectiveStartDate;
  assert.equal(await assertSucceeds(submitJoinRequestAtomically(
    student,
    "course",
    "student",
    inviteCodeA,
  )), "created");
  await assertPermissionDenied(updateDoc(doc(
    student,
    "courses",
    "course",
    "pending_enrollments",
    "student@example.test",
  ), {
    status: "linked",
    studentUid: "student",
    linkedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    lastEventId: "link",
    lastStatusChangedAt: serverTimestamp(),
  }));
  await assertPermissionDenied(linkPendingEnrollmentAtomically(
    student,
    "course",
    "student@example.test",
    "student",
    { operationId: "link", omitFromEffectiveStartDate: true },
  ));
  await assertPermissionDenied(linkPendingEnrollmentAtomically(
    student,
    "course",
    "student@example.test",
    "student",
    {
      operationId: "link",
      fromEffectiveStartDate: Timestamp.fromMillis(originalStartDate.toMillis() + 86400000),
    },
  ));
  assert.equal(await assertSucceeds(linkPendingEnrollmentAtomically(
    student,
    "course",
    "student@example.test",
    "student",
    { operationId: "link" },
  )), "linked");
  assert.equal((await assertSucceeds(getDoc(doc(
    student,
    "courses",
    "course",
    "join_requests",
    "student",
  )))).data().status, "approved");
  const linkedEnrollment = (await assertSucceeds(getDoc(doc(
    student,
    "courses",
    "course",
    "enrollments",
    "student",
  )))).data();
  assert.equal(linkedEnrollment.status, "active");
  assert.equal(linkedEnrollment.name, "Usuario de prueba");
  assert.equal(linkedEnrollment.rosterEntryId, "student@example.test");
  assert.equal(linkedEnrollment.effectiveStartDate.toMillis(), course.startDate.toMillis());
  assert.deepEqual(
    (await assertSucceeds(getDoc(doc(student, "users", "student")))).data().roles,
    ["student"],
  );

  await assertSucceeds(createPendingEnrollment(teacher, "course", "mismatch@example.test", {
    studentCode: "STU-005",
  }));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "courses", "course", "join_requests", "mismatch"),
      joinRequestData("mismatch", "mismatch@example.test", inviteCodeA, {
        name: "Nombre distinto",
        studentCode: "STU-005",
      }),
    );
  });
  assert.equal(await assertSucceeds(linkPendingEnrollmentAtomically(
    mismatch,
    "course",
    "mismatch@example.test",
    "mismatch",
    { operationId: "link" },
  )), "linked");
  const mismatchRequestRef = doc(
    mismatch,
    "courses",
    "course",
    "join_requests",
    "mismatch",
  );
  const mismatchRequest = (await assertSucceeds(getDoc(mismatchRequestRef))).data();
  assert.equal(mismatchRequest.status, "approved");
  assert.equal(mismatchRequest.name, "Nombre distinto");
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "pending_enrollments",
    "mismatch@example.test",
  )))).data().name, "Usuario de prueba");

  await seedProfile("wrong-code", "wrong-code@example.test", ["student"], {
    studentCode: "STU-006",
  });
  await assertSucceeds(createPendingEnrollment(teacher, "course", "wrong-code@example.test", {
    studentCode: "STU-006",
  }));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "courses", "course", "join_requests", "wrong-code"),
      joinRequestData("wrong-code", "wrong-code@example.test", inviteCodeA, {
        studentCode: "STU-999",
      }),
    );
  });
  const wrongCodeStudent = userContext("wrong-code", "wrong-code@example.test", true);
  assert.equal(await assertSucceeds(linkPendingEnrollmentAtomically(
    wrongCodeStudent,
    "course",
    "wrong-code@example.test",
    "wrong-code",
    { operationId: "link" },
  )), "linked");
  assert.equal((await assertSucceeds(getDoc(doc(
    wrongCodeStudent,
    "courses",
    "course",
    "join_requests",
    "wrong-code",
  )))).data().status, "pending");
  await assertPermissionDenied(decideJoinRequestAtomically(
    teacher,
    "course",
    "wrong-code",
    "teacher",
    { status: "approved" },
  ));

  await seedProfile("legacy-student", "legacy-student@example.test", ["student"], {
    studentCode: "STU-006",
  });
  await assertSucceeds(createPendingEnrollment(teacher, "course", "legacy-student@example.test", {
    studentCode: "STU-006",
    name: "Roster Legacy",
  }));
  const legacyCreatedAt = Timestamp.fromDate(new Date("2026-01-10T12:00:00.000Z"));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
      context.firestore(),
      "courses",
      "course",
      "enrollments",
      "legacy-student",
    ), {
      studentUid: "legacy-student",
      ownerUid: "teacher",
      name: "Nombre histórico conservado",
      email: "legacy-student@example.test",
      studentCode: "STU-006",
      subject: course.subject,
      group: course.group,
      period: course.period,
      status: "active",
      createdAt: legacyCreatedAt,
    });
  });
  const legacyStudent = userContext("legacy-student", "legacy-student@example.test", true);
  assert.equal(await assertSucceeds(linkPendingEnrollmentAtomically(
    legacyStudent,
    "course",
    "legacy-student@example.test",
    "legacy-student",
    { operationId: "link" },
  )), "linked");
  const legacyAfterLink = (await assertSucceeds(getDoc(doc(
    legacyStudent,
    "courses",
    "course",
    "enrollments",
    "legacy-student",
  )))).data();
  assert.equal(legacyAfterLink.createdAt.toMillis(), legacyCreatedAt.toMillis());
  assert.equal(legacyAfterLink.name, "Nombre histórico conservado");
  assert.equal("rosterEntryId" in legacyAfterLink, false);
  assert.equal("effectiveStartDate" in legacyAfterLink, false);
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "pending_enrollments",
    "legacy-student@example.test",
  )))).data().name, "Roster Legacy");

  await assertSucceeds(createPendingEnrollment(teacher, "course", "unverified@example.test"));
  await seedProfile("unverified", "unverified@example.test");
  const unverified = userContext("unverified", "unverified@example.test", false);
  await assertPermissionDenied(linkPendingEnrollmentAtomically(
    unverified,
    "course",
    "unverified@example.test",
    "unverified",
    { operationId: "link" },
  ));
});

test("conjunto 7: matrícula manual enlaza pending y decisión C4 en la misma transacción", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = userContext("student", "student@example.test", true);
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  await assertSucceeds(createPendingEnrollment(teacher, "course", "student@example.test"));
  await assertSucceeds(submitJoinRequestAtomically(student, "course", "student", inviteCodeA));
  await assertSucceeds(publishStudent("student", "student@example.test"));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(
      context.firestore(),
      "courses",
      "course",
      "join_requests",
      "student",
    ), { name: "Nombre orientativo distinto" });
  });

  const pending = (await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "pending_enrollments",
    "student@example.test",
  )))).data();
  await assertPermissionDenied(setDoc(
    doc(teacher, "courses", "course", "enrollments", "student"),
    enrollmentData("student", "teacher", "student@example.test", {
      name: pending.name,
      email: pending.email,
      studentCode: pending.studentCode,
    }, {
      subject: pending.subject,
      group: pending.group,
      period: pending.period,
      effectiveStartDate: pending.effectiveStartDate,
    }),
  ));

  assert.equal(await assertSucceeds(enrollManuallyAndReconcilePending(
    teacher,
    "course",
    "student",
    "student@example.test",
    "link",
  )), "student");
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "pending_enrollments",
    "student@example.test",
  )))).data().status, "linked");
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "join_requests",
    "student",
  )))).data().status, "approved");
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "join_requests",
    "student",
  )))).data().name, "Nombre orientativo distinto");
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
  )))).data().status, "active");
  assert.equal((await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "enrollments",
    "student",
  )))).data().name, "Usuario de prueba");
  assert.equal((await assertSucceeds(getDocs(collection(
    teacher,
    "courses",
    "course",
    "pending_enrollments",
    "student@example.test",
    "status_events",
  )))).size, 1);
});

test("conjunto 7: los eventos históricos de cinco campos siguen siendo legibles", async () => {
  await seedProfile("teacher", "teacher@example.test", ["teacher"]);
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const today = bogotaToday();
  await assertSucceeds(createPendingEnrollment(teacher, "course", "legacy@example.test"));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
      context.firestore(),
      "courses",
      "course",
      "pending_enrollments",
      "legacy@example.test",
      "status_events",
      "legacy-five-fields",
    ), {
      fromStatus: "pending",
      toStatus: "withdrawn",
      effectiveDate: today,
      changedAt: today,
      changedBy: "teacher",
    });
  });

  const legacyEvent = (await assertSucceeds(getDoc(doc(
    teacher,
    "courses",
    "course",
    "pending_enrollments",
    "legacy@example.test",
    "status_events",
    "legacy-five-fields",
  )))).data();
  assert.deepEqual(Object.keys(legacyEvent).sort(), [
    "changedAt",
    "changedBy",
    "effectiveDate",
    "fromStatus",
    "toStatus",
  ]);
});

test("conjunto 8: attendance privado solo es legible por docente verificado dueño", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("other", "other@example.test", ["teacher"]);
  await seedProfile("admin", "admin@example.test", ["admin"]);
  await seedProfile("student", "student@example.test", ["student"]);
  await seedCourse("owner", "course");
  await seedAttendanceConfig("course", "owner");
  await seedAttendanceSession("course", "owner", "session", {
    status: "finalized",
    rosterState: "ready",
    finalizedAt: attendanceDate(-1),
  });

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const date = Timestamp.fromDate(new Date("2027-01-05T00:00:00.000Z"));
    await setDoc(doc(db, "courses", "course", "attendance_calendar", "calendar-1"), {
      occurrenceId: "calendar-1",
      kind: "additional",
      originalDate: date,
      effectiveDate: date,
      startMinute: 480,
      endMinute: 540,
      reason: "Recuperación",
      version: 1,
      createdAt: date,
      createdBy: "owner",
      updatedAt: date,
      updatedBy: "owner",
    });
    await setDoc(doc(db, "courses", "course", "attendance_sessions", "session", "segments", "seg-1"), {
      segmentId: "seg-1", order: 0, startMinute: 480, endMinute: 540,
      durationMinutes: 60, createdAt: date,
    });
    await setDoc(doc(db, "courses", "course", "attendance_sessions", "session", "roster", "student@example.test"),
      attendanceRosterEntry("student@example.test", { updatedBy: "owner" }));
    await setDoc(doc(db, "courses", "course", "attendance_sessions", "session", "events", "event-1"), {
      kind: "correction",
      rosterEntryId: "student@example.test",
      oldValue: { meetingMark: "present" },
      newValue: { meetingMark: "absent" },
      reason: "Corrección auditada",
      changedAt: date,
      changedBy: "owner",
    });
    await setDoc(doc(db, "courses", "course", "attendance_records", "session|student@example.test"),
      attendanceRecordData("course", "session", "student@example.test"));
  });

  const owner = userContext("owner", "owner@example.test", true);
  const other = userContext("other", "other@example.test", true);
  const unverifiedOwner = userContext("owner", "owner@example.test", false);
  const adminOnly = userContext("admin", "admin@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const paths = [
    ["courses", "course", "attendance_config", "current"],
    ["courses", "course", "attendance_calendar", "calendar-1"],
    ["courses", "course", "attendance_sessions", "session"],
    ["courses", "course", "attendance_sessions", "session", "segments", "seg-1"],
    ["courses", "course", "attendance_sessions", "session", "roster", "student@example.test"],
    ["courses", "course", "attendance_sessions", "session", "events", "event-1"],
    ["courses", "course", "attendance_records", "session|student@example.test"],
  ];
  for (const path of paths) {
    await assertSucceeds(getDoc(doc(owner, ...path)));
    await assertPermissionDenied(getDoc(doc(other, ...path)));
    await assertPermissionDenied(getDoc(doc(unverifiedOwner, ...path)));
    await assertPermissionDenied(getDoc(doc(adminOnly, ...path)));
    await assertPermissionDenied(getDoc(doc(student, ...path)));
  }
  await assertSucceeds(getDocs(collection(owner, "courses", "course", "attendance_sessions")));
  await assertPermissionDenied(getDocs(collection(other, "courses", "course", "attendance_sessions")));
  await assertPermissionDenied(getDocs(collection(student, "courses", "course", "attendance_sessions")));
  await assertPermissionDenied(getDocs(collection(student, "courses", "course", "attendance_sessions", "session", "roster")));
  await assertPermissionDenied(getDocs(collection(student, "courses", "course", "attendance_sessions", "session", "events")));
});

test("conjunto 8: curso nuevo conserva configuración atómica y sesión incrementa lastSessionId", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  const owner = userContext("owner", "owner@example.test", true);
  await assertSucceeds(writeCourse(owner, "new-course", "owner"));
  const createdConfig = (await assertSucceeds(getDoc(doc(
    owner, "courses", "new-course", "attendance_config", "current",
  )))).data();
  assert.equal(createdConfig.sessionCount, 0);
  assert.equal(createdConfig.lastSessionId, null);

  await seedCourse("owner", "existing-course");
  await seedAttendanceConfig("existing-course", "owner");
  const configRef = doc(owner, "courses", "existing-course", "attendance_config", "current");
  const sessionRef = doc(owner, "courses", "existing-course", "attendance_sessions", "occurrence-1");
  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const configSnapshot = await transaction.get(configRef);
    const config = configSnapshot.data();
    transaction.set(sessionRef, attendanceSessionData("existing-course", "owner", "occurrence-1"));
    transaction.update(configRef, {
      sessionCount: config.sessionCount + 1,
      lastSessionId: "occurrence-1",
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
  }));
  const updatedConfig = (await assertSucceeds(getDoc(configRef))).data();
  assert.equal(updatedConfig.sessionCount, 1);
  assert.equal(updatedConfig.lastSessionId, "occurrence-1");
  assert.equal((await assertSucceeds(getDoc(sessionRef))).exists(), true);
});

test("conjunto 8: Rules rechaza incremento o sesión sin su pareja y bloquea cambiar modo usado", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedCourse("owner", "course");
  await seedAttendanceConfig("course", "owner");
  const owner = userContext("owner", "owner@example.test", true);
  const configRef = doc(owner, "courses", "course", "attendance_config", "current");
  await assertPermissionDenied(updateDoc(configRef, {
    sessionCount: 1,
    lastSessionId: "orphan-session",
    updatedAt: serverTimestamp(),
    updatedBy: "owner",
  }));
  await assertPermissionDenied(setDoc(
    doc(owner, "courses", "course", "attendance_sessions", "orphan-session"),
    attendanceSessionData("course", "owner", "orphan-session"),
  ));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), "courses", "course", "attendance_config", "current"), {
      sessionCount: 1,
      lastSessionId: "historical-session",
    });
  });
  await assertPermissionDenied(updateDoc(configRef, {
    mode: "minutes",
    updatedAt: serverTimestamp(),
    updatedBy: "owner",
  }));
});

test("conjunto 8: estudiante consulta solo su proyección publicada con filtros de identidad", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test", ["student"]);
  await seedCourse("owner", "course");
  await seedAttendanceEnrollment("course", "student", "owner", "student@example.test");
  await seedAttendanceSession("course", "owner", "final-session", {
    status: "finalized", rosterState: "ready", finalizedAt: attendanceDate(-1),
  });
  await seedAttendanceSession("course", "owner", "other-session", {
    status: "finalized", rosterState: "ready", finalizedAt: attendanceDate(-1),
  });
  await seedAttendanceSession("course", "owner", "staged-session", {
    status: "closing", rosterState: "ready",
  });
  await seedAttendanceRecord("course", "final-session", "student@example.test");
  await seedAttendanceRecord("course", "other-session", "other@example.test");
  await seedAttendanceRecord("course", "staged-session", "student@example.test", {
    visibility: "staged", publishedAt: null,
  });

  const student = userContext("student", "student@example.test", true);
  const records = collection(student, "courses", "course", "attendance_records");
  const exactQuery = query(
    records,
    where("rosterEntryId", "==", "student@example.test"),
    where("visibility", "==", "published"),
    orderBy("effectiveDate", "desc"),
    orderBy(documentId(), "desc"),
  );
  const ownPage = await assertSucceeds(getDocs(exactQuery));
  assert.equal(ownPage.size, 1);
  assert.equal(ownPage.docs[0].id, "final-session|student@example.test");
  await assertSucceeds(getDoc(doc(records, "final-session|student@example.test")));
  await assertPermissionDenied(getDoc(doc(records, "other-session|other@example.test")));
  await assertPermissionDenied(getDoc(doc(records, "staged-session|student@example.test")));
  await assertPermissionDenied(getDocs(query(records, where("rosterEntryId", "==", "student@example.test"))));
  await assertPermissionDenied(getDocs(query(records, where("visibility", "==", "published"))));

  const legacyUid = "legacy-student";
  await seedProfile(legacyUid, "legacy@example.test", ["student"]);
  await seedAttendanceEnrollment("course", legacyUid, "owner", "legacy@example.test", null);
  await seedAttendanceSession("course", "owner", "legacy-session", {
    status: "finalized", rosterState: "ready", finalizedAt: attendanceDate(-1),
  });
  await seedAttendanceRecord("course", "legacy-session", `legacy:${legacyUid}`);
  const legacy = userContext(legacyUid, "legacy@example.test", true);
  await assertSucceeds(getDoc(doc(
    legacy, "courses", "course", "attendance_records",
    `legacy-session|legacy:${legacyUid}`,
  )));
});

test("conjunto 8: publicación y lectura esperan finalización; closing y voiding quedan ocultos", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test", ["student"]);
  await seedCourse("owner", "course");
  await seedAttendanceEnrollment("course", "student", "owner", "student@example.test");
  const commonDate = attendanceDate(-1);
  await seedAttendanceSession("course", "owner", "closing-session", {
    status: "closing", rosterState: "ready", scheduledDate: commonDate,
    effectiveDate: commonDate,
  });
  await seedAttendanceSession("course", "owner", "voiding-session", {
    status: "voiding", rosterState: "ready", scheduledDate: commonDate,
    effectiveDate: commonDate, lastMutationKind: "void", lastEventId: "void-op",
    reason: "Anulada",
  });
  await seedAttendanceSession("course", "owner", "voided-session", {
    status: "voided", rosterState: "ready", scheduledDate: commonDate,
    effectiveDate: commonDate, lastMutationKind: "void", lastEventId: "void-op",
    reason: "Anulada", voidedAt: commonDate,
  });
  await seedAttendanceRecord("course", "closing-session", "student@example.test", {
    scheduledDate: commonDate, effectiveDate: commonDate,
  });
  await seedAttendanceRecord("course", "voiding-session", "student@example.test", {
    scheduledDate: commonDate, effectiveDate: commonDate,
  });
  await seedAttendanceRecord("course", "voided-session", "student@example.test", {
    scheduledDate: commonDate, effectiveDate: commonDate,
    result: "voided", unitCount: 0, absentUnits: 0, inReviewUnits: 0,
    justifiedUnits: 0,
  });

  const student = userContext("student", "student@example.test", true);
  const records = collection(student, "courses", "course", "attendance_records");
  await assertPermissionDenied(getDoc(doc(records, "closing-session|student@example.test")));
  await assertPermissionDenied(getDoc(doc(records, "voiding-session|student@example.test")));
  await assertSucceeds(getDoc(doc(records, "voided-session|student@example.test")));
});

test("conjunto 8: segmentos y nómina de minutos se crean por chunks versionados", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("other", "other@example.test", ["teacher"]);
  await seedCourse("owner", "course");
  await seedAttendanceSession("course", "owner", "minutes-session", {
    mode: "minutes", segmentIds: ["seg-1"],
    startMinute: 480, endMinute: 540, rosterCount: 1, unmarkedCount: 1,
  });
  const owner = userContext("owner", "owner@example.test", true);
  const other = userContext("other", "other@example.test", true);
  const sessionRef = doc(owner, "courses", "course", "attendance_sessions", "minutes-session");
  const segmentRef = doc(sessionRef, "segments", "seg-1");
  const rosterRef = doc(sessionRef, "roster", "student@example.test");
  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    transaction.update(sessionRef, {
      version: sessionSnapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.set(segmentRef, {
      segmentId: "seg-1", order: 0, startMinute: 480, endMinute: 540,
      durationMinutes: 60, createdAt: serverTimestamp(),
    });
  }));
  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    assert.equal(sessionSnapshot.exists(), true);
    transaction.set(rosterRef, {
      rosterEntryId: "student@example.test",
      displayName: "Estudiante de prueba",
      segments: {
        "seg-1": {
          mark: "unmarked", absentUnits: 0,
          justificationStatus: "none", justifiedUnits: 0,
        },
      },
      version: 0,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.update(sessionRef, {
      version: sessionSnapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
  }));
  await assertSucceeds(getDoc(segmentRef));
  await assertSucceeds(getDoc(rosterRef));
  await assertPermissionDenied(updateDoc(rosterRef, { displayName: "Alterado" }));
  await assertPermissionDenied(setDoc(doc(
    other, "courses", "course", "attendance_sessions", "minutes-session",
    "segments", "foreign-segment",
  ), {
    segmentId: "foreign-segment", order: 0, startMinute: 480, endMinute: 540,
    durationMinutes: 60, createdAt: serverTimestamp(),
  }));
});

test("conjunto 8: cierre confirmado actualiza dos faltantes en un chunk atómico", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedCourse("owner", "course");
  const previousDate = attendanceDate(-1);
  await seedAttendanceSession("course", "owner", "closing-batch", {
    status: "inProgress", rosterState: "ready", scheduledDate: previousDate,
    effectiveDate: previousDate, rosterCount: 2, markedCount: 0, unmarkedCount: 2,
  });
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const id of ["student-a@example.test", "student-b@example.test"]) {
      await setDoc(doc(db, "courses", "course", "attendance_sessions", "closing-batch", "roster", id),
        attendanceRosterEntry(id, { updatedBy: "owner" }));
    }
  });
  const owner = userContext("owner", "owner@example.test", true);
  const sessionRef = doc(owner, "courses", "course", "attendance_sessions", "closing-batch");
  const rowA = doc(sessionRef, "roster", "student-a@example.test");
  const rowB = doc(sessionRef, "roster", "student-b@example.test");

  await assertPermissionDenied(updateDoc(rowA, {
    meetingMark: "absent", version: 1,
    updatedAt: serverTimestamp(), updatedBy: "owner",
  }));

  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    const snapshotA = await transaction.get(rowA);
    const snapshotB = await transaction.get(rowB);
    transaction.update(sessionRef, {
      status: "closing",
      markedCount: 2,
      unmarkedCount: 0,
      unmarkedConfirmed: true,
      unmarkedConfirmedAt: serverTimestamp(),
      unmarkedConfirmedBy: "owner",
      version: sessionSnapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    for (const snapshot of [snapshotA, snapshotB]) {
      transaction.update(snapshot.ref, {
        meetingMark: "absent",
        version: snapshot.data().version + 1,
        updatedAt: serverTimestamp(),
        updatedBy: "owner",
      });
    }
  }));
  assert.equal((await assertSucceeds(getDoc(sessionRef))).data().status, "closing");
  assert.equal((await assertSucceeds(getDoc(rowA))).data().meetingMark, "absent");
  assert.equal((await assertSucceeds(getDoc(rowB))).data().meetingMark, "absent");
});

test("conjunto 8: anulación registra evento sin rosterEntryId en una transacción", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test", ["student"]);
  await seedCourse("owner", "course");
  await seedAttendanceEnrollment("course", "student", "owner", "student@example.test");
  const date = attendanceDate(-1);
  await seedAttendanceSession("course", "owner", "void-session", {
    status: "finalized", rosterState: "ready", scheduledDate: date,
    effectiveDate: date, finalizedAt: date, rosterCount: 12, markedCount: 12,
    unmarkedCount: 0,
  });
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (let index = 0; index < 12; index += 1) {
      const rosterEntryId = index === 0
        ? "student@example.test"
        : `student-${index}@example.test`;
      await setDoc(
        doc(db, "courses", "course", "attendance_records", `void-session|${rosterEntryId}`),
        attendanceRecordData("course", "void-session", rosterEntryId, {
          scheduledDate: date,
          effectiveDate: date,
          publishedAt: date,
          updatedAt: date,
        }),
      );
    }
  });
  const owner = userContext("owner", "owner@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const sessionRef = doc(owner, "courses", "course", "attendance_sessions", "void-session");
  const eventRef = doc(sessionRef, "events", "void-operation");
  const event = {
    kind: "void",
    oldValue: { status: "finalized" },
    newValue: { status: "voided" },
    reason: "La clase fue anulada",
    changedAt: serverTimestamp(),
    changedBy: "owner",
  };
  await assertPermissionDenied(updateDoc(sessionRef, {
    status: "voiding",
    reason: "La clase fue anulada",
    lastMutationKind: "void",
    lastEventId: "void-operation",
    version: 2,
    updatedAt: serverTimestamp(),
    updatedBy: "owner",
  }));
  await assertPermissionDenied(setDoc(doc(sessionRef, "events", "isolated-void"), event));

  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const snapshot = await transaction.get(sessionRef);
    transaction.update(sessionRef, {
      status: "voiding",
      reason: "La clase fue anulada",
      lastMutationRosterEntryId: null,
      lastMutationKind: "void",
      lastEventId: "void-operation",
      version: snapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.set(eventRef, event);
  }));
  assert.equal((await assertSucceeds(getDoc(eventRef))).data().kind, "void");
  const eventData = (await assertSucceeds(getDoc(eventRef))).data();
  assert.equal(Object.hasOwn(eventData, "rosterEntryId"), false);

  const studentRecordRef = doc(
    student, "courses", "course", "attendance_records",
    "void-session|student@example.test",
  );
  const studentRecords = collection(student, "courses", "course", "attendance_records");
  const ownQuery = query(
    studentRecords,
    where("rosterEntryId", "==", "student@example.test"),
    where("visibility", "==", "published"),
    orderBy("effectiveDate", "desc"),
    orderBy(documentId(), "desc"),
  );
  const whileVoiding = await assertSucceeds(getDocs(ownQuery));
  assert.equal(whileVoiding.size, 1);
  assert.equal(whileVoiding.docs[0].data().result, "present");
  await assertPermissionDenied(updateDoc(studentRecordRef, {
    result: "voided", updatedAt: serverTimestamp(),
  }));

  for (let index = 0; index < 12; index += 1) {
    const rosterEntryId = index === 0
      ? "student@example.test"
      : `student-${index}@example.test`;
    await assertSucceeds(updateDoc(doc(
      owner, "courses", "course", "attendance_records",
      `void-session|${rosterEntryId}`,
    ), {
      result: "voided",
      unitCount: 0,
      absentUnits: 0,
      inReviewUnits: 0,
      justifiedUnits: 0,
      updatedAt: serverTimestamp(),
    }));
  }
  assert.equal((await assertSucceeds(getDoc(sessionRef))).data().version, 2);
  assert.equal((await assertSucceeds(getDocs(ownQuery))).docs[0].data().result, "voided");
  await assertPermissionDenied(getDoc(studentRecordRef));

  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const snapshot = await transaction.get(sessionRef);
    transaction.update(sessionRef, {
      status: "voided",
      voidedAt: serverTimestamp(),
      version: snapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
  }));
  assert.equal((await assertSucceeds(getDoc(studentRecordRef))).data().result, "voided");
});

test("conjunto 8: justificación y corrección actualizan fila, proyección y evento atómicamente", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("other", "other@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test", ["student"]);
  await seedCourse("owner", "course");
  await seedAttendanceEnrollment("course", "student", "owner", "student@example.test");
  const date = attendanceDate(-1);
  await seedAttendanceSession("course", "owner", "audit-session", {
    status: "finalized", rosterState: "ready", scheduledDate: date,
    effectiveDate: date, finalizedAt: date, rosterCount: 1, markedCount: 1,
    unmarkedCount: 0,
  });
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(
      doc(db, "courses", "course", "attendance_sessions", "audit-session", "roster", "student@example.test"),
      attendanceRosterEntry("student@example.test", {
        meetingMark: "absent", updatedBy: "owner", version: 0,
      }),
    );
    await setDoc(
      doc(db, "courses", "course", "attendance_records", "audit-session|student@example.test"),
      attendanceRecordData("course", "audit-session", "student@example.test", {
        scheduledDate: date, effectiveDate: date, result: "absent", absentUnits: 1,
      }),
    );
  });

  const owner = userContext("owner", "owner@example.test", true);
  const other = userContext("other", "other@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const sessionRef = doc(owner, "courses", "course", "attendance_sessions", "audit-session");
  const rowRef = doc(sessionRef, "roster", "student@example.test");
  const recordRef = doc(owner, "courses", "course", "attendance_records", "audit-session|student@example.test");
  const justificationRef = doc(sessionRef, "events", "justification-1");
  const justificationEvent = {
    kind: "justification",
    rosterEntryId: "student@example.test",
    oldValue: { justificationStatus: "none", justifiedUnits: 0 },
    newValue: { justificationStatus: "justified", justifiedUnits: 1 },
    reason: "Soporte revisado",
    changedAt: serverTimestamp(),
    changedBy: "owner",
  };

  await assertPermissionDenied(setDoc(doc(sessionRef, "events", "isolated"), justificationEvent));
  await assertPermissionDenied(setDoc(doc(other, "courses", "course", "attendance_sessions", "audit-session", "events", "foreign"), {
    ...justificationEvent, changedBy: "other",
  }));

  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    const rowSnapshot = await transaction.get(rowRef);
    const recordSnapshot = await transaction.get(recordRef);
    transaction.update(sessionRef, {
      version: sessionSnapshot.data().version + 1,
      lastMutationRosterEntryId: "student@example.test",
      lastMutationKind: "justification",
      lastEventId: "justification-1",
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.update(rowRef, {
      justificationStatus: "justified",
      justifiedUnits: 1,
      version: rowSnapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.update(recordRef, {
      result: "justified",
      justifiedUnits: 1,
      updatedAt: serverTimestamp(),
    });
    transaction.set(justificationRef, justificationEvent);
    assert.equal(recordSnapshot.data().result, "absent");
  }));
  await assertPermissionDenied(updateDoc(justificationRef, { reason: "Reescrito" }));
  await assertPermissionDenied(updateDoc(rowRef, {
    justificationStatus: "notAccepted", justifiedUnits: 0,
    version: 2, updatedAt: serverTimestamp(), updatedBy: "owner",
  }));
  await assertPermissionDenied(updateDoc(doc(student, "courses", "course", "attendance_records", "audit-session|student@example.test"), {
    result: "present", updatedAt: serverTimestamp(),
  }));

  const correctionRef = doc(sessionRef, "events", "correction-1");
  const correctionEvent = {
    kind: "correction",
    rosterEntryId: "student@example.test",
    oldValue: { meetingMark: "absent" },
    newValue: { meetingMark: "present" },
    reason: "Se corrigió la marca con evidencia",
    changedAt: serverTimestamp(),
    changedBy: "owner",
  };
  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    const rowSnapshot = await transaction.get(rowRef);
    const recordSnapshot = await transaction.get(recordRef);
    transaction.update(sessionRef, {
      version: sessionSnapshot.data().version + 1,
      lastMutationRosterEntryId: "student@example.test",
      lastMutationKind: "correction",
      lastEventId: "correction-1",
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.update(rowRef, {
      meetingMark: "present",
      justificationStatus: "none",
      justifiedUnits: 0,
      version: rowSnapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.update(recordRef, {
      result: "present",
      absentUnits: 0,
      justifiedUnits: 0,
      updatedAt: serverTimestamp(),
    });
    transaction.set(correctionRef, correctionEvent);
    assert.equal(recordSnapshot.data().result, "justified");
  }));
  await assertPermissionDenied(updateDoc(correctionRef, { reason: "Reescrito" }));
});

for (const size of [2, 12]) {
test(`C8 closing rescheduled minutes: resume stage finalize publish without losing marks (${size})`, async () => {
  await seedProfile("owner", "owner@example.test", ["student", "teacher"]);
  await seedProfile("student", "student@example.test", ["student"]);
  await seedProfile("other", "other@example.test", ["student", "teacher"]);
  await seedCourse("owner", "course");
  await seedAttendanceEnrollment("course", "student", "owner", "student@example.test");
  const id = "course|block|2026-11-05";
  const scheduledDate = Timestamp.fromDate(new Date("2026-11-05T00:00:00Z"));
  const effectiveDate = Timestamp.fromDate(new Date("2026-11-16T00:00:00Z"));
  const segmentData = [360, 420].map((start, index) => ({
    segmentId: `seg-${index + 1}`, order: index, startMinute: start,
    endMinute: start + 60, durationMinutes: 60, createdAt: effectiveDate,
  }));
  await seedAttendanceSession("course", "owner", id, {
    occurrenceKind: "rescheduled", status: "closing", rosterState: "ready",
    mode: "minutes", scheduledDate, effectiveDate, startMinute: 360, endMinute: 480,
    segmentIds: segmentData.map(s => s.segmentId), rosterCount: size, markedCount: size, unmarkedCount: 0,
    lastMutationKind: "mark", lastMutationRosterEntryId: "other@example.test",
  });
  const owner = userContext("owner", "owner@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const other = userContext("other", "other@example.test", true);
  const parent = doc(owner, "courses", "course", "attendance_sessions", id);
  const identities = ["student@example.test", "other@example.test", ...Array.from({length: size - 2}, (_, i) => `synthetic-${i}@example.test`)];
  const records = identities.map(rosterEntryId => attendanceRecordData("course", id, rosterEntryId, {
    mode: "minutes", scheduledDate, effectiveDate, startMinute: 360, endMinute: 480,
    unitCount: 120, absentUnits: 60, result: "partial", visibility: "staged", publishedAt: null,
    segments: segmentData.map((s, index) => ({
      segmentId: s.segmentId, startMinute: s.startMinute, endMinute: s.endMinute,
      durationMinutes: 60, mark: index === 0 ? "absent" : "present", absentUnits: index === 0 ? 60 : 0,
      justificationStatus: "none", justifiedUnits: 0,
    })), updatedAt: serverTimestamp(),
  }));
  await testEnvironment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const s of segmentData) await setDoc(doc(db, parent.path, "segments", s.segmentId), s);
    for (const record of records) await setDoc(doc(db, parent.path, "roster", record.rosterEntryId), {
      rosterEntryId: record.rosterEntryId, displayName: "Estudiante sintético",
      segments: Object.fromEntries(record.segments.map(s => [s.segmentId, {
        mark: s.mark, absentUnits: s.absentUnits, justificationStatus: s.justificationStatus, justifiedUnits: s.justifiedUnits,
      }])), version: 2, updatedAt: effectiveDate, updatedBy: "owner",
    });
  });
  const rosterBefore = (await getDocs(collection(parent, "roster"))).docs.map(d => d.data());
  if (size === 2) {
    // Separate in-progress control: the verified owner can mark both hours.
    // The recovery fixture above remains already closing throughout the test.
    const controlId = `${id}-mark-control`;
    await seedAttendanceSession("course", "owner", controlId, {
      occurrenceKind: "rescheduled", status: "inProgress", rosterState: "ready",
      mode: "minutes", scheduledDate, effectiveDate, startMinute: 360, endMinute: 480,
      segmentIds: segmentData.map(s => s.segmentId), rosterCount: 1, markedCount: 1, unmarkedCount: 0,
    });
    const control = doc(owner, "courses", "course", "attendance_sessions", controlId);
    const row = doc(control, "roster", identities[0]);
    await testEnvironment.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), row.path), rosterBefore.find(r => r.rosterEntryId === identities[0]));
      for (const s of segmentData) await setDoc(doc(context.firestore(), control.path, "segments", s.segmentId), s);
    });
    const mark = (actor, segmentId, value) => runTransaction(actor, async tx => {
      const p = doc(actor, control.path);
      const r = doc(actor, row.path);
      const session = await tx.get(p);
      const entry = await tx.get(r);
      await tx.get(doc(actor, control.path, "segments", segmentId));
      tx.update(r, {segments: {...entry.data().segments, [segmentId]: {
        mark: value, absentUnits: value === "absent" ? 60 : 0, justificationStatus: "none", justifiedUnits: 0,
      }}, version: entry.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
      tx.update(p, {version: session.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner",
        lastMutationKind: "mark", lastMutationRosterEntryId: identities[0], lastEventId: null});
    });
    await assertSucceeds(mark(owner, "seg-1", "present"));
    await assertSucceeds(mark(owner, "seg-2", "absent"));
    await assertPermissionDenied(mark(student, "seg-1", "absent"));
    await assertPermissionDenied(mark(other, "seg-1", "absent"));
    const marked = (await getDoc(row)).data();
    assert.equal(marked.segments["seg-1"].mark, "present");
    assert.equal(marked.segments["seg-2"].mark, "absent");
  }
  const refFor = record => doc(owner, "courses", "course", "attendance_records", `${id}|${record.rosterEntryId}`);
  // Mirrors _stageRecords: read parent/records, create missing projections and bump parent once.
  const stage = subset => runTransaction(owner, async tx => {
    const session = await tx.get(parent);
    const existing = await Promise.all(subset.map(record => tx.get(refFor(record))));
    const missing = subset.filter((_, index) => !existing[index].exists());
    for (const record of missing) tx.set(refFor(record), record);
    if (missing.length) tx.update(parent, {version: session.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
  });
  // Invalid second segment/shape and immutable schedule changes remain denied.
  if (size === 2) {
    for (const patch of [
      {segments: records[0].segments.map((s, i) => i === 1 ? {...s, mark: "invalid"} : s)},
      {segments: records[0].segments.map((s, i) => i === 1 ? {...s, absentUnits: 61} : s)},
      {segments: records[0].segments.map((s, i) => i === 1 ? {...s, unexpected: true} : s)},
      {segments: records[0].segments.map((s, i) => {const copy = {...s}; if (i === 1) delete copy.mark; return copy;})},
      {unexpected: true}, {unitCount: -1}, {effectiveDate: scheduledDate},
    ]) await assertPermissionDenied(stage([{...records[0], ...patch}]));
    await assertPermissionDenied(setDoc(refFor(records[0]), records[0])); // No paired parent version.
    await assertPermissionDenied(setDoc(doc(other, refFor(records[0]).path), records[0]));
  }
  await assertSucceeds(stage(records.slice(0, 1))); // Interrupted after first student.
  assert.equal((await getDoc(parent)).data().status, "closing");
  await assertPermissionDenied(getDoc(doc(student, refFor(records[0]).path)));
  await assertPermissionDenied(updateDoc(doc(other, parent.path), {status: "finalized"}));
  const stageAll = async () => {
    for (let offset = 0; offset < records.length; offset += 10) await stage(records.slice(offset, offset + 10));
  };
  await assertSucceeds(stageAll());
  const stagedVersion = (await getDoc(parent)).data().version;
  await assertSucceeds(stageAll()); // Repeat same session; no extra projection/version.
  assert.equal((await getDoc(parent)).data().version, stagedVersion);
  for (const record of records) assert.equal((await getDoc(refFor(record))).data().visibility, "staged");
  await assertPermissionDenied(updateDoc(refFor(records[0]), {visibility: "published", publishedAt: serverTimestamp(), updatedAt: serverTimestamp()}));
  await assertSucceeds(runTransaction(owner, async tx => {
    const current = await tx.get(parent);
    tx.update(parent, {status: "finalized", finalizedAt: serverTimestamp(), version: current.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
  }));
  for (const patch of [{effectiveDate: scheduledDate}, {rosterEntryId: "foreign"}, {startMinute: 361}]) {
    await assertPermissionDenied(updateDoc(refFor(records[0]), {...patch, visibility: "published", publishedAt: serverTimestamp(), updatedAt: serverTimestamp()}));
  }
  const publishChunk = subset => runTransaction(owner, async tx => {
    await tx.get(parent);
    const snapshots = await Promise.all(subset.map(record => tx.get(refFor(record))));
    subset.forEach((record, index) => {
      if (snapshots[index].data().visibility === "staged") tx.update(refFor(record), {
        visibility: "published", publishedAt: serverTimestamp(), updatedAt: serverTimestamp(),
      });
    });
  });
  const publish = async () => {
    for (let offset = 0; offset < records.length; offset += 10) await publishChunk(records.slice(offset, offset + 10));
  };
  await assertSucceeds(publish());
  const publishedAt = (await getDoc(refFor(records[0]))).data().publishedAt;
  await assertSucceeds(publish());
  assert.deepEqual((await getDoc(refFor(records[0]))).data().publishedAt, publishedAt);
  assert.deepEqual((await getDocs(collection(parent, "roster"))).docs.map(d => d.data()), rosterBefore);
  assert.equal((await getDocs(collection(owner, "courses", "course", "attendance_records"))).size, size);
  const own = query(collection(student, "courses", "course", "attendance_records"),
    where("rosterEntryId", "==", "student@example.test"), where("visibility", "==", "published"),
    orderBy("effectiveDate", "desc"), orderBy(documentId(), "desc"));
  const visible = await assertSucceeds(getDocs(own));
  assert.equal(visible.size, 1);
  assert.equal(visible.docs[0].data().absentUnits, 60);
  await assertSucceeds(getDoc(doc(student, refFor(records[0]).path)));
  await assertPermissionDenied(getDoc(doc(student, refFor(records[1]).path)));
  await assertPermissionDenied(getDocs(collection(student, parent.path, "roster")));
  await assertPermissionDenied(getDocs(collection(student, parent.path, "events")));
  await assertPermissionDenied(updateDoc(doc(student, refFor(records[0]).path), {absentUnits: 0}));
});
}

test("conjunto 8: staged solo se publica después de finalized y la consulta propia funciona", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test", ["student"]);
  await seedCourse("owner", "course");
  await seedAttendanceEnrollment("course", "student", "owner", "student@example.test");
  const date = attendanceDate(-1);
  await seedAttendanceSession("course", "owner", "publication-session", {
    status: "closing", rosterState: "ready", scheduledDate: date,
    effectiveDate: date, rosterCount: 1, markedCount: 1, unmarkedCount: 0,
  });
  const owner = userContext("owner", "owner@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const sessionRef = doc(owner, "courses", "course", "attendance_sessions", "publication-session");
  const recordRef = doc(owner, "courses", "course", "attendance_records", "publication-session|student@example.test");
  const record = attendanceRecordData("course", "publication-session", "student@example.test", {
    scheduledDate: date,
    effectiveDate: date,
    visibility: "staged",
    publishedAt: null,
    updatedAt: serverTimestamp(),
  });

  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    transaction.update(sessionRef, {
      version: sessionSnapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
    transaction.set(recordRef, record);
  }));
  const studentRecord = doc(student, "courses", "course", "attendance_records", "publication-session|student@example.test");
  await assertPermissionDenied(getDoc(studentRecord));

  await assertPermissionDenied(updateDoc(recordRef, {
    visibility: "published",
    publishedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));

  await assertSucceeds(runTransaction(owner, async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    transaction.update(sessionRef, {
      status: "finalized",
      finalizedAt: serverTimestamp(),
      version: sessionSnapshot.data().version + 1,
      updatedAt: serverTimestamp(),
      updatedBy: "owner",
    });
  }));
  await assertPermissionDenied(getDoc(studentRecord));
  const records = collection(student, "courses", "course", "attendance_records");
  const ownQuery = query(
    records,
    where("rosterEntryId", "==", "student@example.test"),
    where("visibility", "==", "published"),
    orderBy("effectiveDate", "desc"),
    orderBy(documentId(), "desc"),
  );
  assert.equal((await assertSucceeds(getDocs(ownQuery))).size, 0);
  await assertSucceeds(updateDoc(recordRef, {
    visibility: "published",
    publishedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  const visible = await assertSucceeds(getDoc(studentRecord));
  assert.equal(visible.data().visibility, "published");
  const visiblePage = await assertSucceeds(getDocs(ownQuery));
  assert.equal(visiblePage.size, 1);
});


test("C8 regression: prepare future and rescheduled roster before starting", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedCourse("owner", "course");
  await seedAttendanceConfig("course", "owner");
  await testEnvironment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), "courses", "course"), {
      startDate: attendanceDate(-30), endDate: attendanceDate(30),
    });
  });
  const owner = userContext("owner", "owner@example.test", true);
  for (const kind of ["planned", "rescheduled"]) {
    const id = `future-${kind}`;
    const sessionRef = doc(owner, "courses", "course", "attendance_sessions", id);
    const configRef = doc(owner, "courses", "course", "attendance_config", "current");
    const calendarRef = doc(owner, "courses", "course", "attendance_calendar", id);
    if (kind === "rescheduled") await assertSucceeds(setDoc(calendarRef, {
      occurrenceId: id, kind, originalDate: attendanceDate(-2), effectiveDate: attendanceDate(1),
      startMinute: 480, endMinute: 540, reason: "Cambio de horario", version: 1,
      createdAt: serverTimestamp(), createdBy: "owner", updatedAt: serverTimestamp(), updatedBy: "owner",
    }));
    const create = (override = {}) => runTransaction(owner, async tx => {
      await tx.get(doc(owner, "courses", "course"));
      const config = await tx.get(configRef);
      await tx.get(calendarRef);
      await tx.get(sessionRef);
      tx.set(sessionRef, attendanceSessionData("course", "owner", id, {
        occurrenceKind: kind, scheduledDate: kind === "planned" ? attendanceDate(1) : attendanceDate(-2), ...override,
      }));
      tx.update(configRef, {sessionCount: config.data().sessionCount + 1, lastSessionId: id,
        updatedAt: serverTimestamp(), updatedBy: "owner"});
    });
    if (kind === "rescheduled") await assertPermissionDenied(create({effectiveDate: attendanceDate(-2), lateRegistrationReason: "Registro tardío"}));
    await assertSucceeds(create());
    const row = doc(sessionRef, "roster", "student@example.test");
    await assertSucceeds(runTransaction(owner, async tx => {
      const s = await tx.get(sessionRef); await tx.get(row);
      tx.set(row, attendanceRosterEntry("student@example.test", {studentUid: "student", updatedBy: "owner"}));
      tx.update(sessionRef, {version: s.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
    }));
    await assertSucceeds(updateDoc(sessionRef, {rosterState: "ready", version: 3, updatedAt: serverTimestamp(), updatedBy: "owner"}));
    await assertPermissionDenied(updateDoc(sessionRef, {status: "inProgress", version: 4, updatedAt: serverTimestamp(), updatedBy: "owner"}));
  }
});


test("C8 regression: resume published absence void with original publication time", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedCourse("owner", "course");
  const date = attendanceDate(-1);
  await seedAttendanceSession("course", "owner", "blocked", {
    status: "voiding", rosterState: "ready", scheduledDate: date, effectiveDate: date,
    rosterCount: 1, markedCount: 1, unmarkedCount: 0, version: 2,
    lastMutationKind: "void", lastEventId: "original-event", reason: "Clase anulada",
  });
  await seedAttendanceRecord("course", "blocked", "student@example.test", {
    scheduledDate: date, effectiveDate: date, result: "absent", absentUnits: 1,
    publishedAt: date,
  });
  await testEnvironment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "courses", "course", "attendance_sessions", "blocked", "events", "original-event"), {
      kind: "void", oldValue: {status: "finalized"}, newValue: {status: "voided"},
      reason: "Clase anulada", changedAt: date, changedBy: "owner",
    });
  });
  const owner = userContext("owner", "owner@example.test", true);
  const sessionRef = doc(owner, "courses", "course", "attendance_sessions", "blocked");
  const recordRef = doc(owner, "courses", "course", "attendance_records", "blocked|student@example.test");
  const eventRef = doc(sessionRef, "events", "original-event");
  const original = (await getDoc(recordRef)).data();
  const replacement = {...original, result: "voided", unitCount: 0, absentUnits: 0,
    inReviewUnits: 0, justifiedUnits: 0, updatedAt: serverTimestamp()};
  await assertPermissionDenied(setDoc(recordRef, {...replacement, publishedAt: serverTimestamp()}));
  await assertSucceeds(runTransaction(owner, async tx => {
    await tx.get(sessionRef); await tx.get(eventRef); await tx.get(recordRef);
    tx.set(recordRef, replacement);
  }));
  // Fresh client resumes after the record chunk was committed, without a new event.
  const reopened = userContext("owner", "owner@example.test", true);
  await assertSucceeds(runTransaction(reopened, async tx => {
    const ref = doc(reopened, sessionRef.path);
    const session = await tx.get(ref); await tx.get(doc(reopened, eventRef.path));
    tx.update(ref, {status: "voided", voidedAt: serverTimestamp(), version: session.data().version + 1,
      updatedAt: serverTimestamp(), updatedBy: "owner"});
  }));
  assert.equal((await getDoc(recordRef)).data().unitCount, 0);
  assert.equal((await getDoc(recordRef)).data().absentUnits, 0);
  assert.equal((await getDocs(collection(sessionRef, "events"))).size, 1);
});

test("C8 regression: student calendar contains schedule only and requires active enrollment", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedProfile("student", "student@example.test");
  await seedProfile("outsider", "outsider@example.test");
  await seedCourse("owner", "course");
  await seedAttendanceEnrollment("course", "student", "owner", "student@example.test");
  const owner = userContext("owner", "owner@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const outsider = userContext("outsider", "outsider@example.test", true);
  const source = {occurrenceId: "changed", kind: "rescheduled", originalDate: attendanceDate(-2),
    effectiveDate: attendanceDate(1), startMinute: 480, endMinute: 540, reason: "Motivo privado",
    version: 1, createdAt: attendanceDate(-2), createdBy: "owner", updatedAt: attendanceDate(-2), updatedBy: "owner"};
  await testEnvironment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "courses", "course", "attendance_calendar", "changed"), source);
  });
  const {reason, createdAt, createdBy, updatedAt, updatedBy, ...projection} = source;
  const publicRef = doc(owner, "courses", "course", "student_calendar", "changed");
  await assertPermissionDenied(setDoc(publicRef, {...projection, reason}));
  await assertPermissionDenied(setDoc(publicRef, {...projection, startMinute: 600}));
  await assertSucceeds(setDoc(publicRef, projection));
  const visible = await assertSucceeds(getDocs(collection(student, "courses", "course", "student_calendar")));
  assert.equal(visible.size, 1); assert.equal(Object.hasOwn(visible.docs[0].data(), "reason"), false);
  await assertPermissionDenied(getDocs(collection(student, "courses", "course", "attendance_calendar")));
  await assertPermissionDenied(getDocs(collection(outsider, "courses", "course", "student_calendar")));
  await assertPermissionDenied(getDocs(collection(testEnvironment.unauthenticatedContext().firestore(), "courses", "course", "student_calendar")));
  await assertPermissionDenied(setDoc(doc(student, publicRef.path), projection));
  await testEnvironment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), "courses", "course", "enrollments", "student"), {status: "withdrawn"});
  });
  await assertPermissionDenied(getDoc(doc(student, publicRef.path)));
});


test("C8 regression: void minutes projection removes segments and all units", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedCourse("owner", "course");
  const date = attendanceDate(-1);
  await seedAttendanceSession("course", "owner", "minutes-void", {mode: "minutes", status: "voiding", rosterState: "ready",
    scheduledDate: date, effectiveDate: date, segmentIds: ["seg-1"], lastMutationKind: "void", lastEventId: "void-event", reason: "Anulada"});
  await seedAttendanceRecord("course", "minutes-void", "row", {mode: "minutes", scheduledDate: date, effectiveDate: date,
    unitCount: 60, absentUnits: 60, result: "absent", publishedAt: date,
    segments: [{segmentId: "seg-1", startMinute: 480, endMinute: 540, durationMinutes: 60, mark: "absent", absentUnits: 60, justificationStatus: "none", justifiedUnits: 0}]});
  await testEnvironment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "courses", "course", "attendance_sessions", "minutes-void", "events", "void-event"), {
      kind: "void", oldValue: {status: "finalized"}, newValue: {status: "voided"}, reason: "Anulada", changedBy: "owner", changedAt: date});
  });
  const owner = userContext("owner", "owner@example.test", true);
  const ref = doc(owner, "courses", "course", "attendance_records", "minutes-void|row");
  const {segments, ...before} = (await getDoc(ref)).data();
  await assertSucceeds(setDoc(ref, {...before, unitCount: 0, absentUnits: 0, inReviewUnits: 0, justifiedUnits: 0, result: "voided", updatedAt: serverTimestamp()}));
  assert.equal(Object.hasOwn((await getDoc(ref)).data(), "segments"), false);
});

// The actual retry first reads persisted rows, updates an unmarked identity
// when it changed, fills missing rows and increments the parent version.
for (const scenario of [
  { id: "retry-normal-16", original: "2026-11-16", effective: "2026-11-16", start: 600, kind: "planned" },
  { id: "retry-12-to-15", original: "2026-11-12", effective: "2026-11-15", start: 600, kind: "rescheduled" },
  { id: "retry-05-to-16", original: "2026-11-05", effective: "2026-11-16", start: 360, kind: "rescheduled" },
]) {
  test(`C8 retry persisted incomplete minutes roster: ${scenario.id}`, async () => {
    await seedProfile("owner", "owner@example.test", ["student", "teacher"]);
    await seedCourse("owner", "course");
    await seedAttendanceSession("course", "owner", scenario.id, {
      mode: "minutes", segmentIds: ["seg-1", "seg-2"], rosterCount: 2, unmarkedCount: 2,
      occurrenceKind: scenario.kind,
      scheduledDate: Timestamp.fromDate(new Date(`${scenario.original}T00:00:00Z`)),
      effectiveDate: Timestamp.fromDate(new Date(`${scenario.effective}T00:00:00Z`)),
      startMinute: scenario.start, endMinute: scenario.start + 120,
    });
    const rowData = (id, extra = {}) => ({
      rosterEntryId: id, displayName: "Estudiante sintético",
      segments: Object.fromEntries(["seg-1", "seg-2"].map(id => [id, {
        mark: "unmarked", absentUnits: 0, justificationStatus: "none", justifiedUnits: 0,
      }])), version: 0, updatedAt: serverTimestamp(), updatedBy: "owner", ...extra,
    });
    await testEnvironment.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), "courses", "course", "attendance_sessions", scenario.id, "roster", "row-1"), rowData("row-1", {displayName: "Snapshot anterior"}));
    });
    const owner = userContext("owner", "owner@example.test", true);
    const sessionRef = doc(owner, "courses", "course", "attendance_sessions", scenario.id);
    const first = doc(sessionRef, "roster", "row-1");
    const second = doc(sessionRef, "roster", "row-2");
    await assertSucceeds(runTransaction(owner, async tx => {
      const parent = await tx.get(sessionRef);
      const row = await tx.get(first); await tx.get(second);
      tx.update(first, rowData("row-1", {studentUid: "student-1", version: row.data().version + 1}));
      tx.set(second, rowData("row-2", {studentUid: "student-2"}));
      tx.update(sessionRef, {version: parent.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
    }));
    assert.equal((await getDoc(first)).data().studentUid, "student-1");
    assert.equal((await getDoc(second)).exists(), true);
    const changeExisting = patch => runTransaction(owner, async tx => {
      const parent = await tx.get(sessionRef); const row = await tx.get(first);
      tx.update(first, {...patch, version: row.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
      tx.update(sessionRef, {version: parent.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
    });
    await assertPermissionDenied(changeExisting({segments: {
      ...rowData("row-1").segments,
      "seg-1": {mark: "absent", absentUnits: 60, justificationStatus: "none", justifiedUnits: 0},
    }}));
    await assertPermissionDenied(changeExisting({unexpected: "not allowed"}));
    const outsider = userContext("other", "other@example.test", true);
    await seedProfile("other", "other@example.test", ["teacher"]);
    await assertPermissionDenied(getDoc(doc(outsider, first.path)));
    assert.equal((await getDoc(first)).data().segments["seg-1"].mark, "unmarked");
    const beforeReady = (await getDoc(sessionRef)).data();
    if (scenario.kind === "rescheduled") {
      await assertSucceeds(updateDoc(sessionRef, {lateRegistrationReason: "Registro revisado por el docente",
        version: beforeReady.version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"}));
      await assertPermissionDenied(updateDoc(sessionRef, {lateRegistrationReason: "Reemplazar motivo",
        version: beforeReady.version + 2, updatedAt: serverTimestamp(), updatedBy: "owner"}));
    }
    const latest = (await getDoc(sessionRef)).data();
    await assertSucceeds(updateDoc(sessionRef, {rosterState: "ready", version: latest.version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"}));
    assert.equal((await getDocs(collection(sessionRef, "roster"))).size, 2);
    await assertPermissionDenied(changeExisting({displayName: "No reconcile after ready"}));
    // Two different occurrences at the same effective date never share a parent.
    await seedAttendanceSession("course", "owner", `${scenario.id}-other-class`, {
      effectiveDate: beforeReady.effectiveDate, startMinute: scenario.start + 180,
      endMinute: scenario.start + 300,
    });
    assert.equal((await getDoc(sessionRef)).data().rosterState, "ready");
    assert.equal((await getDoc(doc(owner, "courses", "course", "attendance_sessions", `${scenario.id}-other-class`))).data().rosterState, "building");
  });
}

test("C8 retry count follows revalidated membership only while completing an unmarked list", async () => {
  await seedProfile("owner", "owner@example.test", ["teacher"]);
  await seedCourse("owner", "course");
  await seedAttendanceSession("course", "owner", "changed-membership", {rosterCount: 0, unmarkedCount: 0});
  const owner = userContext("owner", "owner@example.test", true);
  const parent = doc(owner, "courses", "course", "attendance_sessions", "changed-membership");
  await assertSucceeds(runTransaction(owner, async tx => {
    await tx.get(parent);
    tx.set(doc(parent, "roster", "new-member"), attendanceRosterEntry("new-member", {updatedBy: "owner"}));
    tx.update(parent, {version: 2, updatedAt: serverTimestamp(), updatedBy: "owner"});
  }));
  await assertSucceeds(updateDoc(parent, {rosterState: "ready", rosterCount: 1, markedCount: 0, unmarkedCount: 1,
    version: 3, updatedAt: serverTimestamp(), updatedBy: "owner"}));
  await assertPermissionDenied(updateDoc(parent, {rosterCount: 2, unmarkedCount: 2, version: 4, updatedAt: serverTimestamp(), updatedBy: "owner"}));
});

for (const rescheduled of [false, true]) {
  test(`C8 regression: correct the second hour of finalized attendance (${rescheduled ? "rescheduled" : "regular"})`, async () => {
    const ownerUid = "owner";
    const studentUid = "student";
    const rowId = "student@example.test";
    const courseId = "course";
    const sessionId = rescheduled ? "course|block|2026-11-05" : "course|block|2026-11-16";
    const scheduledDate = Timestamp.fromDate(new Date(rescheduled ? "2026-11-05T00:00:00Z" : "2026-11-16T00:00:00Z"));
    const effectiveDate = rescheduled ? Timestamp.fromDate(new Date("2026-11-16T00:00:00Z")) : scheduledDate;
    const start = rescheduled ? 360 : 600;
    const end = start + 120;
    const present = { mark: "present", absentUnits: 0, justificationStatus: "none", justifiedUnits: 0 };
    const absent = { ...present, mark: "absent", absentUnits: 60 };
    const segmentsFor = second => [present, second].map((mark, index) => ({
      segmentId: `seg-${index + 1}`,
      startMinute: start + 60 * index,
      endMinute: start + 60 * (index + 1),
      durationMinutes: 60,
      ...mark,
    }));
    await seedProfile(ownerUid, "owner@example.test", ["teacher"]);
    await seedProfile(studentUid, rowId, ["student"]);
    await seedCourse(ownerUid, courseId);
    await seedAttendanceEnrollment(courseId, studentUid, ownerUid, rowId);
    await seedAttendanceSession(courseId, ownerUid, sessionId, {
      status: "finalized", rosterState: "ready", mode: "minutes", occurrenceKind: rescheduled ? "rescheduled" : "planned",
      scheduledDate, effectiveDate, finalizedAt: effectiveDate, startMinute: start, endMinute: end,
      segmentIds: ["seg-1", "seg-2"], rosterCount: 1, markedCount: 1, unmarkedCount: 0,
      lastMutationKind: "mark", lastMutationRosterEntryId: rowId,
    });
    const owner = userContext(ownerUid, "owner@example.test", true);
    const student = userContext(studentUid, rowId, true);
    const parent = doc(owner, "courses", courseId, "attendance_sessions", sessionId);
    const row = doc(parent, "roster", rowId);
    const record = doc(owner, "courses", courseId, "attendance_records", `${sessionId}|${rowId}`);
    const event = doc(parent, "events", "correction-1");
    await testEnvironment.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      await setDoc(doc(db, row.path), {
        rosterEntryId: rowId, displayName: "Estudiante de prueba", studentUid,
        segments: {"seg-1": present, "seg-2": absent}, version: 2,
        updatedAt: effectiveDate, updatedBy: ownerUid,
      });
      await setDoc(doc(db, record.path), attendanceRecordData(courseId, sessionId, rowId, {
        mode: "minutes", scheduledDate, effectiveDate, startMinute: start, endMinute: end,
        unitCount: 120, absentUnits: 60, result: "partial", publishedAt: effectiveDate,
        segments: segmentsFor(absent),
      }));
      for (const [index, segment] of segmentsFor(absent).entries()) {
        await setDoc(doc(db, parent.path, "segments", segment.segmentId), {
          segmentId: segment.segmentId, order: index, startMinute: segment.startMinute,
          endMinute: segment.endMinute, durationMinutes: segment.durationMinutes, createdAt: effectiveDate,
        });
      }
    });
    for (const path of [parent.path, row.path, record.path]) await assertSucceeds(getDoc(doc(owner, path)));
    await assertSucceeds(getDocs(collection(parent, "events")));
    const correctSecondHour = (recordOverrides = {}) => runTransaction(owner, async tx => {
      const session = await tx.get(parent);
      const entry = await tx.get(row);
      await tx.get(record);
      await tx.get(event);
      for (const segment of session.data().segmentIds) await tx.get(doc(parent, "segments", segment));
      tx.update(row, {...entry.data(), segments: {"seg-1": present, "seg-2": present},
        version: entry.data().version + 1, updatedAt: serverTimestamp(), updatedBy: ownerUid});
      tx.update(record, {absentUnits: 0, inReviewUnits: 0, justifiedUnits: 0,
        result: "present", segments: segmentsFor(present), updatedAt: serverTimestamp(), ...recordOverrides});
      tx.set(event, {kind: "correction", rosterEntryId: rowId,
        oldValue: {segmentId: "seg-2", mark: absent}, newValue: {segmentId: "seg-2", mark: present},
        reason: "Corrección de prueba", changedAt: serverTimestamp(), changedBy: ownerUid});
      tx.update(parent, {lastMutationRosterEntryId: rowId, lastMutationKind: "correction",
        lastEventId: "correction-1", version: session.data().version + 1,
        updatedAt: serverTimestamp(), updatedBy: ownerUid});
    });
    await assertPermissionDenied(correctSecondHour({effectiveDate: attendanceDate(1)}));
    await assertPermissionDenied(correctSecondHour({segments: segmentsFor({...present, absentUnits: 61})}));
    assert.equal((await getDoc(event)).exists(), false);
    assert.equal((await getDoc(record)).data().absentUnits, 60);
    await assertSucceeds(correctSecondHour());
    const ownRecord = (await getDoc(doc(student, record.path))).data();
    assert.equal(ownRecord.absentUnits, 0);
    assert.equal(ownRecord.unitCount, 120);
    assert.deepEqual(ownRecord.segments[0], segmentsFor(absent)[0]);
    assert.equal(ownRecord.segments[1].mark, "present");
    assert.deepEqual(ownRecord.publishedAt, effectiveDate);
  });
}


async function c8RequestFixture(mode = "minutes", rescheduled = false, legacy = false) {
  const course = "course", id = rescheduled ? "course|block|2026-11-05" : "course|block|2026-11-16";
  const email = "student@example.test", rowId = legacy ? "legacy:student" : email;
  await seedProfile("owner", "owner@example.test", ["teacher", "student"]);
  await seedProfile("student", email, ["student"]);
  await seedProfile("other", "other@example.test", ["student", "teacher"]);
  await seedCourse("owner", course);
  await seedAttendanceEnrollment(course, "student", "owner", rowId);
  await seedAttendanceEnrollment(course, "other", "owner", "other@example.test");
  const start = rescheduled ? 360 : 600, end = start + 120;
  const scheduledDate = attendanceDate(rescheduled ? 5 : 16);
  const present = {mark:"present",absentUnits:0,justificationStatus:"none",justifiedUnits:0};
  const absent = {...present,mark:"absent",absentUnits:mode === "meeting" ? 1 : 60};
  const segments = mode === "meeting" ? [] : [present,absent].map((m,i)=>({segmentId:`${id}|segment|${i}`,startMinute:start+60*i,endMinute:start+60*(i+1),durationMinutes:60,...m}));
  await seedAttendanceSession(course,"owner",id,{status:"finalized",rosterState:"ready",mode,occurrenceKind:rescheduled?"rescheduled":"planned",scheduledDate,effectiveDate:attendanceDate(16),segmentIds:segments.map(s=>s.segmentId),rosterCount:1,markedCount:1,unmarkedCount:0,finalizedAt:attendanceDate(16),startMinute:start,endMinute:end});
  const owner=userContext("owner","owner@example.test",true), student=userContext("student",email,true), other=userContext("other","other@example.test",true);
  const parent=doc(owner,"courses",course,"attendance_sessions",id), row=doc(parent,"roster",rowId), record=doc(owner,"courses",course,"attendance_records",`${id}|${rowId}`);
  const entry={rosterEntryId:rowId,displayName:"Synthetic",studentUid:"student",version:1,updatedAt:attendanceDate(16),updatedBy:"owner",...(mode==="meeting"?{meetingMark:"absent",justificationStatus:"none",justifiedUnits:0}:{segments:{[segments[0].segmentId]:present,[segments[1].segmentId]:absent}})};
  const projection=attendanceRecordData(course,id,rowId,{mode,scheduledDate,effectiveDate:attendanceDate(16),startMinute:start,endMinute:end,unitCount:mode==="meeting"?1:120,absentUnits:absent.absentUnits,result:mode==="meeting"?"absent":"partial",...(mode==="minutes"?{segments}:{})});
  await testEnvironment.withSecurityRulesDisabled(async c=>{
    if (legacy) {
      await updateDoc(doc(c.firestore(), "courses", course, "enrollments", "student"), {
        rosterEntryId: deleteField(),
      });
    }
    await setDoc(doc(c.firestore(),row.path),entry);await setDoc(doc(c.firestore(),record.path),projection);
    for(const [i,s] of segments.entries())await setDoc(doc(c.firestore(),parent.path,"segments",s.segmentId),{segmentId:s.segmentId,order:i,startMinute:s.startMinute,endMinute:s.endMinute,durationMinutes:60,createdAt:attendanceDate(16)});
  });
  return {course,id,rowId,present,absent,segments,owner,student,other,parent,row,record,projection,entry};
}

for (const mode of ["meeting","minutes"]) for (const approve of [true,false]) {
 test(`C8 requests: ${mode} ${approve ? "approve" : "reject"} once and own access`,async()=>{
  const f=await c8RequestFixture(mode, mode === "minutes" && !approve);
  const {course,id,rowId,owner,student,other,parent,row,record}=f;
  const segmentId=mode==="meeting"?null:f.segments[1].segmentId;
  const requestId=`${id}|${rowId}|${segmentId??"meeting"}`;
  const ref=doc(student,"courses",course,"attendance_requests",requestId);
  const data={sessionId:id,rosterEntryId:rowId,studentUid:"student",segmentId,text:"Solicitud sint?tica",status:"pending",createdAt:serverTimestamp(),decidedAt:null,decidedBy:null,eventId:null};
  await assertPermissionDenied(getDoc(doc(testEnvironment.unauthenticatedContext().firestore(),ref.path)));
  await assertPermissionDenied(getDoc(doc(userContext('student',rowId,false),ref.path)));
  await testEnvironment.withSecurityRulesDisabled(async c=>updateDoc(doc(c.firestore(),'courses',course,'enrollments','student'),{status:'withdrawn'}));
  await assertPermissionDenied(getDoc(ref));
  await testEnvironment.withSecurityRulesDisabled(async c=>updateDoc(doc(c.firestore(),'courses',course,'enrollments','student'),{status:'active'}));
  assert.equal((await assertSucceeds(getDoc(ref))).exists(), false);
  await assertPermissionDenied(getDoc(doc(other,ref.path)));
  await assertPermissionDenied(setDoc(doc(other,ref.path),data));
  await assertPermissionDenied(setDoc(ref,{...data,studentUid:"other"}));
  await assertPermissionDenied(setDoc(ref,{...data,status:"approved"}));
  if(mode==="minutes")await assertPermissionDenied(setDoc(doc(student,"courses",course,"attendance_requests",`${id}|${rowId}|${f.segments[0].segmentId}`),{...data,segmentId:f.segments[0].segmentId}));
  const submit=()=>runTransaction(student,async tx=>{if(!(await tx.get(ref)).exists())tx.set(ref,data);});
  await assertSucceeds(Promise.all([submit(),submit()]));
  assert.equal((await assertSucceeds(getDoc(ref))).data().status, "pending");
  await assertPermissionDenied(getDoc(doc(other, ref.path)));
  await assertPermissionDenied(setDoc(ref,{...data,text:"Reenv?o"}));
  assert.equal((await getDoc(record)).data().justifiedUnits,0);
  await assertPermissionDenied(updateDoc(ref,{status:"approved",decidedAt:serverTimestamp(),decidedBy:"student",eventId:"decision"}));
  await assertPermissionDenied(getDocs(collection(student,"courses",course,"attendance_requests")));
  await assertSucceeds(getDocs(collection(owner,"courses",course,"attendance_requests")));
  const decisionRef=doc(owner,ref.path), event=doc(parent,"events","decision");
  const decide=()=>runTransaction(owner,async tx=>{
    const request=await tx.get(decisionRef);if(request.data().status!=="pending")return;
    const session=await tx.get(parent);const entry=await tx.get(row);await tx.get(record);await tx.get(event);
    const status=approve?"approved":"rejected", nextMark={...f.absent,justificationStatus:approve?"justified":"notAccepted",justifiedUnits:approve?f.absent.absentUnits:0};
    tx.update(row,{...(mode==="meeting"?{meetingMark:"absent",justificationStatus:nextMark.justificationStatus,justifiedUnits:nextMark.justifiedUnits}:{segments:{[f.segments[0].segmentId]:f.present,[segmentId]:nextMark}}),version:entry.data().version+1,updatedAt:serverTimestamp(),updatedBy:"owner"});
    tx.update(record,{justifiedUnits:nextMark.justifiedUnits,inReviewUnits:0,result:approve?"justified":mode==="meeting"?"absent":"partial",...(mode==="minutes"?{segments:f.segments.map((s,i)=>i===1?{...s,...nextMark}:s)}:{}),updatedAt:serverTimestamp()});
    tx.set(event,{kind:"justification",rosterEntryId:rowId,oldValue:{mark:f.absent,requestStatus:"pending"},newValue:{mark:nextMark,requestStatus:status},reason:"",changedAt:serverTimestamp(),changedBy:"owner"});
    tx.update(parent,{version:session.data().version+1,lastMutationKind:"justification",lastMutationRosterEntryId:rowId,lastEventId:"decision",updatedAt:serverTimestamp(),updatedBy:"owner"});
    tx.update(decisionRef,{status,decidedAt:serverTimestamp(),decidedBy:"owner",eventId:"decision"});
  });
  await assertPermissionDenied(updateDoc(doc(other,ref.path),{status:"approved",decidedAt:serverTimestamp(),decidedBy:"other",eventId:"decision"}));
  await assertSucceeds(decide());await assertSucceeds(decide());
  const actual=(await getDoc(doc(student,record.path))).data();
  assert.equal((await getDoc(ref)).data().status, approve ? "approved" : "rejected");
  assert.equal(actual.unitCount,mode==="meeting"?1:120);
  assert.equal(actual.absentUnits-actual.justifiedUnits,approve?0:f.absent.absentUnits);
  if(mode==="minutes")assert.deepEqual(actual.segments[0],f.segments[0]);
  assert.equal((await getDocs(collection(parent,"events"))).size,1);
  await assertPermissionDenied(updateDoc(decisionRef,{status:approve?"rejected":"approved",decidedAt:serverTimestamp()}));
 });
}

test("C8 requests: two hourly keys retain legacy identity and paginate by course", async () => {
  const f = await c8RequestFixture("minutes", true, true);
  const {course, id, rowId, record, owner, student, other, row} = f;
  await testEnvironment.withSecurityRulesDisabled(async c => {
    await updateDoc(doc(c.firestore(), row.path), {
      segments: Object.fromEntries(f.segments.map(s => [s.segmentId, f.absent])),
    });
    await updateDoc(doc(c.firestore(), record.path), {
      absentUnits: 120, result: "absent",
      segments: f.segments.map(s => ({...s, ...f.absent})),
    });
  });
  const requests = db => collection(db, "courses", course, "attendance_requests");
  const own = requests(student);
  for (const {segmentId} of f.segments) {
    const requestId = `${id}|${rowId}|${segmentId}`;
    const ref = doc(own, requestId);
    assert.equal((await assertSucceeds(getDoc(ref))).exists(), false);
    await assertPermissionDenied(getDoc(doc(requests(other), requestId)));
    await assertSucceeds(setDoc(ref, {
      sessionId: id, rosterEntryId: rowId, studentUid: "student", segmentId,
      text: "Solicitud sintética", status: "pending", createdAt: serverTimestamp(),
      decidedAt: null, decidedBy: null, eventId: null,
    }));
    assert.equal((await assertSucceeds(getDoc(ref))).data().segmentId, segmentId);
  }
  const pending = db => query(requests(db), where("status", "==", "pending"), orderBy(documentId()));
  await assertPermissionDenied(getDocs(query(pending(student), limit(1))));
  await assertPermissionDenied(getDocs(query(pending(other), limit(1))));
  const first = await assertSucceeds(getDocs(query(pending(owner), limit(1))));
  const second = await assertSucceeds(getDocs(query(pending(owner), startAfter(first.docs[0]), limit(1))));
  assert.equal(first.size, 1);
  assert.equal(second.size, 1);
  assert.notEqual(first.docs[0].id, second.docs[0].id);
});

test("C8 requests: a corrected absence rejects approval and can be closed without changing totals", async () => {
  const f = await c8RequestFixture("minutes", true);
  const {owner, student, course, id, rowId, row, parent, record} = f;
  const [firstSegment, secondSegment] = f.segments.map(s => s.segmentId);
  const ref = doc(student, "courses", course, "attendance_requests", `${id}|${rowId}|${secondSegment}`);
  await assertSucceeds(setDoc(ref, {
    sessionId: id, rosterEntryId: rowId, studentUid: "student", segmentId: secondSegment,
    text: "Solicitud sintética", status: "pending", createdAt: serverTimestamp(),
    decidedAt: null, decidedBy: null, eventId: null,
  }));
  const ownerRef = doc(owner, ref.path);
  const correction = doc(parent, "events", "mark-present");
  await assertSucceeds(runTransaction(owner, async tx => {
    const s = await tx.get(parent);
    const r = await tx.get(row);
    tx.update(row, {
      segments: {[firstSegment]: f.present, [secondSegment]: f.present},
      version: r.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner",
    });
    tx.update(record, {
      absentUnits: 0, result: "present", updatedAt: serverTimestamp(),
      segments: f.segments.map(part => ({...part, ...f.present})),
    });
    tx.set(correction, {
      kind: "correction", rosterEntryId: rowId,
      oldValue: {segmentId: secondSegment, mark: f.absent},
      newValue: {segmentId: secondSegment, mark: f.present},
      reason: "", changedAt: serverTimestamp(), changedBy: "owner",
    });
    tx.update(parent, {
      version: s.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner",
      lastEventId: correction.id, lastMutationRosterEntryId: rowId, lastMutationKind: "correction",
    });
  }));
  const decision = doc(parent, "events", "settle-request");
  const decide = status => runTransaction(owner, async tx => {
    const s = await tx.get(parent);
    const r = await tx.get(row);
    tx.update(row, {version: r.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner"});
    tx.update(record, {updatedAt: serverTimestamp()});
    tx.set(decision, {
      kind: "justification", rosterEntryId: rowId, reason: "",
      oldValue: {mark: f.present, requestStatus: "pending"},
      newValue: {mark: f.present, requestStatus: status},
      changedAt: serverTimestamp(), changedBy: "owner",
    });
    tx.update(parent, {
      version: s.data().version + 1, updatedAt: serverTimestamp(), updatedBy: "owner",
      lastEventId: decision.id, lastMutationRosterEntryId: rowId, lastMutationKind: "justification",
    });
    tx.update(ownerRef, {
      status, decidedAt: serverTimestamp(), decidedBy: "owner", eventId: decision.id,
    });
  });
  await assertPermissionDenied(decide("approved"));
  await assertSucceeds(decide("rejected"));
  const published = (await getDoc(doc(student, record.path))).data();
  assert.equal(published.absentUnits, 0);
  assert.equal(published.unitCount, 120);
  assert.equal((await getDoc(ref)).data().status, "rejected");
});

test("C8 restore: interrupted finalized void restores marks units and publishedAt once",async()=>{
 const f=await c8RequestFixture();const {owner,other,student,parent,row,record,projection}=f;
 const marks=(await getDoc(row)).data(), originalDate=(await getDoc(record)).data().publishedAt;
 // Void a previously finalized session, preserving the private roster.
 const voidEvent=doc(parent,"events","void-before-restore");
 await assertSucceeds(runTransaction(owner,async tx=>{const s=await tx.get(parent);tx.set(voidEvent,{kind:"void",oldValue:{status:"finalized"},newValue:{status:"voided"},reason:"",changedAt:serverTimestamp(),changedBy:"owner"});tx.update(parent,{status:"voiding",reason:"",lastMutationKind:"void",lastMutationRosterEntryId:null,lastEventId:voidEvent.id,version:s.data().version+1,updatedAt:serverTimestamp(),updatedBy:"owner"});}));
 const voided={...(await getDoc(record)).data(),visibility:"published",result:"voided",unitCount:0,absentUnits:0,inReviewUnits:0,justifiedUnits:0,publishedAt:originalDate,updatedAt:serverTimestamp()};delete voided.segments;
 await assertSucceeds(setDoc(record,voided));
 await assertSucceeds(runTransaction(owner,async tx=>{const s=await tx.get(parent);tx.update(parent,{status:"voided",voidedAt:serverTimestamp(),version:s.data().version+1,updatedAt:serverTimestamp(),updatedBy:"owner"});}));
 const event=doc(parent,"events","restore-1");
 await assertPermissionDenied(updateDoc(doc(student,parent.path),{status:"restoring"}));
 await assertPermissionDenied(updateDoc(doc(other,parent.path),{status:"restoring"}));
 await assertSucceeds(runTransaction(owner,async tx=>{const s=await tx.get(parent);tx.set(event,{kind:"restore",oldValue:{status:"voided"},newValue:{status:"finalized"},reason:"",changedAt:serverTimestamp(),changedBy:"owner"});tx.update(parent,{status:"restoring",lastMutationKind:"restore",lastMutationRosterEntryId:null,lastEventId:event.id,version:s.data().version+1,updatedAt:serverTimestamp(),updatedBy:"owner"});}));
 // Interruption here: repeat the projection write and finish using the persisted event.
 await assertPermissionDenied(setDoc(doc(student,record.path),{...projection,updatedAt:serverTimestamp()}));
 await assertPermissionDenied(setDoc(record,{...projection,rosterEntryId:"foreign",updatedAt:serverTimestamp()}));
 await assertSucceeds(setDoc(record,{...projection,publishedAt:originalDate,updatedAt:serverTimestamp()}));
 await assertSucceeds(setDoc(record,{...projection,publishedAt:originalDate,updatedAt:serverTimestamp()}));
 await assertSucceeds(runTransaction(owner,async tx=>{const s=await tx.get(parent);tx.update(parent,{status:"finalized",version:s.data().version+1,updatedAt:serverTimestamp(),updatedBy:"owner"});}));
 const actual=(await getDoc(doc(student,record.path))).data();
 assert.equal(actual.unitCount,120);assert.equal(actual.absentUnits,60);assert.deepEqual(actual.publishedAt,originalDate);
 assert.deepEqual((await getDoc(row)).data(),marks);
 assert.equal((await getDocs(collection(parent,"events"))).size,2);
});


test("C8 optional calendar reason keeps immutable history private to owner",async()=>{
 await seedProfile('owner','owner@example.test',['teacher']);
 await seedProfile('student','student@example.test',['student']);await seedCourse('owner','course');
 const owner=userContext('owner','owner@example.test',true),student=userContext('student','student@example.test',true);
 const ref=doc(owner,'courses','course','attendance_calendar','changed');
 const course=(await getDoc(doc(owner,'courses','course'))).data();
 const first={occurrenceId:'changed',kind:'cancelled',originalDate:course.startDate,effectiveDate:course.startDate,startMinute:480,endMinute:540,reason:'Motivo anterior',version:1,createdAt:serverTimestamp(),createdBy:'owner',updatedAt:serverTimestamp(),updatedBy:'owner'};
 await assertSucceeds(runTransaction(owner,async tx=>{await tx.get(ref);tx.set(ref,first);tx.set(doc(ref,'events','1'),{oldValue:{},newValue:first,changedAt:serverTimestamp(),changedBy:'owner'});}));
 const saved=(await getDoc(ref)).data();
 const next={...saved,reason:'',version:2,updatedAt:serverTimestamp()};
 await assertSucceeds(runTransaction(owner,async tx=>{const previous=await tx.get(ref);tx.set(ref,next);tx.set(doc(ref,'events','2'),{oldValue:previous.data(),newValue:next,changedAt:serverTimestamp(),changedBy:'owner'});}));
 const events=await assertSucceeds(getDocs(collection(ref,'events')));assert.equal(events.size,2);
 assert.equal(events.docs.find(d=>d.id==='2').data().oldValue.reason,'Motivo anterior');
 await assertPermissionDenied(getDoc(doc(student,ref.path,'events','1')));
 await assertPermissionDenied(updateDoc(doc(ref,'events','2'),{changedBy:'student'}));
});
