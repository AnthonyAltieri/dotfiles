---
name: linear-claim-work
description: Locate or create and safely claim the correct Linear issue before implementation. Use when upcoming work needs both a canonical ticket and an assignee, including find-or-create, assign, own, claim, start, or take-ticket requests that precede a broader task. Resolve team, project, and assignee; default an unspecified owner to the authenticated user; and stop for duplicates, conflicting ownership, or existing work. Do not use for standalone issue creation, general Linear CRUD or triage, or implementation-only requests.
---

# Claim Linear Work

Establish one verified Linear issue and clear ownership before downstream work begins. Preserve the remainder of the user's request as the downstream brief rather than absorbing implementation into this skill.

Use `linear:linear` and its connected Linear app as the sole authority for semantic issue reads and writes. This skill adds the duplicate, ownership, and work-conflict policy around those operations; it does not define a second CRUD workflow. If the connected Linear tools are unavailable, ask the user to connect Linear and stop. Do not use browser automation or raw API calls as a fallback for Linear CRUD.

## Inputs and defaults

- Treat the requested product or engineering outcome as the work request.
- Preserve all remaining research, implementation, review, and verification instructions as the downstream brief.
- Use an explicitly named issue assignee or owner. Otherwise resolve the authenticated Linear user with `me` and use that user as the intended assignee.
- Interpret “owner” as issue assignee unless the user clearly means a project lead or another Linear field.
- Resolve one team and one project disposition before writing. A project disposition is either one named project or explicit/observed no project.
- Treat “claim” as assignment. Change status only when the request also clearly says to start or immediately implement the work.
- Leave labels, priority, cycle, estimate, due date, comments, and other fields unchanged unless the user requests them or a repository instruction requires them.

## Workflow

1. Separate the work request, the downstream brief, and agent-control instructions such as `$ultragoal`.
2. Resolve the authenticated user and any explicitly named assignee through Linear. Ask for an exact Linear identity when a name resolves to zero or multiple users. Never infer identity from the OS account, Git configuration, or a similar display name.
3. Search before creating or asking prematurely for team and project:
   - Fetch an explicit Linear URL or issue key directly.
   - Otherwise use full-text issue search for recall and structured issue listing when team or project filters are known.
   - Include terminal and archived issues so an old issue is not duplicated accidentally.
4. Fetch every plausible candidate deeply enough to compare outcome, scope, team, project, status, assignee, and duplicate or parent relations.
5. Select only an explicitly named issue or one unique equivalent match. Do not invent a confidence score.
6. If multiple candidates remain plausible, show their keys, titles, teams/projects, statuses, assignees, and match rationales; ask which is canonical. Do not create another issue while ambiguity remains.
7. Follow an explicit duplicate relation to the canonical issue and evaluate that issue from the beginning. Treat a broad parent or umbrella issue as context, not automatically as the same leaf task.
8. Resolve missing scope from explicit user text, the canonical issue, a repository mapping, or one unambiguous exact Linear match. If team or project disposition remains unknown, ask one compact question before any write. For a new issue, require an explicit project or explicit no project; for an existing issue, its observed empty project is a known disposition.
9. If no candidate remains, repeat the scoped search immediately before creating. If a new plausible issue appears, return to candidate evaluation; otherwise proceed on the create path without an existing-issue conflict audit.
10. If an existing canonical issue was selected, audit it for ownership and existing-work conflicts.
11. Stop for every conflict and collect all evidence into one warning. Make no Linear mutation, start no downstream implementation, and activate no goal until the user responds.
12. Immediately before updating an existing issue, fetch it again. Re-evaluate the gate if assignment, status, comments, links, or update time changed.
13. Apply the smallest authorized mutation.
14. Read the issue back and verify its key, team, project disposition, assignee, and status.
15. Return the verified record. Continue the downstream brief only when the handoff is cleared.

## Match and scope gates

Pause and ask instead of creating or claiming when:

- multiple plausible issues remain;
- the candidate is completed, canceled, archived, or otherwise terminal;
- the candidate's team or project materially conflicts with the intended scope;
- overlapping issues exist without a canonical duplicate relation;
- the apparent match is an umbrella issue rather than the requested unit of work.

If the user chooses a separate follow-up, require differentiated scope and link it to the existing issue rather than silently duplicating it.

## Ownership and work-conflict gate

Always warn and ask for fresh instructions when either condition is true:

- The canonical issue is assigned or delegated to someone other than the intended assignee.
- Credible implementation work exists from someone other than the intended assignee, or active work exists but its author cannot be resolved.

Treat the original “assign it to me,” “claim it,” or “take control” request as insufficient permission to displace a newly discovered owner. Wait for instructions given after the conflict evidence is shown.

Inspect the issue details, relations, comments, attachments, and linked work. When repository context and a purpose-built GitHub surface are available, inspect implementation artifacts using the exact issue key. If a relevant linked artifact cannot be inspected, report the incomplete audit and pause.

Count these as credible work signals:

- a comment explicitly claiming the issue or reporting implementation, progress, blockers, or partial completion;
- a branch with commits, commit, pull request, prototype, build, deployment, or other implementation artifact attributable to another person;
- active or completed child work attributable to another person;
- active implementation evidence whose author is unresolved.

Do not treat these as conflicts by themselves:

- a different reporter or creator;
- requirements discussion, acceptance criteria, or routine triage;
- labels, priority, estimate, or cycle changes;
- an auto-generated Linear branch name without commits;
- bot comments, unrelated review discussion, or a mere reference link.

Disclose historical substantive work; never decide silently that it is abandoned. Report the surfaces inspected and say “no conflicting work signals found in the inspected surfaces,” not “nobody is working on it.”

Use one consolidated prompt such as:

> `ENG-123` is assigned to Maya, and I found her linked open PR and progress comment. I have not changed the issue or started implementation. How do you want me to handle the existing ownership and work?

## Mutation rules

- Create a new issue in one operation with its title, team, project disposition, and assignee. Include a started status only for clear immediate-execution intent.
- Resolve the team's canonical started-type status instead of guessing a status name.
- Update an existing issue only after the final read and conflict gate. Change only cleared fields.
- Treat reassignment, team/project movement, reopening, status changes, and comments as separate decisions. Do not smuggle one mutation into authorization for another.
- Do not rewrite an existing title or description or add a claim comment unless requested.
- Make assignment and status no-ops when already correct.
- On an uncertain create or update failure, search or fetch before retrying. Never retry a create blindly.
- If post-write readback does not match the intended state, stop and report the mismatch.

## New issue content

Create an outcome-oriented title and a concise description containing the user's context, scope, constraints, acceptance criteria, verification requirements, and relevant source links. Do not fabricate missing product decisions.

Keep agent-control instructions such as goal activation, subagent usage, browser choice, or review mechanics out of the product ticket unless they are genuinely part of the team's deliverable. Keep them in the downstream brief.

## Output and composition

Return:

- issue key, URL, and title;
- whether it was created or reused;
- team and project disposition;
- intended and verified assignee;
- verified status and exact mutations performed;
- conflict-audit result and surfaces inspected;
- handoff state: `cleared` or `paused`;
- preserved downstream objective and key constraints.

If the user requested only Linear acquisition, stop after the record. Otherwise continue the original task after a cleared handoff using the applicable skills.

Do not require or activate a durable goal implicitly. When `$ultragoal` is explicitly requested, complete this claim gate first, then pass the verified issue and downstream brief into Ultragoal grounding and activation. Preserve explicit browser proof as a downstream verifier and initialize the requested browser only at that stage.
