# Live Chinese → English Translator

A small static webapp that streams Mandarin speech through the browser's
Web Speech API, runs each finalized sentence through a local
Marian-style neural machine translation model (`Xenova/opus-mt-zh-en`)
inside a Web Worker, and renders the English translation in place
beneath the original Chinese block.

Everything runs in the browser. There is no server. The model is fetched
on first load from jsdelivr (`@xenova/transformers@2.17.2`) and cached
by the browser thereafter.

## Running

Serve the directory with any static HTTP server (the Worker module
import requires `http(s)://`, not `file://`):

```sh
python3 -m http.server 8080
# then open http://localhost:8080
```

A speech-recognition-capable browser is required (Chrome / Edge — Safari
support is partial). For the GPU toggle, a WebGPU-capable build is also
needed (Chrome 113+ with a working GPU stack).

## File layout

| File                          | Role                                                                               |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| `index.html`                  | DOM shell: model status, mic + GPU buttons, transcript scroll area, error banner.  |
| `app.js`                      | Glue: speech recognition, worker bridge, transcript DOM lifecycle, GPU toggle.     |
| `queue.js`                    | `SentenceQueue`: orders translation results by sentence id and surfaces pending.   |
| `chunker.js`                  | `chunkText(text, limit)`: sentence-aware splitter for batch translation.           |
| `translator-worker.js`        | Web Worker hosting the `@xenova/transformers` translation pipeline.                |
| `style.css`                   | Light + dark theme, control buttons, transcript entry styles, placeholder pulse.   |
| `tests/queue.test.mjs`        | 15 Node-runnable assertion tests for `SentenceQueue`.                              |
| `tests/chunker.test.mjs`      | 8 Node-runnable assertion tests for `chunkText`.                                   |

Run all tests with:

```sh
node tests/queue.test.mjs
node tests/chunker.test.mjs
```

## Architecture

### Data flow

```
mic ─► SpeechRecognition (zh-CN, continuous + interimResults)
        │
        │ on final result, if it contains Chinese chars
        ▼
     queue.add(text) ─► id
        │
        ├─► appendPendingEntry(id, text)            (DOM: Chinese visible
        │                                             with "translating…"
        │                                             placeholder)
        │
        └─► worker.postMessage({ translate, id, text })
                │
                ▼
            translator-worker
                │ chunkText(text)
                ▼
            translator(chunks)            (single batched forward pass
                │                          if multiple chunks, else one)
                ▼
            postMessage({ translation, id, translated })
                │
                ▼
            queue.resolve(id, translated)
                │
                ▼
            queue callback (id, original, translation)
                │
                ▼
            resolveEntry(id, translated)             (DOM: placeholder
                                                     replaced in place)
```

### `queue.js` — SentenceQueue

Sentences are added in spoken order (`add(text) → id`). Translations
may in principle arrive out of order; the queue holds later results in
`_results` until earlier ones land, then flushes them in id order
through the callback `(id, original, translation)`.

In practice the worker's job-chain also serializes translations, so
results almost always arrive in order. The queue's holding behavior is
defensive insurance against any future race.

Public API:

- `add(text) → id` — append sentence, return monotonically-increasing id.
- `resolve(id, translation)` — supply a successful translation (no-op
  on unknown or already-resolved ids).
- `resolveError(id)` — supply a failure (becomes `[Translation error]`).
- `failPending()` — surface every still-unresolved id as an error and
  flush. Used when the worker is torn down for retry / device switch /
  crash, so orphaned ids don't linger forever.
- `pending` (getter) — count of sentences still in flight or held;
  drives the `(N pending)` label and the `beforeunload` guard.

### `chunker.js` — chunkText

