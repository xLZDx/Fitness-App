# Decision: voice start of a set is a "ready" prompt with free-form answers (2026-10-22)

Decision (operator, 2026-10-22): the bare word "go" is not a good start command. People say "let's start", "begin", "let's go", "okay", "ready", "yes", "do it" in their own style. Starting a set by voice works as a dialogue instead of a fixed phrase list.

## Behavior
1. After the coach has explained the exercise (what and how to do), it asks "tell me when you are ready".
2. The app waits for the user's answer. The wait is a defined state ("waiting for ready"), not a global listener for the word "go".
3. Any answer with an affirmative intent starts the set and the timer: free-form phrases such as "start", "let's go", "go ahead", "ready", "I'm ready", "okay", "yes", "do it", "begin", "let's do it". The set is not started by the same phrases outside the waiting state.
4. Negative or deferring answers ("wait", "not yet", "one second", "no") keep the app waiting and do not start the timer.
5. Unclear or empty answers do not start the set; the coach may ask once more, then stays on the touch button.
6. Touch remains the equivalent path; voice and touch use the same command queue (`LOCAL_QUEUE_DECISION.md`), so a voice start cannot bypass the local-first path.

## Consequences for the existing parser
- The current phrase list with a bare "go" (`voice_command.dart`) is replaced for the start action by an intent check that is active only in the "waiting for ready" state. The known gap ("let's go home", "go again", "go back" starting a set) is closed by this state restriction and by the negative class, not by a longer phrase list.
- Other commands (stop, next, rest) are outside this decision and keep their current behavior.
- No production caller of the parser exists yet; the change lands with the voice runtime.

## Acceptance criteria (proposals to carry into the package registers)
1. In the waiting state, each phrase of a frozen list of at least 12 affirmative variants (including those in item 3) starts the set; the list is frozen before the test.
2. In the waiting state, each of at least 8 negative or deferring phrases leaves the set not started.
3. Outside the waiting state, none of the affirmative phrases starts a set, including "let's go home", "go again" and "go back".
4. A false start rate target on a recorded speech corpus (including gym noise and other speakers) is defined and frozen before the pilot; the corpus and the labeling rules are fixed first. No number is claimed here.
5. The user can always cancel a started set by touch, and a mistaken start is not recorded as a completed set.

## Not yet verified
No speech recognition engine, language list or noise corpus has been chosen or measured. Whether an on-device intent check is enough, or a language model call is needed for free-form answers, is an implementation question with a latency and privacy cost that this decision does not settle.
