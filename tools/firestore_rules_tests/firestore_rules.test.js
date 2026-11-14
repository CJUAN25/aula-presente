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

async function seedCourse(uid, courseId, blocks = [courseBlock()]) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(
      doc(db, "courses", courseId),
      courseData(uid, { blocks }),
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
    ...extra,
  };
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
    const currentStatus = enrollmentSnapshot.data().status;
    transaction.update(enrollmentRef, {
      status: nextStatus,
      lastStatusEventId: operationId,
      lastStatusChangedAt: serverTimestamp(),
      ...enrollmentPatch,
    });
    transaction.set(eventRef, {
      fromStatus: currentStatus,
      toStatus: nextStatus,
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
  { omitOrders = [], childOverrides = {}, extraChildren = [] } = {},
) {
  return runTransaction(db, async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists()) throw new Error("course-already-exists");
    transaction.set(reference, payload);
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
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = await publishStudent("student", "student@example.test");
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  const blockId = courseBlock().id;
  await assertSucceeds(setDoc(
    enrollmentRef,
    enrollmentData("student", "teacher", "student@example.test"),
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
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const otherTeacher = userContext("other-teacher", "other-teacher@example.test", true);
  const admin = userContext("admin", "admin@example.test", true);
  const student = userContext("student", "student@example.test", true);
  const unverifiedTeacher = userContext("teacher", "teacher@example.test", false);
  const anonymous = testEnvironment.unauthenticatedContext().firestore();
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  await publishStudent("student", "student@example.test");
  await assertSucceeds(setDoc(enrollmentRef, enrollmentData("student", "teacher", "student@example.test")));

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
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  await publishStudent("student", "student@example.test");
  await assertSucceeds(setDoc(enrollmentRef, enrollmentData("student", "teacher", "student@example.test")));

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
  await seedCourse("teacher", "course");
  const teacher = userContext("teacher", "teacher@example.test", true);
  const student = await publishStudent("student", "student@example.test");
  await assertSucceeds(createInvitationAtomically(teacher, "course", inviteCodeA));
  const enrollmentRef = doc(teacher, "courses", "course", "enrollments", "student");
  await assertSucceeds(setDoc(enrollmentRef, enrollmentData("student", "teacher", "student@example.test")));
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
