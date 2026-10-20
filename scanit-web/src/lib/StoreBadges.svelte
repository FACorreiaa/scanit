<script lang="ts">
	// Official store badges. URLs live in config.ts, so going live is a one-line change there.
	// No URL: the badge is muted, not a link, with "Coming soon". A TestFlight URL: linked, with a
	// "Beta · TestFlight" caption. Badges are never recoloured, angled or animated (Apple/Google rules).
	import { site } from '$lib/config';

	const apple = site.downloadUrl;
	const appleIsBeta = /testflight\.apple\.com/i.test(apple);
	const play = site.playUrl;
</script>

<div class="flex flex-col items-center gap-5 sm:flex-row sm:items-start sm:justify-center sm:gap-6">
	<div class="flex flex-col items-center gap-1.5">
		{#if apple}
			<a href={apple} class="badge-link block" rel="noopener">
				<picture>
					<source srcset="/badges/download-on-the-app-store-white.svg" media="(prefers-color-scheme: dark)" />
					<img
						src="/badges/download-on-the-app-store.svg"
						alt={appleIsBeta ? 'Download the ScanItNow beta on TestFlight' : 'Download on the App Store'}
						width="132"
						height="44"
						class="block h-11 w-auto"
					/>
				</picture>
			</a>
			{#if appleIsBeta}
				<span class="text-xs" style="color: var(--ink-muted)">Beta · TestFlight</span>
			{/if}
		{:else}
			<picture class="badge-muted block">
				<source srcset="/badges/download-on-the-app-store-white.svg" media="(prefers-color-scheme: dark)" />
				<img
					src="/badges/download-on-the-app-store.svg"
					alt="App Store — coming soon"
					width="132"
					height="44"
					class="block h-11 w-auto"
				/>
			</picture>
			<span class="text-xs" style="color: var(--ink-muted)" aria-hidden="true">Coming soon</span>
		{/if}
	</div>

	<div class="flex flex-col items-center gap-1.5">
		<!-- The Play PNG has built-in padding (564×168 visible of 646×250); crop it so both badges are 44px tall. -->
		{#if play}
			<a href={play} class="badge-link play-crop block" rel="noopener">
				<img src="/badges/google-play-badge.png" alt="Get it on Google Play" width="169" height="66" />
			</a>
		{:else}
			<span class="badge-muted play-crop block">
				<img src="/badges/google-play-badge.png" alt="Google Play — coming soon" width="169" height="66" />
			</span>
			<span class="text-xs" style="color: var(--ink-muted)" aria-hidden="true">Coming soon</span>
		{/if}
	</div>
</div>

<style>
	.badge-muted {
		opacity: 0.45;
		filter: grayscale(1);
	}
	.badge-link {
		border-radius: 8px;
	}
	.play-crop {
		width: 147.7px;
		height: 44px;
		overflow: hidden;
	}
	.play-crop img {
		display: block;
		max-width: none;
		width: 169.2px;
		height: 65.5px;
		margin: -10.74px 0 0 -10.74px;
	}
</style>
