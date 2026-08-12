#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const defaultArtifactRoot = resolve(
  scriptDirectory,
  "../public/compare/best-dictation-apps-for-mac",
);
const defaultManifestPath = resolve(
  defaultArtifactRoot,
  "benchmark-manifest-v1.json",
);
const defaultResultsPath = resolve(defaultArtifactRoot, "results-template.csv");

const allowedStatuses = new Set([
  "",
  "complete",
  "not_tested",
  "unsupported",
  "failed",
  "invalid",
]);
const processingPaths = new Set([
  "on_device",
  "vendor_cloud",
  "third_party_cloud",
  "hybrid",
  "unknown",
]);
const requiredHeaders = [
  "benchmark_version",
  "status",
  "app_id",
  "run_id",
  "fixture_id",
  "repetition",
  "app_version",
  "plan",
  "test_profile",
  "raw_transcript_path",
  "raw_transcript",
  "final_transcript_path",
  "final_transcript",
  "elapsed_seconds",
  "correction_seconds",
  "edit_actions",
  "capture_complete",
  "speaker_turns_correct",
  "speaker_turns_total",
  "processing_path",
  "privacy_mode",
  "app_language_setting",
  "tested_at",
  "hardware",
  "macos_version",
  "price_snapshot",
  "pricing_source_url",
  "notes",
];

function usage() {
  return `Usage:
  node scripts/score-dictation-benchmark.mjs [options]

Options:
  --manifest <path>   Manifest JSON (default: public/.../benchmark-manifest-v1.json)
  --results <path>    Populated CSV (default: the empty results-template.csv)
  --output <path>     Write deterministic score JSON instead of stdout
  --verify-only       Verify manifest structure and every declared SHA-256 digest
  --help              Show this help
`;
}

function parseArguments(argv) {
  const options = {
    manifestPath: defaultManifestPath,
    resultsPath: defaultResultsPath,
    outputPath: null,
    verifyOnly: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help") {
      process.stdout.write(usage());
      process.exit(0);
    }
    if (argument === "--verify-only") {
      options.verifyOnly = true;
      continue;
    }
    if (["--manifest", "--results", "--output"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new Error(`${argument} requires a path`);
      }
      index += 1;
      const resolved = resolve(process.cwd(), value);
      if (argument === "--manifest") options.manifestPath = resolved;
      if (argument === "--results") options.resultsPath = resolved;
      if (argument === "--output") options.outputPath = resolved;
      continue;
    }
    throw new Error(`Unknown argument: ${argument}`);
  }

  return options;
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function pathInside(root, relativePath, label) {
  if (!relativePath || typeof relativePath !== "string") {
    throw new Error(`${label} must be a non-empty relative path`);
  }
  if (isAbsolute(relativePath)) {
    throw new Error(`${label} must be relative: ${relativePath}`);
  }
  const absoluteRoot = resolve(root);
  const absolutePath = resolve(absoluteRoot, relativePath);
  if (
    absolutePath !== absoluteRoot &&
    !absolutePath.startsWith(`${absoluteRoot}${sep}`)
  ) {
    throw new Error(`${label} escapes its artifact directory: ${relativePath}`);
  }
  return absolutePath;
}

function readJson(path, label) {
  let source;
  try {
    source = readFileSync(path, "utf8");
  } catch (error) {
    throw new Error(`Cannot read ${label} at ${path}: ${error.message}`);
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new Error(`Invalid JSON in ${label} at ${path}: ${error.message}`);
  }
}

function requireArray(value, label) {
  if (!Array.isArray(value)) throw new Error(`${label} must be an array`);
  return value;
}

