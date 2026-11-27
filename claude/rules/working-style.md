# Working style

How the user likes Claude to work, in every project.

## Communication and reports

- Open every reply with the answer or the next action. No preamble, recap or closing pleasantries.
- Use numbered steps with one action each, at most 5 items per list, and end with one concrete next action that takes under 2 minutes.
- Restate where the work stands each turn ("Step 2 of 5 done: X. Next: Y") and give concrete time estimates.
- Use this short, scannable reply format from the very first reply of every session, without being asked. Stop only when the user says "normal mode".
- Explain problems and solutions in very short bullets and cut the background. Why: long planning messages are hard to take in.
- In a language or toolchain the user is new to, give a one-line why for each step: what the command does, why the flag or file matters, what a failure means.
- Explain concepts from outside software, such as electrical engineering, in plain terms.
- In a multi-phase plan, give a short status report after each task.

## Asking questions

- Ask questions through the multiple-choice dialog (AskUserQuestion), not as a list in prose: 2 to 4 concrete options each, recommended option first. Why: it is faster and more engaging for the user.
- Put at most 4 questions in one dialog and batch the rest into a second. Make each question stand alone with its context, because the dialog may be all the user sees.
- Keep other work moving on the recommended default while waiting for an answer.
- For visual or layout choices, use option previews, or build a throwaway HTML page that renders the options side by side with the project's real styles and a light/dark toggle. Screenshot it to check it before sharing, and delete it once the user has decided.
- When a colour or look-and-feel choice is genuinely ambiguous and the spec doesn't cover it, ask with a concrete option or screenshot before committing to it. Why: a wrong guess wastes a review cycle.

## Git and safety

- Never run git commands that change repo state (add, commit, push, branch, checkout, stash, reset, rm --cached) unless the user asks in that message. This applies to subagents too. Why: the user handles version control themselves.
- Read-only git (status, diff, log) is fine for context.
- Skip the commit steps that skills and plans include, such as "commit the design doc". Leave changes uncommitted and say what is ready.
- Don't stop a multi-phase plan at checkpoints for commits. Finish the plan, then give a manual test list and one prompt to run `/commit-message`.
- To tell whether a test failure was there before, don't stash. Reason from the files you touched, run only the affected tests, or ask for a baseline.
- Confirm before anything destructive.
- Never run anything that could delete objects in cloud storage buckets (CLI deletes, app delete paths, prune commands even with `--dry-run`, tests that might reach a real bucket) without an explicit go-ahead in that message. Why: buckets can be shared between apps and hold production data.
- Never upload or write to third-party services with API keys found in a local `.env`. Read-only calls are fine. Why: the user controls what goes into those services and uploads by hand.
- Local development databases are disposable: change them without asking when you need to for access or test setup, then say what changed. This never covers hosted or shared databases.
- Ask before running anything that calls a paid API (LLM evals, live assistant probes), with a cost estimate, and check that kind of UI with mocked state instead. Why: a command documented at about $0.10 per run actually cost about $2.
- Keep paid cloud compute inside any free credit or budget. Use the cheapest tier, estimate the worst-case cost (time cap × rate × retries) before a batch, check usage before and after, and ask before anything could go over. Never change spend limits yourself.
- In the user's Chrome, never open DevTools or read console messages, because doing so switches the window into mobile mode. Catch errors with in-page JavaScript listeners instead. Resizing the window is fine. Pass this rule to every agent that uses the browser.
- During browser automation, never click native `alert`, `confirm` or `prompt` dialogs, because they freeze the extension. Find them by grepping instead.

## Tokens and agents

- Default to the cheapest method that still does the job well: scripted batch edits rather than file-by-file editing, scripts rather than LLM agents for mechanical checks, and only the parts of files you need.
- For each plan, pick inline work, sequential agents or parallel agents by result quality, and say which and why in one line. Run in parallel only when tasks are truly independent. If two options give the same quality, take the cheaper one.
- Don't spawn checker or review agents unless asked. When you need agents, use fewer of them and a cheaper model.
- Give a token estimate before any multi-agent run. Budget roughly 70k to 80k tokens per agent before any real work.
- Give agents a written brief of checked facts instead of having them load skills or read the repo. Give each one its exact file list and focused tests, run the full suite yourself afterwards, and do the final merge in the main session.
- For a new phase, suggest a fresh session instead of a very long context, with written notes as the handover.

## Code style

- Write no code comments at all: no docblocks, no line, block or template comments, no `ponytail:` notes, whether in your edits or any agent's. The only exceptions are type annotations the language can't express and tool directives. Why: code should explain itself, and comments drift out of date.
- Put the reasoning that would have gone in a comment into the reply, the commit message or the project docs. Check the diff for new comment lines before handing over.
- Strip the comments from code you port in from elsewhere. Leave comments that were already in the project unless asked. Markdown and docs files are exempt.
- Make code explain itself through clear names, small functions, descriptive test names and assertion messages.
- Before adding a new shared component, name the existing ones you checked and say why none fits, even with a small opt-in prop. Prefer extending an existing one, and prefer deleting duplicates.
- When the same markup or UI shape appears a second time, extract a shared component instead of patching both copies. Why: parallel copies drift apart and get fixed separately.
- Fix problems at the highest shared layer (a shared style or partial rather than one page) so later work costs less.
- In cleanups, treat config that the framework or vendor packages read by convention (mail, password reset, email verification, auth) as live even if no app code references it. Grep the vendor code before cutting a key. Why: a cleanup once silently broke email and password reset in production.
- Don't run formatters in write mode (`prettier --write`, `npm run format`) unless the code already follows them. Format your edits by hand to match the lines around them. Why: one run turned four files into a 1,000-line noise diff.

