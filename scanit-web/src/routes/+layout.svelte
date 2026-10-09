<script lang="ts">
	import '../app.css';
	import { site } from '$lib/config';

	let { children } = $props();
</script>

<div class="flex min-h-[100dvh] flex-col">
	<header class="mx-auto flex h-16 w-full max-w-6xl items-center px-4 md:px-8">
		<a href="/" class="text-lg font-semibold tracking-tight no-underline" style="color: var(--ink)">{site.name}</a>
	</header>

	<main class="flex-1">
		{@render children()}
	</main>

	<footer class="mx-auto w-full max-w-6xl px-4 py-12 md:px-8" style="color: var(--ink-muted)">
		<nav class="flex flex-wrap gap-x-6 gap-y-2 text-sm" aria-label="Legal">
			<a href="/privacy" style="color: var(--ink-muted)">Privacy</a>
			<a href="/terms" style="color: var(--ink-muted)">Terms</a>
			<a href="/delete-account" style="color: var(--ink-muted)">Delete your data</a>
		</nav>
	</footer>
</div>