Splits a long input into pieces of at most `limit` characters
(default 80, comfortably under opus-mt's ~512-token context).

Algorithm:

1. Trim. Short inputs return `[text]` unchanged.
2. Lookbehind split on terminal punctuation `[。！？；.!?;]`, keeping
   each delimiter glued to the clause it terminates.
3. Greedy-group consecutive clauses up to the character limit.
4. Anything still over the limit (a single run with no delimiters)
   gets a hard character-count split.
5. Trim each chunk; drop empties.

Used by the worker to (a) prevent truncation past the model's context
and (b) feed the translator an array, which transformers.js batches
into one encoder/decoder forward pass.

### `translator-worker.js` — translation worker

Self-contained ES-module worker that hosts the pipeline.

Message contract — inbound:

- `{ type: 'init', payload: { device: 'wasm' | 'webgpu' } }`
- `{ type: 'translate', payload: { id, text } }`

Outbound:

- `{ type: 'progress', payload: { progress, device } }` — fired during
  model download. `device` is the device actually being loaded (so the
  UI can label correctly even after a GPU→CPU fallback).
- `{ type: 'ready', payload: { device } }`
- `{ type: 'fallback', payload: { from, to, reason } }` — emitted when
  WebGPU init fails and the worker auto-falls back to wasm.
- `{ type: 'translation', payload: { id, translated } }`
- `{ type: 'translation-error', payload: { id } }`
- `{ type: 'error', payload: <message> }` — fatal init failure.

Notable behaviors:

- **Job serialization.** `translate` messages are appended to a
  Promise chain (`jobChain = jobChain.then(...)`), so only one
  translation runs at a time. Concurrent calls into the same pipeline
  are unsafe and balloon memory; serializing is both safer and faster
  on cold pipelines.
- **Init buffering.** `runTranslate` awaits the in-flight `initPromise`
  before checking `translator`, so sentences spoken during a device
  switch are buffered instead of silently dropped.
- **GPU fallback.** A failed `device: 'webgpu'` load automatically
  retries with wasm. The fallback notice is deferred by the app until
  after `ready` so the loading status doesn't wipe it.
- **Batch translation.** If `chunkText` returns more than one chunk,
  the array is passed to `translator(chunks)` as a single batch.
  Outputs are trimmed and joined with a space.

### `app.js` — main thread

Owns the DOM, the worker, the queue, and the speech recognizer.

#### Speech recognition

Uses `SpeechRecognition` (or `webkitSpeechRecognition`) with
`continuous=true` and `interimResults=true`. Only finalized results
are forwarded; partial transcripts go into a pulsing italic interim
line at the bottom of the transcript.

- Final results are filtered with `/[一-鿿㐀-䶿]/`
  before being sent to the translator (avoids translating pure noise).
- `recognition.onerror` distinguishes fatal errors
  (`not-allowed`, `service-not-allowed`, `network`, `audio-capture`)
  — those stop listening — from transient ones like `no-speech`,
  whose label is auto-cleared after 1.5s so users don't see a stale
  error string forever.
- `recognition.onend` auto-restarts listening, with a try/catch + 250ms
  retry to dodge the `InvalidStateError` some browsers throw on
  rapid-fire restart.

#### Two-phase entry rendering

When a sentence is finalized:

1. `appendPendingEntry(id, chinese)` immediately renders an entry with
   the timestamp, the Chinese text, and a pulsing italic
   `translating…` placeholder where the English will go.
2. When the worker eventually posts back, the queue callback hands
   `(id, original, translation)` to `resolveEntry(id, translation)`,
   which finds the entry via the `entryById` Map and replaces the
   placeholder text in place.

Errors take the same path with `[Translation error]` as the value;
the `.translating` class is replaced by `.error`.

#### Transcript cap

`MAX_ENTRIES = 200`. A counter (`entryCount`) tracks the live entry
count so the cap check is amortized O(1) — the previous
`querySelectorAll('.entry')` on every append was O(n) per sentence
(quadratic over a session). Evicted entries also have their id
removed from `entryById`.

#### Auto-scroll

After both append and resolve, the scroll position is only forced to
the bottom if the user is already within 80px of it; this preserves
their position when they scroll back to read older entries.

#### GPU toggle

Visible only when `navigator.gpu` exists. Clicking flips
`requestedDevice` between `'wasm'` and `'webgpu'`, terminates the
current worker, drains pending ids via `queue.failPending()`, and
spins a new worker with the new device. Status text reports the
*active* device, which after a GPU→CPU fallback may differ from what
was requested. Note: WebGPU is the closest thing browsers expose to
"CUDA"; on NVIDIA Windows/Linux it is dispatched through the GPU
driver stack into CUDA, but there is no direct CUDA API in browsers.

#### Beforeunload guard

If `queue.pending > 0` when the user tries to close the tab, the
browser shows its standard "Leave site?" prompt so in-flight
translations aren't silently lost.

#### Retry & worker crash handling

Both the Retry button (manual) and `worker.onerror` (crash) call
`reloadWorker()`, which terminates the worker, calls
`queue.failPending()` so orphaned sentences become `[Translation
error]` entries instead of leaking, and re-inits.

#### Click-to-copy

Click any resolved entry to copy its English translation to the
clipboard via `navigator.clipboard.writeText`. The entry briefly
flashes green (`.copied` class) on success. Pending entries (no
`dataset.translation` set yet) and error entries are skipped.

### `style.css`

- Light theme by default, dark theme via `@media (prefers-color-scheme: dark)`.
- `.entry-english.translating` is grey italic with a 1.4s opacity
  pulse, with a `prefers-reduced-motion` fallback that disables the
  animation and uses static low opacity.
- The mic button turns red while listening; the GPU button turns green
  when active.

## Change log (this session)

Branch: `claude/optimize-translation-webapp-v4x3F`.

### `6a08809` — perf: serialize worker jobs, harden queue, bound transcript, dark mode

The kitchen-sink first pass:

- Worker translate jobs serialized through a Promise chain
  (`jobChain = jobChain.then(...)`) — concurrent pipeline calls were
  unsafe and ballooned memory.
- `SentenceQueue.resolve` / `resolveError` now ignore unknown and
  already-resolved ids (defensive). New `pending` getter so the UI can
  show the queue depth.
- `app.js`: throttle progress DOM updates so we don't redraw on every
  byte; auto-restart `recognition.start()` is wrapped against
  `InvalidStateError` with a 250ms retry; transcript capped at 200
  entries; auto-scroll only when near bottom; click-an-entry to copy
  its translation; pending count surfaces in the `(N pending)` label
  while listening.
- `style.css`: dark mode, entry hover, `.copied` flash.
- `tests/queue.test.mjs`: added unknown-id, double-resolve, and
  `pending` coverage.

### `5f9c6aa` — fix: drain pending sentences when worker is torn down

When the translator worker crashed or was retried, in-flight ids
remained in the queue forever — the `(N pending)` count climbed
indefinitely and any later out-of-order result was held behind the
orphans. Added `queue.failPending()` (errors out every unresolved id
while preserving any held real result), and called it from the retry
handler and `worker.onerror`. Tests added for empty / mixed-held /
post-fail-add scenarios.

### `019cc05` — feat: optional WebGPU backend for translation (GPU button)

Added a `Use GPU` / `Use CPU` toggle, visible only when
`navigator.gpu` exists. The worker accepts a `device` field in the
init payload and passes it through to `pipeline(...)`. On WebGPU
init failure, the worker auto-falls back to wasm and emits a
`fallback` message; the app defers showing that notice until after
`ready` so it doesn't get wiped. `runTranslate` awaits the in-flight
`initPromise` so sentences spoken during a device switch are buffered,
not lost. Status text now reports the active device, e.g.
`Model ready (GPU)`.

There is no direct CUDA API from browsers; WebGPU is the closest
equivalent (it routes through the platform GPU driver, which on
NVIDIA Windows/Linux uses CUDA underneath).

### `1bb1e86` — fix: stale error label, misleading fallback progress, O(n) cap, unload guard

Four targeted fixes from a focused audit pass:

1. After a non-fatal `recognition.onerror` (e.g. `no-speech`), the
   `listening-status` label was overwritten with `error: no-speech`
   and never restored — `updatePendingStatus` only ran on a new
   sentence. Now restored after a 1.5s pause if still listening and
   the text still starts with `error:`.
2. After a WebGPU→wasm auto-fallback, the worker continued firing
   progress events that the app labeled `Loading model on GPU... N%`
   for ~10s because `requestedDevice` wasn't updated until `ready`.
   Now every progress message carries the device that's actually being
   loaded; the label uses that.
3. The 200-entry cap re-walked the entire transcript with
   `querySelectorAll('.entry')` on every append — O(n) per sentence,
   quadratic over a long session. Replaced with a counter + a single
   `querySelector('.entry')` for eviction; amortized O(1).
4. `beforeunload` guard added so closing the tab while
   `queue.pending > 0` triggers the browser's leave-site prompt.

### `64a645c` — feat: chunk long sentences and translate as a batch

Long inputs were being passed to opus-mt as a single string: risk of
truncation past the model's token limit and zero use of batch
parallelism. Added a `chunker.js` module:

- Lookbehind split on terminal punctuation (`。！？； . ! ? ;`), keeping
  delimiters glued to their clause.
- Greedy grouping up to a character cap (default 80).
- Hard character-count fallback for clauses with no delimiters.

The worker uses `chunkText(text)`. If the result has more than one
chunk, the entire array is passed to `translator(chunks)` —
`@xenova/transformers` runs that as a batched single forward pass —
and the outputs are trimmed and space-joined. Single-chunk inputs
keep the original fast path.

`tests/chunker.test.mjs` adds 8 tests covering short input, empty /
nullish input, Chinese-punctuation splits, Latin-punctuation splits,
hard fallback, content preservation, punctuation gluing, and
ceil(n/limit) chunk counts.

### `7d50fea` — feat: show Chinese block immediately, fill in English when ready

Previously the entire entry waited for both the Chinese and its
English to be ready, then appeared together. On slow devices the user
could speak several sentences and see nothing for many seconds — no
acknowledgement that their voice had been captured.

Now the Chinese block renders the moment the recognition final result
arrives, with a pulsing italic `translating…` placeholder where the
English will go. When the translation comes back, the placeholder is
replaced in place.

- `queue.js`: callback signature is now `(id, original, translation)`
  so the app can correlate. Existing in-order semantics are preserved.
- `app.js`: split `appendEntry` into `appendPendingEntry(id, chinese)`
  and `resolveEntry(id, english)`. New `entryById` Map gives O(1)
  lookup. The cap eviction and Clear button keep the map in sync.
- `style.css`: 1.4s opacity pulse on `.translating`, with a
  `prefers-reduced-motion` fallback and a dark-mode tweak.
- `tests/queue.test.mjs`: every test's callback signature updated;
  new test 15 asserts the id is the first argument.

## Testing

| Suite                      | Count | Run                                |
| -------------------------- | ----- | ---------------------------------- |
| `tests/queue.test.mjs`     | 15    | `node tests/queue.test.mjs`        |
| `tests/chunker.test.mjs`   | 8     | `node tests/chunker.test.mjs`      |

Both suites are pure Node — no browser, no transformers.js, no DOM
required. They cover the two pieces of pure logic in the project; the
DOM-side glue in `app.js` and the model-loading glue in
`translator-worker.js` are exercised manually in a browser.

## Known limitations / not done

- **No SRI for the CDN module import.** Adding integrity to a bare ES
  module specifier is awkward; deferred.
- **Hardcoded language and model.** zh-CN recognition + `Xenova/opus-mt-zh-en`
  are baked in. Exposing these as URL params or a config UI was out of
  scope for the bug-fix / refinement passes.
- **Mixed-script filtering is permissive.** The Chinese-character
  gate accepts a result if *any* CJK character is present; a sentence
  like `"hello 你好"` still gets translated.
- **No offline detection.** A failed model fetch on a flaky network
  surfaces as a generic error rather than a connectivity hint.
- **WebGPU is not CUDA.** True CUDA inference would require running
  the model server-side and exchanging tensors — out of scope for an
  in-browser app.
