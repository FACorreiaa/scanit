<script lang="ts">
	// Logo mark + wordmark, swapping to the light-ink variants on dark pages.
	let { height = 28 }: { height?: number } = $props();
</script>

<span class="inline-flex items-center gap-2.5" aria-label="ScanItNow">
	<picture>
		<source srcset="/brand/logo-mark-dark.svg" media="(prefers-color-scheme: dark)" />
		<img src="/brand/logo-mark.svg" alt="" width={height} height={height} style="height: {height}px; width: {height}px" />
	</picture>
	<picture>
		<source srcset="/brand/wordmark-dark.svg" media="(prefers-color-scheme: dark)" />
		<img
			src="/brand/wordmark.svg"
			alt="ScanItNow"
			width={Math.round(height * 0.82 * 5.5)}
			height={Math.round(height * 0.82)}
			style="height: {Math.round(height * 0.82)}px; width: auto"
		/>
	</picture>
</span>
