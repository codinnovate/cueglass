import Foundation

/// Mandatory Markdown pattern for interview answers rendered in the overlay.
enum InlineTechnicalExplanationFormat {
    static let rules = """
    ## INLINE TECHNICAL EXPLANATIONS — MANDATORY MARKDOWN FORMAT

    The interview answer will be rendered as Markdown.

    Whenever you introduce a technical term, concept, acronym, or advanced terminology that may not be immediately understandable, explain it immediately using a separate bracketed explanation.

    ### REQUIRED FORMAT

    Always use:

    **technical term** **[simple explanation]**

    The technical term and its explanation must be visually distinct.

    Example:

    "React Fiber is basically React's newer **reconciliation** **[the process React uses to figure out what changed in the UI]** architecture."

    "The old reconciliation process was **synchronous** **[meaning once React started the work, it had to finish before moving on]**."

    "Fiber breaks rendering into smaller **units of work** **[small pieces of rendering React can process separately]**."

    ### MARKDOWN REQUIREMENT

    The explanation MUST be:

    * inside square brackets `[...]`
    * bolded separately from the technical term
    * immediately after the technical term
    * short and conversational
    * written in simple language

    Correct:

    **reconciliation** **[how React figures out what changed]**

    Correct:

    **memoization** **[remembering a previous result so you don't calculate it again]**

    Correct:

    **asynchronous** **[work that doesn't have to finish immediately before the program continues]**

    Incorrect:

    **reconciliation** (how React figures out what changed)

    Incorrect:

    **reconciliation** — how React figures out what changed

    Incorrect:

    **reconciliation** **(how React figures out what changed)**

    Incorrect:

    **reconciliation**: how React figures out what changed

    The square brackets are mandatory.

    ### DO NOT PUT THE TECHNICAL TERM INSIDE THE BRACKETS

    The bracket should ONLY contain the simple explanation.

    Correct:

    **reconciliation** **[how React figures out what changed in the UI]**

    Incorrect:

    **[reconciliation — how React figures out what changed]**

    ### KEEP EXPLANATIONS SHORT

    The bracketed explanation should normally be approximately 3–15 words.

    Do not turn the bracket into another technical explanation.

    Good:

    **referential equality** **[checking whether two references point to the same object]**

    Bad:

    **referential equality** **[a comparison mechanism in JavaScript that determines whether two independently evaluated expressions maintain equivalent reference identity within memory]**

    ### USE PLAIN ENGLISH

    The bracket explanation should be easier to understand than the original technical term.

    Good:

    **race condition** **[when the result depends on which operation finishes first]**

    Good:

    **idempotency** **[doing the same operation repeatedly produces the same result]**

    Good:

    **caching** **[storing previous results so they can be reused faster]**

    Bad:

    **idempotency** **[a property of an operation under repeated application]**

    ### EXPLAIN ONLY WHEN NECESSARY

    Do not explain basic terms every time.

    Don't do this:

    **function** **[a reusable block of code]**

    **variable** **[a named place to store data]**

    **array** **[a list of values]**

    The target audience is already a software engineer.

    Instead, explain concepts that could reasonably require knowledge of the specific technology or computer science topic.

    Examples:

    **reconciliation** **[how React figures out what changed]**

    **closure** **[when a function remembers variables from where it was created]**

    **memoization** **[remembering a previous result to avoid doing the work again]**

    **hydration** **[making server-rendered HTML interactive in the browser]**

    **race condition** **[when the result depends on which operation finishes first]**

    ### EXPLAIN ON FIRST USE

    If a technical term appears multiple times, explain it only the first time.

    Example:

    "React uses **reconciliation** **[how React figures out what changed in the UI]** to determine what needs to update. During reconciliation, React compares the new result with the previous one..."

    Do NOT repeatedly write:

    "**reconciliation** **[how React figures out what changed]**"

    throughout the answer.

    ### AVOID NESTED EXPLANATIONS

    Do not create explanations that contain another unexplained technical term.

    Bad:

    **reconciliation** **[the algorithm that compares virtual DOM trees]**

    This introduces "algorithm" and "virtual DOM" without explaining them.

    Better:

    **reconciliation** **[how React figures out what changed in the UI]**

    ### SPOKEN FLOW

    The bracketed explanation must sound natural when spoken aloud.

    The brackets are primarily a visual Markdown distinction for the UI. The underlying sentence should still sound like something a developer would naturally say.

    For example:

    "React Fiber is basically React's newer **reconciliation** **[how React figures out what changed in the UI]** architecture."

    should sound naturally spoken as:

    "React Fiber is basically React's newer reconciliation — how React figures out what changed in the UI — architecture."

    Do not write awkward sentences just to accommodate the Markdown formatting.

    ### FINAL QUALITY CHECK

    Before returning an answer, silently check every technical term.

    If the term could reasonably confuse the listener:

    1. Bold the technical term.
    2. Immediately follow it with a separately bolded `[simple explanation]`.
    3. Keep the explanation short.
    4. Do not repeat the explanation later.
    5. Make sure the explanation itself uses simple language.

    Required pattern:

    **TERM** **[simple explanation]**

    This formatting rule is mandatory for all interview answers.
    """
}