## Workflow and testing

- Propose the industry-standard approach and tooling, and don't add local setups that working engineers in the field don't use. Frame plans as phases of a complete solution, not "quick wins first".
- While a project is in planning, write no code until the user says to build, and get that go-ahead separately for each phase. After each step, start by saying where things stand overall and what comes next.
- Check library behaviour by reading its source and show the evidence, instead of asserting it from memory.
- Before any refactor or restructure, add characterization tests that pin current behaviour, run them green on the old code, then rerun them after the move.
- Scope slow end-to-end or browser suites to the pages a change touches, using the same filters before and after. Run the full suite only when asked or when a shared layout changes. Clean up the run output afterwards.
- When you migrate or restyle a page, follow every button, link and form-submit destination from it and migrate those pages too, recursively, along with the partials and components they include. List the pages you crawled in the handover. Why: a converted page that links to an old one feels half done and costs extra review rounds.
- When asked to crawl an app in the browser, go one page at a time. Open every dropdown, follow every item in it and open every modal those items launch, first in the light theme and then in dark. Let transitions settle before you take a screenshot.
- After building any UI piece, screenshot it in light and dark at desktop, tablet and phone widths, including motion frames. Read the screenshots and fix what's wrong before calling it done. In plans, give every UI task a visual-check step.
- When the user reports one instance of a problem, change only what matches the reason they gave, and show other look-alikes for review before touching them. Why: twice, widening a single report into a whole pattern had to be undone.
- When the user decides to leave a bug you found unfixed, search the issue tracker for an existing ticket and file a backlog ticket if there is none. Say whether you reproduced the bug or only read it from code. Don't file tickets for findings without being asked.
- Before handing over test steps, walk through every step yourself in the browser exactly as written and fix what's wrong. Then reset any test data and the user's theme, and restate the steps.
- Write test steps as one linear numbered walkthrough from the start page, where each step is one click ("Click X") followed by one plain check ("Check: you see Y"). Use no nested bullets, background notes or jargon, and say when to press Cancel or Escape.
- Make test steps cover every new page and every new or changed shared component. Include a look-and-feel check for spacing, alignment, motion, light and dark themes, and tablet and phone widths.
- End test steps with a short progress block for the whole effort: items done out of the total with a percentage, and what's next.

## Tickets, notes and release notes

- Keep tickets as short as possible: one line for the issue, then a few terse bullets for the approach. No prose sections or code walk-throughs. Use the project's ticket template if it has one.
- In bug tickets, describe only the symptoms a user sees, not the cause, the fix or the verification work.
- Write user-facing release notes like game patch notes. Start with one opening line, then Major, Minor, Tweaks and Fixes sections, dropping any that are empty. Use verb-first bullets of about 14 words at most, with feature names exactly as the UI shows them. Leave out links, jargon and developer-only work.
- Keep reference docs and glossaries plain: the same short labelled bullets in every entry, with no emoji, icons, coloured callouts or status badges.

## UI and design taste

- Treat beauty as a requirement on a par with function. Aim for soft, tactile and satisfying, not flat, dense or dated. The user's feedback outranks design-review verdicts, so don't let review fixes strip the polish back out.
- When asked to make a UI "beautiful", start by applying the project's established look consistently. Ask before introducing a new visual direction such as new fonts or header styles. Why: an unrequested custom redesign was rejected and fully reverted.
- Keep UI minimal, responsive and fast: client-side state for interactive flows, few re-renders, heavy dependencies loaded only when needed, network work in parallel, lean components.
- Treat crafted motion as part of UI work. Propose a motion idea for the key moments (a state change, a completion) and build it with springs, WAAPI or canvas. Keep it fast (no waiting on choreography, 60 fps, loops paused off-screen) and respect `prefers-reduced-motion`.
- Never join UI text with "·", "|" or "•" separators. Use plain wording, layout spacing, commas or "of". Why: separators read as generated filler.
- Don't show percentages that imply progress toward completion when nothing is being completed.
- On data-heavy pages, start from the question the page answers. Lead with the answer in plain words and a few headline numbers, and put the detail behind a click.
- Show a single total as one plain number with a label, not as a ring, bar or split chart, unless the user asks for a chart. Put the polish into type, layout and motion, not dense widgets.
- When charts are wanted, use the theme's colours rather than flat neutrals, and keep each category the same colour everywhere.
- Never drop or recompute a figure that the old version of a report shows. "Nothing recorded" is not 0%.
- Let long tables scroll inside their own widget instead of stretching the page.
- Never let stacked form controls or neighbouring buttons touch. Give them a consistent gap, except in joined button groups and tight checkbox or radio lists.
- In a themed app, don't leave unstyled native browser UI (file inputs, OS select popups, `alert`, `confirm` or `prompt`). Use or extend the project's themed component, and show a themed confirmation before a destructive form submit.
