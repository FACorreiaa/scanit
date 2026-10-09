<script lang="ts">
	import type { Snippet } from 'svelte';
	import { site } from '$lib/config';

	let { title, description, children }: { title: string; description: string; children: Snippet } = $props();
</script>

<svelte:head>
	<title>{title} | {site.name}</title>
	<meta name="description" content={description} />
</svelte:head>

<article class="legal mx-auto max-w-[65ch] px-4 pt-8 pb-8 md:pt-16">
	<h1 class="text-3xl font-semibold tracking-tight md:text-4xl">{title}</h1>
	<p class="mt-2 text-sm" style="color: var(--ink-muted)">Last updated {site.legalUpdated}</p>
	<div class="mt-8">
		{@render children()}
	</div>
</article>

<style>
	.legal :global(h2) {
		margin-top: 2rem;
		font-size: 1.25rem;
		font-weight: 600;
	}
	.legal :global(p),
	.legal :global(ul) {
		margin-top: 0.75rem;
	}
	.legal :global(ul) {
		list-style: disc;
		padding-left: 1.25rem;
	}
	.legal :global(li + li) {
		margin-top: 0.5rem;
	}
	.legal :global(a) {
		color: var(--link);
	}
</style>
