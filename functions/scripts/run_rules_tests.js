/**
 * Runs the Firestore rules tests, choosing a JDK the emulator will accept.
 *
 * `firebase-tools` requires Java 21+. This machine's `JAVA_HOME` points at the
 * JDK 17 the Android release build uses, and moving it would change what
 * `flutter build apk` compiles against — so the emulator gets its own JDK
 * instead, and only for the life of this process.
 *
 * Deliberately a script rather than `cross-env JAVA_HOME=... firebase ...` in
 * package.json:
 *
 *   - It has to be conditional. In CI, `actions/setup-java` already puts a 21
 *     on `JAVA_HOME`, and a hardcoded `D:/tools/...` would override a correct
 *     value with a path that does not exist there.
 *   - A hardcoded Windows path in package.json is wrong on every other OS,
 *     and package.json has no conditionals.
 *   - It avoids adding `cross-env` for a one-line need.
 *
 * If no suitable JDK is found it fails LOUDLY with what to do about it, rather
 * than letting the emulator die with a message about Java versions that reads,
 * to anyone who has not been here, like a broken test suite.
 */
const { spawnSync } = require("child_process");
const { existsSync, readdirSync } = require("fs");
const { join, delimiter: pathSep } = require("path");

/** Major version of the JDK at `home`, or 0 if it is not usable. */
function majorVersion(home) {
  const java = join(home, "bin", process.platform === "win32" ? "java.exe" : "java");
  if (!existsSync(java)) return 0;
  // `java -version` writes to STDERR and exits 0 — it has done since 1.0.
  // `execFileSync` returns stdout, which is empty, so reading only stdout
  // makes every JDK look like version 0 including a perfectly good one.
  // `spawnSync` hands back both streams.
  const probe = spawnSync(java, ["-version"], { encoding: "utf8" });
  return parseMajor(`${probe.stderr || ""}${probe.stdout || ""}`);
}

function parseMajor(text) {
  // `openjdk version "21.0.5" 2024-10-15` → 21
  const m = /version "(\d+)[.")]/.exec(text);
  return m ? Number(m[1]) : 0;
}

/** Candidate JDK homes, best-known first. */
function candidates() {
  const out = [];
  if (process.env.JAVA_HOME) out.push(process.env.JAVA_HOME);
  // The portable JDK installed for exactly this, on this machine.
  const tools = "D:/tools";
  if (existsSync(tools)) {
    for (const entry of readdirSync(tools)) {
      if (/^jdk-2\d/.test(entry)) out.push(join(tools, entry));
    }
  }
  return out;
}

const MINIMUM = 21;
let chosen = null;
for (const home of candidates()) {
  if (majorVersion(home) >= MINIMUM) {
    chosen = home;
    break;
  }
}

if (!chosen) {
  console.error(
    `\nNo JDK ${MINIMUM}+ found, and the Firestore emulator requires one.\n` +
      `Checked: ${candidates().join(", ") || "(nothing)"}\n\n` +
      `The rules tests are the only coverage firestore.rules has, so this is\n` +
      `not a suite to skip. Install a JDK ${MINIMUM}+ and either put it on\n` +
      `JAVA_HOME or drop it in D:/tools/jdk-21*.\n`,
  );
  process.exit(1);
}

// One shell string rather than (command, args). Node 20+ refuses to spawn a
// `.cmd` without a shell -- the CVE-2024-27980 hardening -- and `npx` on
// Windows IS `npx.cmd`, so the argv form dies with a bare `EINVAL` that says
// nothing about why.
const result = spawnSync(
  "npx firebase emulators:exec --only firestore " +
    "--project demo-fitness-rules " +
    '"npx jest --config jest.rules.config.js"',
  {
    shell: true,
    stdio: "inherit",
    env: {
      ...process.env,
      JAVA_HOME: chosen,
      // PATH, not just JAVA_HOME. firebase-tools resolves `java` from PATH and
      // ignores JAVA_HOME entirely -- setting only the latter looks correct,
      // changes nothing, and produces the same "Java version before 21" error
      // as doing nothing at all. Prepended so the chosen JDK wins over the 17
      // the Android build put there.
      PATH: `${join(chosen, "bin")}${pathSep}${process.env.PATH || ""}`,
      Path: `${join(chosen, "bin")}${pathSep}${process.env.PATH || ""}`,
    },
    cwd: join(__dirname, ".."),
  },
);

if (result.error) {
  // A spawn failure used to exit silently with no output at all, which in a
  // script whose entire job is failing loudly is the worst possible outcome.
  console.error(`\nCould not start the emulator: ${result.error.message}\n`);
  process.exit(1);
}

process.exit(result.status ?? 1);
