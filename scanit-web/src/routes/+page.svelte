<script lang="ts">
	import { site } from '$lib/config';
</script>

<svelte:head>
	<title>{site.name}: know your total before the till</title>
	<meta
		name="description"
		content="Scan each product as you shop. ScanItNow keeps a running total and tells you before you go over your limit."
	/>
</svelte:head>

<!-- Hero: copy left, the real trip screen right; stacks on phones. -->
<section class="mx-auto grid max-w-6xl grid-cols-1 items-center gap-12 px-4 pt-12 md:grid-cols-[1.15fr_0.85fr] md:px-8 md:pt-20">
	<div class="max-w-2xl">
		<h1 class="text-4xl leading-none font-semibold tracking-tighter text-balance md:text-6xl">
			Know your total before the till.
		</h1>
		<p class="mt-6 max-w-[48ch] text-lg" style="color: var(--ink-muted)">
			Scan each product as you shop. ScanItNow keeps a running total and tells you before you go over your limit.
		</p>
		<div class="mt-8">
			{#if site.downloadUrl}
				<a
					href={site.downloadUrl}
					class="inline-flex h-12 items-center rounded-full px-6 font-medium whitespace-nowrap no-underline transition-transform active:scale-[0.97]"
					style="background: var(--color-accent); color: var(--color-accent-ink)"
				>
					Get ScanItNow for iPhone
				</a>
			{:else}
				<p class="inline-flex h-12 items-center rounded-full border px-6 font-medium" style="border-color: var(--hairline)">
					Coming soon for iPhone
				</p>
			{/if}
		</div>
	</div>

	<img
		src="/screens/trip.jpg"
		alt="A trip at Lidl in ScanItNow: three items, a total of €5,48 and a red bar showing €0,48 over the €5,00 limit."
		width="600"
		height="1304"
		fetchpriority="high"
		class="mx-auto w-[min(78vw,320px)] rounded-[var(--radius-card)] shadow-[0_24px_60px_-20px_rgb(35_132_59/0.35)]"
	/>
</section>

<!-- Feature row: screen left, text right (mirrors the hero). -->
<section class="mx-auto mt-24 grid max-w-6xl grid-cols-1 items-center gap-12 px-4 md:mt-32 md:grid-cols-[0.85fr_1.15fr] md:px-8">
	<img
		src="/screens/insights.jpg"
		alt="ScanItNow insights: €39,07 this month, average trip €16,08, five of five trips under the limit, and spend by store and category."
		width="600"
		height="1304"
		loading="lazy"
		class="order-2 mx-auto w-[min(78vw,320px)] rounded-[var(--radius-card)] shadow-[0_24px_60px_-20px_rgb(35_132_59/0.35)] md:order-1"
	/>
	<div class="order-1 max-w-[46ch] md:order-2">
		<h2 class="text-3xl font-semibold tracking-tight md:text-4xl">See where the money goes.</h2>
		<p class="mt-4 text-lg" style="color: var(--ink-muted)">
			Spend by store and by category, the prices that went up, and where the things you buy often cost less.
		</p>
	</div>
</section>

<!-- Text-only band: the facts that matter in a supermarket, no cards. -->
<section class="mx-auto mt-24 max-w-6xl px-4 md:mt-32 md:px-8">
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