function verifyManifest(manifest, manifestPath) {
  const artifactRoot = dirname(manifestPath);
  if (manifest.benchmark_id !== "best-dictation-apps-for-mac") {
    throw new Error("Manifest benchmark_id is not best-dictation-apps-for-mac");
  }
  if (typeof manifest.schema_version !== "string") {
    throw new Error("Manifest schema_version must be a string");
  }
  if (typeof manifest.execution_gate?.ready !== "boolean") {
    throw new Error("Manifest execution_gate.ready must be boolean");
  }

  const products = requireArray(manifest.products, "manifest.products");
  if (products.length === 0 || new Set(products).size !== products.length) {
    throw new Error("manifest.products must contain unique product IDs");
  }

  const integrityFiles = requireArray(
    manifest.integrity?.files,
    "manifest.integrity.files",
  );
  if (manifest.integrity?.algorithm !== "sha256") {
    throw new Error("Only sha256 manifest integrity is supported");
  }

  const verifiedFiles = [];
  const declaredPaths = new Map();
  for (const entry of integrityFiles) {
    if (!/^[a-f0-9]{64}$/u.test(entry.sha256 ?? "")) {
      throw new Error(`Invalid SHA-256 digest for ${entry.path ?? "unknown path"}`);
    }
    if (declaredPaths.has(entry.path)) {
      throw new Error(`Duplicate integrity path: ${entry.path}`);
    }
    const absolutePath = pathInside(
      artifactRoot,
      entry.path,
      "Manifest integrity path",
    );
    let bytes;
    try {
      bytes = readFileSync(absolutePath);
    } catch (error) {
      throw new Error(`Cannot read integrity file ${entry.path}: ${error.message}`);
    }
    const actual = sha256(bytes);
    if (actual !== entry.sha256) {
      throw new Error(
        `SHA-256 mismatch for ${entry.path}: expected ${entry.sha256}, got ${actual}`,
      );
    }
    declaredPaths.set(entry.path, entry.sha256);
    verifiedFiles.push({ path: entry.path, sha256: actual });
  }

  for (const [field, label] of [
    ["methodology_path", "Methodology"],
    ["results_template_path", "Results template"],
  ]) {
    if (!declaredPaths.has(manifest[field])) {
      throw new Error(`${label} path must be declared in manifest.integrity.files`);
    }
  }

  const fixtures = requireArray(manifest.fixtures, "manifest.fixtures");
  const fixtureIds = new Set();
  for (const fixture of fixtures) {
    if (!fixture.id || fixtureIds.has(fixture.id)) {
      throw new Error(`Fixture IDs must be non-empty and unique: ${fixture.id}`);
    }
    fixtureIds.add(fixture.id);
    if (!fixture.workflow || !fixture.locale || !fixture.reference_path) {
      throw new Error(
        `Fixture ${fixture.id} must declare workflow, locale, and reference_path`,
      );
    }
    if (!Number.isInteger(fixture.required_repetitions) || fixture.required_repetitions < 1) {
      throw new Error(`Fixture ${fixture.id} has invalid required_repetitions`);
    }
    requireArray(fixture.required_fields, `${fixture.id}.required_fields`);
    requireArray(fixture.metrics, `${fixture.id}.metrics`);

    for (const field of ["reference_path", "seed_path", "segments_path"]) {
      if (fixture[field] && !declaredPaths.has(fixture[field])) {
        throw new Error(
          `Fixture ${fixture.id} ${field} is missing from manifest.integrity.files`,
        );
      }
    }
    if (fixture.audio_path) {
      if (!declaredPaths.has(fixture.audio_path)) {
        throw new Error(
          `Fixture ${fixture.id} audio_path is missing from manifest.integrity.files`,
        );
      }
      if (fixture.audio_sha256 !== declaredPaths.get(fixture.audio_path)) {
        throw new Error(`Fixture ${fixture.id} audio_sha256 does not match integrity`);
      }
    }
    if (
      manifest.execution_gate.ready &&
      fixture.workflow !== "correction" &&
      (!fixture.audio_path || !fixture.audio_sha256)
    ) {
      throw new Error(
        `Execution gate cannot be ready while ${fixture.id} lacks hashed audio`,
      );
    }
  }

  if (manifest.ranking?.overall_score !== false) {
    throw new Error("Manifest must explicitly disable an overall weighted score");
  }
  if (manifest.protocol?.eligible_status !== "complete") {
    throw new Error("Only status=complete may be rank eligible");
  }

  const requiredRepetitions = manifest.protocol?.required_repetitions;
  if (!Number.isInteger(requiredRepetitions) || requiredRepetitions < 1) {
    throw new Error("manifest.protocol.required_repetitions must be a positive integer");
  }
  for (let repetition = 1; repetition <= requiredRepetitions; repetition += 1) {
    const order = manifest.protocol?.run_order?.[`block_${repetition}`];
    if (!Array.isArray(order)) {
      throw new Error(`manifest.protocol.run_order.block_${repetition} must be an array`);
    }
    if (
      order.length !== products.length ||
      new Set(order).size !== products.length ||
      order.some((product) => !products.includes(product))
    ) {
      throw new Error(
        `manifest.protocol.run_order.block_${repetition} must contain every product exactly once`,
      );
    }
  }

  return { artifactRoot, verifiedFiles, fixtures };
}

