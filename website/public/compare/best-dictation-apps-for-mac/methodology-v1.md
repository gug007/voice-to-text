# Best dictation apps for Mac: benchmark methodology v1

Version 1.0.0 · preregistered August 12, 2026

## Current status

**No cross-app hands-on results exist yet.** This directory currently contains the preregistered procedure, original reference transcripts, integrity hashes, and an empty results template. A blank cell, a blank status, or `not_tested` is missing evidence—not a zero, a loss, or a result—and must never receive a rank.

The audio-based test gate is intentionally closed. Canonical WAV stimuli must be recorded, normalized, published, and added to `benchmark-manifest-v1.json` with SHA-256 hashes before any cross-app run begins. Until then, any product observations on the comparison page are sourced feature research, not benchmark findings.

## What this benchmark compares

The benchmark keeps unlike jobs separate:

1. **Live dictation:** normalized word error rate (WER), character error rate (CER), strict edit distance, and time until final text appears.
2. **File transcription:** the same accuracy measures plus wall-clock processing time.
3. **Meetings:** capture completion, transcript accuracy, elapsed processing time, and speaker-turn attribution. Summaries are shown as examples and are not accuracy-ranked because a single objective reference summary would reward one writing style.
4. **Correction:** time and discrete edit actions needed to turn the same seeded text into the exact published target.
5. **Privacy path:** observed processing path for the exact tested configuration, kept separate from vendor retention and training policies.
6. **Languages:** results reported by the exact locale and app language setting tested; a marketing language count never substitutes for a run.
7. **Price:** a dated plan-and-price snapshot with a direct source URL. Price is descriptive and is never folded into an accuracy score.

There is no weighted overall score. Different people value local processing, meeting capture, language support, or price differently; hiding those choices in weights would create false precision.

## Artifacts and integrity

`benchmark-manifest-v1.json` is the source of truth for fixture IDs, locales, repetitions, required fields, and hashes. All text is UTF-8 with LF line endings. Verify the package before and after a run:

```sh
cd website
node scripts/score-dictation-benchmark.mjs --verify-only
```

Reference text in this package is original benchmark material and may be recorded for the test. Store canonical audio as 48 kHz, mono, 24-bit linear PCM WAV at −23 LUFS integrated, no peak above −1 dBTP, with 500 ms of silence at both ends. Add each audio path, duration, and SHA-256 digest to the corresponding fixture and integrity list. Do not begin testing while `execution_gate.ready` is `false`.

## Frozen test environment

Use one clean macOS user account and one Mac for every product in a cohort. Freeze and publish:

- Mac model identifier, chip, memory, microphone/virtual-device route, and power mode;
- full macOS version and build;
- app version, distribution channel, plan, model, app language, and all relevant toggles;
- meeting-client and virtual-audio-device versions;
- test profile, date/time, network type, and region.

Run all products inside seven calendar days, on AC power, with the same 48 kHz input route at unity gain. Disable macOS Voice Control, third-party text expanders, automatic spelling correction, grammar correction, smart quotes, and smart dashes in the destination app. Use a fresh plain-text document for each repetition. Finish model downloads and app indexing before timing. At the start of each block, relaunch every app and give its selected model one unscored warm-up using a dedicated warm-up recording that is never used as a measured fixture.

Before each block, record the calibration stimulus through the complete input route. Its integrated level must be within ±0.2 dB of the first accepted calibration and its onset within ±20 ms of the published reference. If either check fails, label the block `invalid` with reason `invalid_rig`, repair the route, and restart the entire block; an individual product result may not be selectively rerun because it looks poor.

The primary `default` profile is a reset/fresh install with normal onboarding choices and the vendor-recommended model for that language. An optional `local_only` profile is a separate cohort. Never mix profiles, hardware, or macOS versions in one leaderboard.

## Canonical stimulus creation

Use native speakers for en-US, es-ES, and fr-FR. A speaker reads the reference naturally without adding or dropping words. Record in a treated, quiet room with the same microphone distance and gain. Preserve one canonical take per fixture; do not rerecord it for individual apps. A reviewer listens while reading the reference, confirms every lexical item, and records the WAV duration. A second reviewer verifies the file hash.

For live dictation, route the canonical WAV into the system input through the frozen virtual audio device and play it once at real-time speed. For file transcription, import the same published WAV without conversion. Do not use a live rereading, because delivery differences would confound app differences.

For the meeting fixture, create a private call with three isolated source participants. Each participant plays only that speaker’s turns from synchronized source tracks derived from the published fixture. Capture on the test Mac using the product’s documented meeting workflow. Freeze the meeting client, its audio-processing settings, and all source-track hashes. If a product has no meeting workflow, record `unsupported`; do not feed its file importer and call that a meeting result.

## Run order and repetitions

Perform three measured repetitions for every product–profile–fixture combination in the three block orders frozen in `benchmark-manifest-v1.json`. Run the blocks at least four hours apart and span at least two calendar days. Keep fixture order fixed as listed in the manifest. Reset the destination document and clear only user-editable app history between repetitions; never delete a model cache if that is not a normal user action. Record bandwidth and round-trip latency at the start and end of every block containing a cloud path.

Use one CSV row per repetition. `run_id` must be unique, and `repetition` must be 1, 2, or 3. Raw means the first stable transcript the product exposes before manual correction or optional reprocessing. If an app exposes both a speech transcript and an AI rewrite, save both as separate files, but put the speech transcript in `raw_transcript_path`. A polished rewrite may be described in `notes`; it must not replace raw recognition text for WER.

