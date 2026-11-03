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
  deleteDoc,
  documentId,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
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
