// See https://svelte.dev/docs/kit/types#app.d.ts
import type { HTMLAttributes } from 'svelte/elements';

declare global {
	namespace App {}
}

// <model-viewer> from @google/model-viewer, loaded on demand in HeroMascot.svelte.
declare module 'svelte/elements' {
	interface SvelteHTMLElements {
		'model-viewer': HTMLAttributes<HTMLElement> & {
			[attribute: string]: unknown;
			onload?: (event: Event) => void;
		};
	}
}

export {};