function parseCsv(source) {
  const text = source.replace(/^\uFEFF/u, "");
  const records = [];
  let record = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"') {
        if (text[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          quoted = false;
        }
      } else {
        field += character;
      }
      continue;
    }

    if (character === '"') {
      if (field.length !== 0) {
        throw new Error("CSV quote must begin at the start of a field");
      }
      quoted = true;
    } else if (character === ",") {
      record.push(field);
      field = "";
    } else if (character === "\n" || character === "\r") {
      if (character === "\r" && text[index + 1] === "\n") index += 1;
      record.push(field);
      records.push(record);
      record = [];
      field = "";
    } else {
      field += character;
    }
  }

  if (quoted) throw new Error("CSV ends inside a quoted field");
  if (field.length > 0 || record.length > 0) {
    record.push(field);
    records.push(record);
  }
  if (records.length === 0) throw new Error("Results CSV is empty");

  const headers = records[0];
  if (new Set(headers).size !== headers.length) {
    throw new Error("Results CSV contains duplicate headers");
  }
  const missingHeaders = requiredHeaders.filter((header) => !headers.includes(header));
  const extraHeaders = headers.filter((header) => !requiredHeaders.includes(header));
  if (missingHeaders.length || extraHeaders.length) {
    throw new Error(
      `Results CSV header mismatch. Missing: ${missingHeaders.join(", ") || "none"}. ` +
        `Unexpected: ${extraHeaders.join(", ") || "none"}.`,
    );
  }

  return records.slice(1).map((values, index) => {
    if (values.length !== headers.length) {
      throw new Error(
        `CSV row ${index + 2} has ${values.length} fields; expected ${headers.length}`,
      );
    }
    return Object.fromEntries([
      ...headers.map((header, headerIndex) => [header, values[headerIndex]]),
      ["__row_number", index + 2],
    ]);
  });
}

function normalizeFileText(text) {
  return text.replace(/\r\n?/gu, "\n").replace(/\n$/u, "");
}

function loadOutput(row, inlineField, pathField, resultsDirectory) {
  const inline = row[inlineField];
  const relativePath = row[pathField].trim();
  if (inline !== "" && relativePath !== "") {
    throw new Error(
      `CSV row ${row.__row_number} sets both ${inlineField} and ${pathField}`,
    );
  }
  if (inline !== "") return normalizeFileText(inline);
  if (relativePath === "") return null;
  const absolutePath = pathInside(
    resultsDirectory,
    relativePath,
    `CSV row ${row.__row_number} ${pathField}`,
  );
  try {
    return normalizeFileText(readFileSync(absolutePath, "utf8"));
  } catch (error) {
    throw new Error(
      `Cannot read CSV row ${row.__row_number} ${pathField} (${relativePath}): ${error.message}`,
    );
  }
}

function parseNumber(value, label, { integer = false, maximum = Infinity } = {}) {
  if (value.trim() === "") return null;
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > maximum) {
    throw new Error(`${label} must be a number from 0 to ${maximum}`);
  }
  if (integer && !Number.isInteger(number)) {
    throw new Error(`${label} must be an integer`);
  }
  return number;
}

function parseBoolean(value, label) {
  if (value === "") return null;
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`${label} must be true, false, or blank`);
}

