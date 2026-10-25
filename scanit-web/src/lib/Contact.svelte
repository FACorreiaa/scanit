<script lang="ts">
	import { site } from '$lib/config';
</script>

<!-- Discord always works; the email joins it once the owner sets one. -->
{#if site.contactEmail}
	<a href="mailto:{site.contactEmail}">{site.contactEmail}</a> or
{/if}
<a href={site.discordUrl} target="_blank" rel="noopener noreferrer">Join us on Discord</a>
