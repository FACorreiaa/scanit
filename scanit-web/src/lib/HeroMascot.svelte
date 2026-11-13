<!--
	ScanBot in the hero. The still renders first (prerendered, no JS needed, and the only thing shown
	with reduced motion or Save-Data on). After mount, model-viewer is imported on demand and the 3D
	model fades in over the still once it has loaded, so the ~2 MB model never blocks first paint.
-->
<script lang="ts">
	import { onMount } from 'svelte';

	let live = $state(false);
	let loaded = $state(false);

	onMount(() => {
		const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
		const saveData = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection?.saveData;
		if (reduceMotion || saveData) return;
		import('@google/model-viewer').then(
			() => (live = true),
			() => {} // keep the still
		);
	});
</script>

<div class="hero-mascot">
	<picture class:hide={loaded}>
		<source srcset="/brand/mascot.avif" type="image/avif" />
		<source srcset="/brand/mascot.webp" type="image/webp" />
		<img src="/brand/mascot.png" alt="" width="767" height="641" decoding="async" />
	</picture>
	{#if live}
		<model-viewer
			class:show={loaded}
			src="/models/scanbot.glb"
			alt="ScanBot, the ScanItNow mascot, scanning a parcel's barcode"
			camera-controls
			disable-zoom
			disable-pan
			disable-tap
			touch-action="pan-y"
			interaction-prompt="none"
			auto-rotate
			auto-rotate-delay="0"
			rotation-per-second="12deg"
			camera-orbit="20deg 78deg auto"
			shadow-intensity="0.5"
			exposure="1.5"
			environment-image="neutral"
			onload={() => (loaded = true)}
		></model-viewer>
	{/if}
</div>

<style>
	.hero-mascot {
		position: relative;
		width: var(--mascot-w, 15rem);
		max-width: 100%;
		aspect-ratio: 767 / 641;
	}
	picture,
	img,
	model-viewer {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
	}
	img {
		object-fit: contain;
	}
	picture {
		transition: opacity 0.6s ease;
	}
	picture.hide {
		opacity: 0;
	}
	model-viewer {
		/* Slightly larger than the still: the model frames itself with padding. */
		inset: -20%;
		width: 140%;
		height: 140%;
		opacity: 0;
		transition: opacity 0.6s ease;
		--poster-color: transparent;
		--progress-bar-height: 0;
		outline: none;
	}
	model-viewer.show {
		opacity: 1;
	}
</style>