function normalizedForErrorRate(text, locale) {
  return text
    .normalize("NFKC")
    .toLocaleLowerCase(locale)
    .replace(/[’‘`]/gu, "'")
    .replace(/'/gu, "")
    .replace(/[\p{P}\p{S}]+/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
}

function wordTokens(text, locale) {
  const normalized = normalizedForErrorRate(text, locale);
  if (normalized === "") return [];
  const segmenter = new Intl.Segmenter(locale, { granularity: "word" });
  return [...segmenter.segment(normalized)]
    .filter((part) => part.isWordLike)
    .map((part) => part.segment);
}

function characterTokens(text, locale) {
  return Array.from(normalizedForErrorRate(text, locale).replace(/\s+/gu, ""));
}

function levenshtein(left, right) {
  if (left.length > right.length) return levenshtein(right, left);
  let previous = Array.from({ length: left.length + 1 }, (_, index) => index);
  for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
    const current = [rightIndex];
    for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
      current[leftIndex] = Math.min(
        current[leftIndex - 1] + 1,
        previous[leftIndex] + 1,
        previous[leftIndex - 1] +
          (left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1),
      );
    }
    previous = current;
  }
  return previous[left.length];
}

function round(number, places = 6) {
  const factor = 10 ** places;
  return Math.round((number + Number.EPSILON) * factor) / factor;
}

function scoreTranscript(reference, hypothesis, locale) {
  const referenceWords = wordTokens(reference, locale);
  const hypothesisWords = wordTokens(hypothesis, locale);
  const referenceCharacters = characterTokens(reference, locale);
  const hypothesisCharacters = characterTokens(hypothesis, locale);
  if (referenceWords.length === 0 || referenceCharacters.length === 0) {
    throw new Error("Reference transcript is empty after normalization");
  }
  const wordEditDistance = levenshtein(referenceWords, hypothesisWords);
  const characterEditDistance = levenshtein(
    referenceCharacters,
    hypothesisCharacters,
  );
  return {
    reference_words: referenceWords.length,
    hypothesis_words: hypothesisWords.length,
    word_edit_distance: wordEditDistance,
    wer: round(wordEditDistance / referenceWords.length),
    reference_characters: referenceCharacters.length,
    hypothesis_characters: hypothesisCharacters.length,
    character_edit_distance: characterEditDistance,
    cer: round(characterEditDistance / referenceCharacters.length),
    strict_edit_distance: levenshtein(
      Array.from(reference),
      Array.from(hypothesis),
    ),
  };
}

function hasTextOutput(row, inlineField, pathField) {
  return row[inlineField] !== "" || row[pathField].trim() !== "";
}

function validateUrl(value, label) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${label} must be a valid URL`);
  }
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error(`${label} must use http or https`);
  }
}

