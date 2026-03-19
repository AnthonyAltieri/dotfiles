---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, or applications. Generates creative, polished code that avoids generic AI aesthetics.
license: Complete terms in LICENSE.txt
metadata:
  short-description: Design distinctive frontend interfaces
---

# Frontend Design

Create distinctive, production-grade frontend interfaces that avoid generic AI aesthetics while still shipping working code.

The user provides frontend requirements: a component, page, application, or interface to build. They may include context about the purpose, audience, or technical constraints.

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

## Design Thinking

Before coding, understand the context and commit to a bold aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc. There are so many flavors to choose from. Use these for inspiration but design one that is true to the aesthetic direction.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work. The key is intentionality, not intensity.

Then implement working code (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Design Principles

Focus on:
- **Typography**: Choose fonts that are beautiful, unique, and interesting. Avoid generic fonts like Arial and Inter; opt instead for distinctive choices that elevate the frontend's aesthetics; unexpected, characterful font choices. Pair a distinctive display font with a refined body font.
- **Color & Theme**: Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
- **Motion**: Use animations for effects and micro-interactions. Prioritize CSS-only solutions for HTML. Use Motion library for React when available. Focus on high-impact moments: one well-orchestrated page load with staggered reveals (animation-delay) creates more delight than scattered micro-interactions. Use scroll-triggering and hover states that surprise.
- **Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements. Generous negative space OR controlled density.
- **Backgrounds & Visual Details**: Create atmosphere and depth rather than defaulting to solid colors. Add contextual effects and textures that match the overall aesthetic. Apply creative forms like gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, and grain overlays.

Never use generic AI-generated aesthetics like overused font families (Inter, Roboto, Arial, system fonts), cliched color schemes (particularly purple gradients on white backgrounds), predictable layouts and component patterns, and cookie-cutter design that lacks context-specific character.

Interpret creatively and make unexpected choices that feel genuinely designed for the context. No design should be the same. Vary between light and dark themes, different fonts, different aesthetics. NEVER converge on common choices (Space Grotesk, for example) across generations.

**IMPORTANT**: Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate code with extensive animations and effects. Minimalist or refined designs need restraint, precision, and careful attention to spacing, typography, and subtle details. Elegance comes from executing the vision well.

## Gotchas

- Do not force a bold redesign when the repo already has an established design system.
- Avoid purple-on-white gradients, default sans stacks, and interchangeable SaaS hero layouts.
- Distinctive does not mean noisy; a restrained layout can still feel authored if the typography and spacing are sharp.
- Make desktop and mobile both feel intentional. Do not let the mobile layout degrade into a generic fallback.

## References

- `references/design-gotchas.md` - Anti-patterns and course-correction prompts for when the output starts looking generic.
