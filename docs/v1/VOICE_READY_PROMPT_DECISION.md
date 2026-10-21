# Decision: voice start of a set is a "ready" prompt with free-form answers (2026-10-22)

Decision (operator, 2026-10-22): the bare word "go" is not a good start command. People say "let's start", "begin", "let's go", "okay", "ready", "yes", "do it" in their own style. Starting a set by voice works as a dialogue instead of a fixed phrase list. The free-form approach stays; this document only adds the safeguards that make it safe.

## Behavior
1. After the coach has explained the exercise (what and how to do), it asks "tell me when you are ready" and enters the state WAITING_FOR_READY for one specific workout session, exercise and set of the signed-in user.
2. Readiness is judged on the whole utterance as an intent to start this set now, not on the presence of an affirmative word. Negation, deferral, a competing instruction and ambiguity take precedence over any affirmative cue ("not ready", "okay but wait", "yes but not yet", "let's go home", "go back" never start a set).
3. A clearly affirmative answer ("start", "let's go", "go ahead", "I'm ready", "okay, do it", "begin", "yes") starts the set. A deferring or negative answer keeps the state waiting. An ambiguous answer ("go again", "okay") gets at most one clarifying question, then the state stays waiting for the touch button.
4. The same phrases outside WAITING_FOR_READY never start a set.
5. The decision is a free-form intent check, not a longer fixed phrase list. How it is implemented (on-device rules, a model call) is open and is judged by the acceptance tests below.

## StartSet is not CompleteSet
- StartSet only starts the set timing state of the existing player. It records no repetitions, no completed set and no workout fact, and it is not one of the three durable queue commands (CompleteSet, AddEligibleExercise, SetDifficulty in `LOCAL_QUEUE_DECISION.md`). This document does not extend that queue.
- CompleteSet stays the only command that persists a performed set, through the durable queue with its existing pending/synced semantics. The rest timer keeps its own lifecycle and is not implied by an accepted ready answer.
- Touch and voice invoke the same StartSet action. The waiting context is consumed exactly once: a repeated or late recognition result, a double tap or both touch and voice together start at most one set interval.
- Cancelling a mistaken start by touch leaves zero new completed-set facts.

## Microphone and listening lifecycle
- Listening is opened only by the existing authorized, consented voice-session mechanism, only inside WAITING_FOR_READY, with a visible listening indicator. There is no ambient or always-on listening for this feature.
- The listening window is bounded (proposal: 15 seconds, one re-prompt, then the screen offers the touch button and the state returns to idle). The window length is frozen before the pilot.
- The waiting context is invalidated by: route change, exercise or set change, cancel, account change, sign-out, app moving to background, screen lock, microphone interruption and timeout. A recognition result that arrives after invalidation, or a second final result for the same utterance, is discarded and cannot revive or reuse the state.
- Recognized text and audio are used only for this decision inside the capture window. Audio and transcripts are not stored, and are not sent to a speech or language provider outside the authorized capture window; whether any provider receives them inside the window is part of the voice runtime privacy review, not decided here. If microphone permission is denied, the prompt is replaced by the touch button with an explanation.
- Speech from another person is not distinguishable by this design. The mitigation is the visible indicator, the bounded window and the touch cancel; no speaker identification is claimed.

## Consequences for the existing parser
- The phrase list with a bare "go" in `voice_command.dart` is not used for starting a set. The known gap ("let's go home", "go again", "go back" starting a set) is intended to be closed by the waiting-state restriction and the whole-utterance intent rule, pending the acceptance evidence below. It is not closed today: the parser has no production caller and is unchanged.
- Other commands (stop, next, rest) are outside this decision and keep their current behavior.

## Acceptance criteria (proposals to carry into the package registers)
1. Affirmative: in WAITING_FOR_READY each phrase of a frozen list of at least 12 affirmative variants starts exactly one set interval.
2. Non-affirmative: in WAITING_FOR_READY a frozen adversarial set of at least 20 utterances (negated, deferring, compound, ambiguous, competing-action, and an unrelated sentence containing an affirmative word, including "not ready", "okay but wait", "yes but not yet", "let's go home", "go back", "go again", "that is not what I said") causes zero starts, zero timer starts and zero completion records; ambiguous ones lead to at most one clarifying question.
3. Outside the state: none of the affirmative phrases starts a set when the state is idle, after timeout, or after invalidation.
4. Lifecycle tests: microphone denied, cancel, timeout, navigation, account switch, app background, screen lock, interrupted capture and delayed or duplicated recognition callbacks each give zero unintended starts, zero audio captured or sent outside the window and zero audio or transcripts persisted, and the visible microphone state matches reality.
5. Exactly once: one affirmative answer starts one set interval; replayed recognition results, double taps and late callbacks start no second interval. Cancelling a start by touch leaves zero new completed-set facts; after real completion CompleteSet enters the durable queue as in `LOCAL_QUEUE_DECISION.md`.
6. False-start rate: the corpus (gym noise, several speakers), the labeling rules, the denominator and the pass threshold are frozen before the implementation is accepted; a prepared corpus alone is not a pass. No number is claimed here.

## Not yet verified
No speech recognition engine, language list, provider or noise corpus has been chosen or measured. Whether an on-device check is enough or a language model call is needed for free-form answers is an implementation question with a latency and privacy cost that this decision does not settle.