function scoreRows(rows, manifest, context) {
  const fixtures = new Map(manifest.fixtures.map((fixture) => [fixture.id, fixture]));
  const products = new Set(manifest.products);
  const profiles = new Set(Object.keys(manifest.protocol.profiles));
  const runIds = new Set();
  const cellRepetitions = new Set();
  const exclusions = [];
  const scoredRuns = [];

  for (const row of rows) {
    const status = row.status.trim();
    if (!allowedStatuses.has(status)) {
      throw new Error(
        `CSV row ${row.__row_number} has unsupported status ${JSON.stringify(status)}`,
      );
    }
    if (status !== "complete") {
      exclusions.push({
        csv_row: row.__row_number,
        app_id: row.app_id || null,
        fixture_id: row.fixture_id || null,
        status: status || "blank",
        reason: "Only status=complete is scoreable or rank eligible.",
      });
      continue;
    }

    const rowLabel = `CSV row ${row.__row_number}`;
    if (row.benchmark_version !== manifest.schema_version) {
      throw new Error(
        `${rowLabel} benchmark_version must be ${manifest.schema_version}`,
      );
    }
    if (!products.has(row.app_id)) {
      throw new Error(`${rowLabel} has unknown app_id ${JSON.stringify(row.app_id)}`);
    }
    const fixture = fixtures.get(row.fixture_id);
    if (!fixture) {
      throw new Error(`${rowLabel} has unknown fixture_id ${JSON.stringify(row.fixture_id)}`);
    }
    if (!row.run_id.trim() || runIds.has(row.run_id)) {
      throw new Error(`${rowLabel} run_id must be non-empty and unique`);
    }
    runIds.add(row.run_id);

    const repetition = parseNumber(row.repetition, `${rowLabel} repetition`, {
      integer: true,
      maximum: fixture.required_repetitions,
    });
    if (repetition === null || repetition < 1) {
      throw new Error(`${rowLabel} repetition must start at 1`);
    }
    if (!profiles.has(row.test_profile)) {
      throw new Error(`${rowLabel} has unknown test_profile ${row.test_profile}`);
    }
    const cellKey = [
      row.app_id,
      row.test_profile,
      row.fixture_id,
      repetition,
    ].join("\u0000");
    if (cellRepetitions.has(cellKey)) {
      throw new Error(`${rowLabel} duplicates an app/profile/fixture/repetition cell`);
    }
    cellRepetitions.add(cellKey);

    for (const field of manifest.protocol.required_metadata_fields) {
      if (row[field]?.trim() === "") {
        throw new Error(`${rowLabel} is complete but ${field} is blank`);
      }
    }
    if (!processingPaths.has(row.processing_path)) {
      throw new Error(`${rowLabel} has invalid processing_path ${row.processing_path}`);
    }
    if (Number.isNaN(Date.parse(row.tested_at))) {
      throw new Error(`${rowLabel} tested_at must be an ISO-8601 date or timestamp`);
    }
    validateUrl(row.pricing_source_url, `${rowLabel} pricing_source_url`);

    for (const field of fixture.required_fields) {
      if (field === "raw_transcript") {
        if (!hasTextOutput(row, "raw_transcript", "raw_transcript_path")) {
          throw new Error(`${rowLabel} is complete but raw transcript is missing`);
        }
      } else if (field === "final_transcript") {
        if (!hasTextOutput(row, "final_transcript", "final_transcript_path")) {
          throw new Error(`${rowLabel} is complete but final transcript is missing`);
        }
      } else if (row[field]?.trim() === "") {
        throw new Error(`${rowLabel} is complete but ${field} is blank`);
      }
    }

    const reference = normalizeFileText(
      readFileSync(
        pathInside(context.artifactRoot, fixture.reference_path, "reference_path"),
        "utf8",
      ),
    );
    const rawTranscript = loadOutput(
      row,
      "raw_transcript",
      "raw_transcript_path",
      context.resultsDirectory,
    );
    const finalTranscript = loadOutput(
      row,
      "final_transcript",
      "final_transcript_path",
      context.resultsDirectory,
    );
    const elapsedSeconds = parseNumber(
      row.elapsed_seconds,
      `${rowLabel} elapsed_seconds`,
    );
    const correctionSeconds = parseNumber(
      row.correction_seconds,
      `${rowLabel} correction_seconds`,
    );
    const editActions = parseNumber(row.edit_actions, `${rowLabel} edit_actions`, {
      integer: true,
    });
    const captureComplete = parseBoolean(
      row.capture_complete,
      `${rowLabel} capture_complete`,
    );
    const speakerTurnsCorrect = parseNumber(
      row.speaker_turns_correct,
      `${rowLabel} speaker_turns_correct`,
      { integer: true },
    );
    const speakerTurnsTotal = parseNumber(
      row.speaker_turns_total,
      `${rowLabel} speaker_turns_total`,
      { integer: true },
    );

    const metrics = {};
    if (fixture.workflow === "correction") {
      const seed = normalizeFileText(
        readFileSync(
          pathInside(context.artifactRoot, fixture.seed_path, "seed_path"),
          "utf8",
        ),
      );
      const initial = rawTranscript ?? seed;
      Object.assign(metrics, {
        initial_strict_edit_distance: levenshtein(
          Array.from(reference),
          Array.from(initial),
        ),
        final_strict_edit_distance: levenshtein(
          Array.from(reference),
          Array.from(finalTranscript),
        ),
        correction_exact: finalTranscript === reference,
        correction_seconds: correctionSeconds,
        edit_actions: editActions,
      });
    } else {
      Object.assign(metrics, scoreTranscript(reference, rawTranscript, fixture.locale), {
        elapsed_seconds: elapsedSeconds,
      });
    }

    if (fixture.workflow === "meeting") {
      const segments = readJson(
        pathInside(context.artifactRoot, fixture.segments_path, "segments_path"),
        "meeting segments",
      );
      const expectedTurns = requireArray(segments.turns, "meeting segments.turns").length;
      if (speakerTurnsTotal !== expectedTurns) {
        throw new Error(
          `${rowLabel} speaker_turns_total must equal ${expectedTurns} reference turns`,
        );
      }
      if (speakerTurnsCorrect > speakerTurnsTotal) {
        throw new Error(`${rowLabel} speaker_turns_correct exceeds total turns`);
      }
      Object.assign(metrics, {
        capture_complete: captureComplete,
        speaker_turn_accuracy: round(speakerTurnsCorrect / speakerTurnsTotal),
      });
    }

    scoredRuns.push({
      csv_row: row.__row_number,
      run_id: row.run_id,
      app_id: row.app_id,
      fixture_id: fixture.id,
      workflow: fixture.workflow,
      locale: fixture.locale,
      repetition,
      test_profile: row.test_profile,
      environment: {
        hardware: row.hardware,
        macos_version: row.macos_version,
      },
      configuration: {
        app_version: row.app_version,
        plan: row.plan,
        processing_path: row.processing_path,
        privacy_mode: row.privacy_mode,
        app_language_setting: row.app_language_setting,
        price_snapshot: row.price_snapshot,
        pricing_source_url: row.pricing_source_url,
        tested_at: row.tested_at,
      },
      evidence: {
        raw_transcript_path: row.raw_transcript_path || null,
        raw_transcript_sha256:
          rawTranscript === null ? null : sha256(Buffer.from(rawTranscript, "utf8")),
        final_transcript_path: row.final_transcript_path || null,
        final_transcript_sha256:
          finalTranscript === null ? null : sha256(Buffer.from(finalTranscript, "utf8")),
      },
      metrics,
      notes: row.notes || null,
    });
  }

  scoredRuns.sort((left, right) =>
    [left.test_profile, left.workflow, left.fixture_id, left.app_id, left.repetition]
      .join("\u0000")
      .localeCompare(
        [
          right.test_profile,
          right.workflow,
          right.fixture_id,
          right.app_id,
          right.repetition,
        ].join("\u0000"),
      ),
  );
  return { exclusions, scoredRuns };
}

