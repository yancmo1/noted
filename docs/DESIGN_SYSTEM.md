# Noted design system

Noted is a quiet, local-first memory tool. The interface should feel calm while making recording, upload, processing, playback, and recovery states unmistakable.

## Semantic color roles

- Primary: forest green for the main action and navigation selection.
- Recording: coral for active recording and stop/save actions.
- Success: sage green for uploaded, ready, and completed states.
- Attention: amber for processing, consent, and recoverable problems.
- Failure: muted red for errors and destructive actions.
- Memory: lavender for AI, citations, and interpreted content.

Use semantic roles rather than raw color names. Preserve sufficient contrast in both light and dark appearances.

## Type and spacing

- Web display: Fraunces; body: DM Sans; measurements/code: DM Mono.
- iOS: Dynamic Type styles first; fixed sizes only for decorative icons or intentional optical adjustments.
- Shared spacing rhythm: 8, 12, 16, 24 points/pixels.
- Card radius: 16; compact controls may use 8–12; pills are reserved for short status labels.
- Interactive targets: 44×44 minimum on touch surfaces.

## Interaction states

Every primary action has default, focus, pressed, disabled, loading, success, and error treatments. Dynamic status changes use visible copy and accessible announcements; color and icons reinforce but never carry the meaning alone.

## Platform behavior

- Web: responsive single-column mobile layout, keyboard-visible focus, reduced-motion support, and theme-aware surfaces.
- iOS: native navigation, lists, dialogs, Dynamic Type, VoiceOver labels, and safe-area handling.
- Recording and playback must always expose what is happening now and what the user can do next.
