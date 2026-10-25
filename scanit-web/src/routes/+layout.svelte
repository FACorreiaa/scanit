<script lang="ts">
	import '../app.css';
	import Lockup from '$lib/Lockup.svelte';
	import { site } from '$lib/config';

	let { children } = $props();
</script>

<svelte:head>
	<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
	<meta name="theme-color" content="#f7f7f5" media="(prefers-color-scheme: light)" />
	<meta name="theme-color" content="#111113" media="(prefers-color-scheme: dark)" />
	<meta property="og:site_name" content={site.name} />
	<meta property="og:image" content="/og.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
</svelte:head>

<div class="flex min-h-[100dvh] flex-col">
	<header class="relative z-20 mx-auto flex h-16 w-full max-w-6xl items-center justify-between px-4 md:px-8">
		<a href="/" class="no-underline" aria-label="{site.name} home"><Lockup /></a>
		<nav class="flex items-center gap-6 text-sm" aria-label="Elsewhere">
			<a href={site.discordUrl} target="_blank" rel="noopener noreferrer" class="nav-link font-medium no-underline"
				>Join us on Discord</a
			>
			<a
				href={site.xUrl}
				target="_blank"
				rel="noopener noreferrer"
				aria-label="Follow on X"
				class="nav-link font-medium no-underline">X</a
			>
		</nav>
	</header>

	<main class="flex-1">
		{@render children()}
	</main>

	<footer class="mx-auto flex w-full max-w-6xl flex-wrap items-center justify-between gap-6 px-4 py-12 md:px-8" style="color: var(--ink-muted)">
		<Lockup height={22} />
		<nav class="flex flex-wrap gap-x-6 gap-y-2 text-sm" aria-label="Legal">
			<a href="/privacy" style="color: var(--ink-muted)">Privacy</a>
			<a href="/terms" style="color: var(--ink-muted)">Terms</a>
			<a href="/delete-account" style="color: var(--ink-muted)">Delete your data</a>
		</nav>
	</footer>
</div>