function median(numbers) {
  const sorted = [...numbers].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

function mean(numbers) {
  return numbers.reduce((total, number) => total + number, 0) / numbers.length;
}

function environmentSignature(run, fields) {
  return fields
    .map((field) =>
      field === "test_profile" ? run.test_profile : run.environment[field],
    )
    .join(" | ");
}

const workflowMetrics = {
  dictation: [
    ["wer", "ascending"],
    ["cer", "ascending"],
    ["elapsed_seconds", "ascending"],
  ],
  file_transcription: [
    ["wer", "ascending"],
    ["cer", "ascending"],
    ["elapsed_seconds", "ascending"],
  ],
  meeting: [
    ["wer", "ascending"],
    ["cer", "ascending"],
    ["elapsed_seconds", "ascending"],
    ["speaker_turn_accuracy", "descending"],
  ],
  correction: [
    ["correction_seconds", "ascending"],
    ["edit_actions", "ascending"],
  ],
};

function buildScopes(manifest, scoredRuns) {
  const profiles = [...new Set(scoredRuns.map((run) => run.test_profile))].sort();
  const scopes = [];
  for (const profile of profiles) {
    for (const [workflow, metrics] of Object.entries(workflowMetrics)) {
      const fixtureIds = manifest.fixtures
        .filter((fixture) => fixture.workflow === workflow)
        .map((fixture) => fixture.id);
      if (fixtureIds.length) {
        scopes.push({
          id: workflow,
          workflow,
          locale: null,
          profile,
          fixtureIds,
          metrics,
        });
      }
    }
    const dictationLocales = [
      ...new Set(
        manifest.fixtures
          .filter((fixture) => fixture.workflow === "dictation")
          .map((fixture) => fixture.locale),
      ),
    ].sort();
    for (const locale of dictationLocales) {
      scopes.push({
        id: `dictation:${locale}`,
        workflow: "dictation",
        locale,
        profile,
        fixtureIds: manifest.fixtures
          .filter(
            (fixture) =>
              fixture.workflow === "dictation" && fixture.locale === locale,
          )
          .map((fixture) => fixture.id),
        metrics: [
          ["wer", "ascending"],
          ["cer", "ascending"],
        ],
      });
    }
  }
  return scopes;
}

function coverageForApp(appId, scope, metric, manifest, scoredRuns) {
  const reasons = [];
  const fixtureMedians = [];
  const environmentSignatures = new Set();
  for (const fixtureId of scope.fixtureIds) {
    const fixture = manifest.fixtures.find((item) => item.id === fixtureId);
    const runs = scoredRuns.filter(
      (run) =>
        run.app_id === appId &&
        run.test_profile === scope.profile &&
        run.fixture_id === fixtureId,
    );
    const repetitions = new Set(runs.map((run) => run.repetition));
    if (
      runs.length !== fixture.required_repetitions ||
      repetitions.size !== fixture.required_repetitions
    ) {
      reasons.push(
        `${fixtureId}: needs ${fixture.required_repetitions} complete repetitions; found ${runs.length}`,
      );
      continue;
    }
    if (
      fixture.workflow === "correction" &&
      runs.some((run) => run.metrics.correction_exact !== true)
    ) {
      reasons.push(`${fixtureId}: at least one final correction is not exact`);
      continue;
    }
    if (
      fixture.workflow === "meeting" &&
      runs.some((run) => run.metrics.capture_complete !== true)
    ) {
      reasons.push(`${fixtureId}: at least one meeting capture is incomplete`);
      continue;
    }
    const values = runs.map((run) => run.metrics[metric]);
    if (values.some((value) => !Number.isFinite(value))) {
      reasons.push(`${fixtureId}: ${metric} is missing`);
      continue;
    }
    fixtureMedians.push({ fixture_id: fixtureId, median: median(values) });
    for (const run of runs) {
      environmentSignatures.add(
        environmentSignature(run, manifest.protocol.same_environment_fields),
      );
    }
  }
  if (environmentSignatures.size > 1) {
    reasons.push("runs do not share one frozen environment");
  }
  return {
    eligible: reasons.length === 0 && fixtureMedians.length === scope.fixtureIds.length,
    reasons,
    fixture_medians: fixtureMedians.map((item) => ({
      ...item,
      median: round(item.median),
    })),
    value:
      fixtureMedians.length === scope.fixtureIds.length
        ? mean(fixtureMedians.map((item) => item.median))
        : null,
    environment:
      environmentSignatures.size === 1 ? [...environmentSignatures][0] : null,
  };
}

function rankedEntries(candidates, direction) {
  const sorted = [...candidates].sort((left, right) => {
    const difference = left.value - right.value;
    if (difference !== 0) return direction === "ascending" ? difference : -difference;
    return left.app_id.localeCompare(right.app_id);
  });
  let previousValue = null;
  let previousRank = 0;
  return sorted.map((candidate, index) => {
    const rank = previousValue !== null && candidate.value === previousValue
      ? previousRank
      : index + 1;
    previousValue = candidate.value;
    previousRank = rank;
    return {
      rank,
      app_id: candidate.app_id,
      value: round(candidate.value),
      fixture_medians: candidate.fixture_medians,
    };
  });
}

function buildRankings(manifest, scoredRuns) {
  if (!manifest.execution_gate.ready) return [];
  const rankings = [];
  for (const scope of buildScopes(manifest, scoredRuns)) {
    for (const [metric, direction] of scope.metrics) {
      const coverage = manifest.products.map((appId) => ({
        app_id: appId,
        ...coverageForApp(appId, scope, metric, manifest, scoredRuns),
      }));
      const candidates = coverage.filter((item) => item.eligible);
      const cohorts = new Map();
      for (const candidate of candidates) {
        if (!cohorts.has(candidate.environment)) cohorts.set(candidate.environment, []);
        cohorts.get(candidate.environment).push(candidate);
      }
      const cohortResults = [...cohorts.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([environment, members]) => ({
          environment,
          published:
            members.length >= (manifest.ranking.minimum_apps ?? 2),
          reason:
            members.length >= (manifest.ranking.minimum_apps ?? 2)
              ? null
              : `Needs at least ${manifest.ranking.minimum_apps ?? 2} eligible apps in the same environment.`,
          entries:
            members.length >= (manifest.ranking.minimum_apps ?? 2)
              ? rankedEntries(members, direction)
              : [],
        }));
      rankings.push({
        scope: scope.id,
        workflow: scope.workflow,
        locale: scope.locale,
        test_profile: scope.profile,
        metric,
        direction,
        cohorts: cohortResults,
        not_ranked: coverage
          .filter((item) => !item.eligible)
          .map((item) => ({ app_id: item.app_id, reasons: item.reasons })),
      });
    }
  }
  return rankings;
}

function buildObservations(manifest, scoredRuns) {
  return manifest.products.map((appId) => {
    const runs = scoredRuns.filter((run) => run.app_id === appId);
    const unique = (selector) => [...new Set(runs.map(selector))].sort();
    return {
      app_id: appId,
      complete_runs: runs.length,
      tested_locales: unique((run) => run.locale),
      processing_paths: unique((run) => run.configuration.processing_path),
      privacy_modes: unique((run) => run.configuration.privacy_mode),
      price_snapshots: unique((run) => run.configuration.price_snapshot),
      pricing_source_urls: unique(
        (run) => run.configuration.pricing_source_url,
      ),
    };
  });
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const manifest = readJson(options.manifestPath, "benchmark manifest");
  const verification = verifyManifest(manifest, options.manifestPath);

  if (options.verifyOnly) {
    let templateSource;
    try {
      templateSource = readFileSync(
        pathInside(
          verification.artifactRoot,
          manifest.results_template_path,
          "Results template path",
        ),
        "utf8",
      );
    } catch (error) {
      throw new Error(`Cannot read results template: ${error.message}`);
    }
    const templateRows = parseCsv(templateSource);
    if (templateRows.some((row) => row.status.trim() === "complete")) {
      throw new Error("Blank results template must not contain complete result rows");
    }
    const report = {
      benchmark_id: manifest.benchmark_id,
      methodology_version: manifest.methodology_version,
      integrity_verified: true,
      verified_file_count: verification.verifiedFiles.length,
      verified_files: verification.verifiedFiles,
      results_template_schema_verified: true,
      execution_gate_ready: manifest.execution_gate.ready,
      execution_gate_blocking_items: manifest.execution_gate.blocking_items,
      disclosure: manifest.disclosure.statement,
    };
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return;
  }

  let csvSource;
  try {
    csvSource = readFileSync(options.resultsPath, "utf8");
  } catch (error) {
    throw new Error(`Cannot read results CSV at ${options.resultsPath}: ${error.message}`);
  }
  const rows = parseCsv(csvSource);
  const { exclusions, scoredRuns } = scoreRows(rows, manifest, {
    artifactRoot: verification.artifactRoot,
    resultsDirectory: dirname(options.resultsPath),
  });
  const rankings = buildRankings(manifest, scoredRuns);
  const report = {
    benchmark_id: manifest.benchmark_id,
    methodology_version: manifest.methodology_version,
    results_file: relative(process.cwd(), options.resultsPath) || ".",
    integrity_verified: true,
    execution_gate_ready: manifest.execution_gate.ready,
    ranking_gate_reason: manifest.execution_gate.ready
      ? null
      : "Rankings are suppressed until canonical audio exists, its hashes verify, and execution_gate.ready is true.",
    results_state:
      scoredRuns.length === 0
        ? "no_hands_on_results"
        : "unpublished_candidate_results",
    complete_row_count: scoredRuns.length,
    excluded_row_count: exclusions.length,
    exclusions,
    observations: buildObservations(manifest, scoredRuns),
    run_scores: scoredRuns,
    rankings,
    overall_ranking: null,
    overall_ranking_reason:
      "The preregistered methodology forbids a weighted overall score.",
  };
  const output = `${JSON.stringify(report, null, 2)}\n`;
  if (options.outputPath) {
    writeFileSync(options.outputPath, output, "utf8");
  } else {
    process.stdout.write(output);
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`Benchmark validation failed: ${error.message}\n`);
  process.exitCode = 1;
}