Timing boundaries:

- **Live dictation:** start with the first audible sample; stop when the app’s text is stable for two seconds after audio ends.
- **File:** start immediately before confirming import; stop when the full transcript is visible and exportable.
- **Meeting:** start at the first source sample; record capture completion at the final sample and processing time when the final transcript is available.
- **Correction:** start when the seeded text is visible and the operator may act; stop only when the text exactly matches the target.

Capture timing on a 60 fps screen recording and review it frame by frame. Enter seconds to three decimals. A discrete correction action is one keyboard shortcut, click, selection, typed replacement, or spoken correction command; navigation inside one continuous selection gesture counts once. Use only the product’s documented correction workflow plus ordinary keyboard/mouse operations. Reset the exact seed before each repetition.

## Accuracy scoring

The scorer calculates Levenshtein insertions, deletions, and substitutions.

```text
WER = word edit distance / reference word count
CER = character edit distance / reference character count
```

For WER and CER, text is normalized to Unicode NFKC, lowercased with the fixture locale, curly apostrophes are canonicalized, punctuation/symbols are removed, and whitespace is collapsed. CER additionally removes whitespace. Words are selected using `Intl.Segmenter(locale, { granularity: "word" })` with `isWordLike`. The scorer also reports strict edit distance on the unnormalized text so formatting differences remain visible.

The correction task is valid for timing only when `final_transcript` exactly matches the published target after normalizing line endings and removing the file’s single terminal newline. A near match is reported with its remaining edit distance but is excluded from correction-time ranks.

For the meeting fixture, globally map each app speaker label to at most one neutral reference speaker (`speaker_a`, `speaker_b`, `speaker_c`) to maximize correctly attributed turns. A turn is correct only when the dominant label across its aligned words maps to the reference speaker. Record correct and total reference turns; merged, missing, or unlabeled turns are incorrect. Both reviewers must agree on the alignment.

## Privacy-path audit

Privacy is not a single yes/no field. For every tested configuration, record one processing path: `on_device`, `vendor_cloud`, `third_party_cloud`, `hybrid`, or `unknown`. Also record the exact privacy mode and model.

Before a measured run, inspect official documentation and save the source URL and access date in the run notes. During a separate audit run, capture per-process network activity from app launch through final text. After required model downloads, repeat once with outbound traffic blocked. An `on_device` label requires both documented local processing and successful completion while blocked with no app payload connection. Network silence does not prove deletion, non-retention, or exclusion from training, so report those vendor policy claims in separate prose with citations.

## Pricing and language audit

Snapshot the public individual-plan price on the test date, including currency, tax treatment if shown, billing cadence, free allowance, and whether the tested feature needs a paid tier. Save the direct pricing URL. Do not silently convert currencies; if a convenience conversion is shown, record its dated exchange-rate source.

Report only the locale actually tested. Product-wide language counts belong in a sourced capability table and must be labeled vendor claims. `unsupported` is allowed only after checking the tested version and official documentation; `not_tested` means no empirical conclusion.

## Exclusions and failures

Allowed statuses are:

- `complete`: all required evidence and metadata for the row exists;
- `not_tested`: no run was performed;
- `unsupported`: the tested product/version documents no applicable workflow;
- `failed`: the workflow was attempted but did not finish; describe and retain evidence;
- `invalid`: operator, routing, timing, or artifact error invalidated the run;
- blank: an unfilled template row.

Only `complete` rows enter metric aggregation. Do not convert a missing, unsupported, failed, invalid, blank, or `not_tested` row into a numeric value. Do not discard a bad complete result unless the preregistered invalidation rule applies; publish the reason and rerun all three repetitions for that product–fixture cell.

## Aggregation and ranking rules

Take the median of three repetitions for each product–fixture cell, then the unweighted mean of fixture medians inside the same workflow and profile. Publish WER, CER, time, correction actions, capture completion, and speaker accuracy as separate tables. Lower is better for errors and time; higher is better for capture and speaker accuracy.

A product is rank-eligible for a table only when it has all three `complete` repetitions for every fixture in that table, every correction output is exact where relevant, every meeting capture completed where relevant, and all compared rows share the frozen environment fields. At least two products must be eligible. Ties use competition ranking. Products without complete coverage remain visible as “not ranked” with the exact reason.

## Publication checklist

Do not publish a hands-on winner, rank, or “tested” badge until all of these are true:

- the manifest execution gate is ready and every artifact hash verifies;
- canonical WAV files, raw outputs, final correction outputs, timings, and run logs are public;
- all required product–fixture cells contain three valid repetitions;
- app versions, environment, model/profile, privacy path, and language settings are disclosed;
- two reviewers reproduce the scorer output and resolve speaker alignment;
- failures and unsupported workflows remain visible;
- sourced feature claims are visually separated from measured results;
- the write-up plainly names every category where a competitor wins.

Score a populated copy without modifying the blank template:

```sh
cd website
node scripts/score-dictation-benchmark.mjs \
  --results public/compare/best-dictation-apps-for-mac/results-v1.csv \
  --output public/compare/best-dictation-apps-for-mac/scores-v1.json
```

The output includes every scored run, explicit exclusions, coverage failures, and only those per-metric rankings that meet the gate. It never emits an overall winner.
