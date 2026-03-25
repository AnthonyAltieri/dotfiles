---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use when the user asks to build web components, pages, or applications and the existing design system does not already dictate the visual direction.
metadata:
  short-description: Design distinctive frontend interfaces
---

# Frontend Design

Create distinctive, production-grade frontend interfaces that avoid generic AI aesthetics while still shipping working code.

## Quick start

1. Read the request for purpose, audience, and technical constraints.
2. Pick one strong aesthetic direction before coding.
3. If you feel yourself converging on generic defaults, read `references/design-gotchas.md`.

## Workflow

1. Understand the context.
   - What does the interface need to do?
   - Who uses it?
   - Is there an existing design system that must be preserved?
2. Commit to a clear visual direction.
   - Choose a memorable tone and execute it consistently.
   - Match the visual intensity to the product context.
3. Build working code, not mockups.
   - Ship real layouts, interactions, and responsive behavior.
   - Prefer CSS variables and reusable styling primitives.
4. Review for generic patterns.
   - Replace timid typography, flat backgrounds, and predictable card grids.
   - Remove decorative effects that are not pulling their weight.

## Design Principles

- Typography should feel chosen, not defaulted.
- Color should have a clear hierarchy and enough contrast.
- Motion should emphasize a few high-value moments instead of filling every element with animation.
- Layout should have a strong compositional idea rather than a generic stacked section template.
- Backgrounds and supporting surfaces should create atmosphere.

## Gotchas

- Do not force a bold redesign when the repo already has an established design system.
- Avoid purple-on-white gradients, default sans stacks, and interchangeable SaaS hero layouts.
- Distinctive does not mean noisy; a restrained layout can still feel authored if the typography and spacing are sharp.
- Make desktop and mobile both feel intentional. Do not let the mobile layout degrade into a generic fallback.

## References

- `references/design-gotchas.md` - Anti-patterns and course-correction prompts for when the output starts looking generic.
