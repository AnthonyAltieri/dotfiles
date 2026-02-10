# Create or Update PR Command

Create or update a pull request using the GitHub CLI (`gh`).

## Task

1. **Check for existing PR**: Use `gh pr view` to determine if a PR already exists for this branch
2. **Create or update**: 
   - If no PR exists → create one with `gh pr create`
   - If PR exists → update it with `gh pr edit`
3. **Analyze changes**: Compare this branch against `master` to identify all code changes
4. **Write PR description**: Generate an information-dense description following the structure below

## PR Description Structure

### Section 1: Feature Summary
- Bullet points only
- Focus on **user-facing features and capabilities**, not implementation details
- Answer: "What can users/developers now do that they couldn't before?"

### Section 2+: Implementation Details
For each major change area, include:
- Rationale for key decisions
- Code snippets showing usage patterns
- Tables for comparing before/after, listing new APIs, or summarizing options

## Style Guidelines

- Be concise—prefer dense information over verbose explanations
- Use tables to organize structured data (endpoints, config options, type changes)
- Use fenced code blocks with language hints for examples
- Avoid filler phrases like "This PR adds..." or "We decided to..."

## Example Output Format

```markdown
## Summary

- Add real-time sync for timesheet entries across browser tabs
- Support bulk operations on time entries with undo capability  
- Implement retry logic for failed API submissions

## Implementation

### Real-time Sync

Uses `BroadcastChannel` API for cross-tab communication:

```typescript
const channel = new BroadcastChannel('timesheet-sync');
channel.postMessage({ type: 'ENTRY_UPDATED', payload: entry });
```

### New API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/entries/bulk` | POST | Create/update multiple entries |
| `/entries/bulk` | DELETE | Remove multiple entries |

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `retryAttempts` | number | 3 | Max retry count |
| `retryDelay` | number | 1000 | Base delay (ms) |
```
