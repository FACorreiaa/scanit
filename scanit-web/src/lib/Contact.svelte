<script lang="ts">
	import { site } from '$lib/config';
</script>

{#if site.contactEmail}
	<a href="mailto:{site.contactEmail}">{site.contactEmail}</a>
{:else}
	the contact address on the ScanItNow App Store page
{/if}
