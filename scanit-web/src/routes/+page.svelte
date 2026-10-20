<script lang="ts">
	import { site } from '$lib/config';
	import StoreBadges from '$lib/StoreBadges.svelte';
	import CardWall from '$lib/CardWall.svelte';
</script>

<svelte:head>
	<title>{site.name}: know your total before the till</title>
	<meta
		name="description"
		content="Scan each product as you shop. ScanItNow keeps a running total and tells you before you go over your limit."
	/>
</svelte:head>

<!-- Hero: centred copy, official store badges, and a wall of shelf-label cards fanned along the bottom. -->
<section class="hero relative">
	<div class="hero-glow" aria-hidden="true"></div>
	<div class="relative z-40 mx-auto flex max-w-3xl flex-col items-center px-4 pt-10 text-center md:pt-16">
		<a href="#made-for-the-aisle" class="pill">
			<span class="pill-dot" aria-hidden="true"></span>
			Free on iPhone · no account needed
			<span class="pill-arrow" aria-hidden="true">→</span>
		</a>
		<h1 class="mt-6 text-4xl leading-[1.05] font-bold tracking-tight sm:text-5xl md:text-6xl">
			<span class="block text-balance">Know your total</span>
			<span class="block text-balance" style="color: var(--ink-muted)">before the till.</span>
		</h1>
		<p class="mt-5 max-w-xl text-base sm:text-lg" style="color: var(--ink-muted)">
			Scan each product as you shop. ScanItNow keeps a running total and tells you before you go over your limit.
		</p>
		<div class="mt-8">
			<StoreBadges />
		</div>
	</div>
	<CardWall />
</section>

<!-- Both real screens together: one section, not two alternating rows. -->
<section class="mx-auto mt-24 max-w-6xl px-4 md:mt-32 md:px-8">
	<h2 class="max-w-[22ch] text-3xl font-semibold tracking-tight md:text-4xl">
		Your total as you scan. Your spending, explained.
	</h2>
	<p class="mt-4 max-w-[52ch] text-lg" style="color: var(--ink-muted)">
		The limit bar turns amber, then red, as you near it. Afterwards, see spend by store and category and which prices
		went up.
	</p>
	<div class="mt-12 grid grid-cols-2 items-start gap-4 md:gap-12 md:px-12">
		<img
			src="/screens/trip.jpg"
			alt="A trip at Lidl in ScanItNow: three items, a total of €5,48 and a red bar showing €0,48 over the €5,00 limit."
			width="600"
			height="1304"
			loading="lazy"
			class="mx-auto w-full max-w-[320px] rounded-[var(--radius-card)] shadow-[0_24px_60px_-20px_rgb(35_132_59/0.35)]"
		/>
		<img
			src="/screens/insights.jpg"
			alt="ScanItNow insights: €39,07 this month, average trip €16,08, five of five trips under the limit, and spend by store and category."
			width="600"
			height="1304"
			loading="lazy"
			class="mx-auto mt-12 w-full max-w-[320px] rounded-[var(--radius-card)] shadow-[0_24px_60px_-20px_rgb(35_132_59/0.35)]"
		/>
	</div>
</section>

<!-- Text-only band: the facts that matter in a supermarket, no cards. -->
<section id="made-for-the-aisle" class="mx-auto mt-24 max-w-6xl scroll-mt-8 px-4 md:mt-32 md:px-8">
	<h2 class="text-3xl font-semibold tracking-tight md:text-4xl">Made for the aisle.</h2>
	<dl class="mt-10 grid grid-cols-1 gap-x-12 gap-y-8 md:grid-cols-2">
		<div>
			<dt class="font-semibold">Remembers prices</dt>
			<dd class="mt-1 max-w-[40ch]" style="color: var(--ink-muted)">
				Scan something you bought at this store before and the price fills itself in.
			</dd>
		</div>
		<div>
			<dt class="font-semibold">Works without signal</dt>
			<dd class="mt-1 max-w-[40ch]" style="color: var(--ink-muted)">
				Everything in a trip works offline. Product names fill in once you are back online.
			</dd>
		</div>
		<div>
			<dt class="font-semibold">No account needed</dt>
			<dd class="mt-1 max-w-[40ch]" style="color: var(--ink-muted)">
				Your trips stay on your phone. The camera reads barcodes on the device.
			</dd>
		</div>
		<div>
			<dt class="font-semibold">A limit, if you want one</dt>
			<dd class="mt-1 max-w-[40ch]" style="color: var(--ink-muted)">
				Set a budget for the trip, or just watch the total. Your phone buzzes as you get close.
			</dd>
		</div>
	</dl>
</section>

<style>
	.hero {
		--card-h: clamp(11rem, 26vh, 18rem);
		/* Clip sideways only, so the glow can bleed up behind the header. */
		overflow-x: clip;
		/* Room for the wall: the front-row centre card shows ~80% of its height. */
		padding-bottom: max(12rem, calc(var(--card-h) * 0.8 + 1.5rem));
	}
	@media (min-width: 640px) {
		.hero {
			padding-bottom: max(16rem, calc(var(--card-h) + 3rem));
		}
	}
	.hero-glow {
		position: absolute;
		top: -6rem;
		left: 50%;
		width: 42rem;
		height: 24rem;
		translate: -50% 0;
		border-radius: 9999px;
		background: color-mix(in srgb, var(--color-accent) 10%, transparent);
		filter: blur(64px);
		pointer-events: none;
	}
	@media (prefers-color-scheme: dark) {
		.hero-glow {
			background: color-mix(in srgb, var(--color-accent) 16%, transparent);
		}
	}

	.pill {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.3rem 0.85rem;
		border-radius: 9999px;
		border: 1px solid var(--hairline);
		background: color-mix(in srgb, var(--surface-raised) 70%, transparent);
		color: var(--ink-muted);
		font-size: 0.8125rem;
		text-decoration: none;
		transition: border-color 0.2s ease;
	}
	.pill:hover {
		border-color: color-mix(in srgb, var(--color-accent) 50%, transparent);
	}
	.pill-dot {
		width: 6px;
		height: 6px;
		border-radius: 9999px;
		background: var(--color-accent);
	}
	.pill-arrow {
		opacity: 0.5;
		transition: translate 0.2s ease;
	}
	.pill:hover .pill-arrow {
		translate: 2px 0;
	}
	@media (prefers-reduced-motion: reduce) {
		.pill-arrow {
			transition: none;
		}
	}
</style>
