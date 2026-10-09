<script lang="ts">
	import Contact from '$lib/Contact.svelte';
	import LegalPage from '$lib/LegalPage.svelte';
</script>

<LegalPage title="Terms of use" description="The terms for using ScanIt, the shopping total app for iPhone.">
	<p>By using ScanIt you agree to these terms.</p>

	<h2>What ScanIt is</h2>
	<p>
		ScanIt is a personal tool for adding up your shopping. Totals are only as accurate as the prices you scan or type.
		The amount charged at the till is what you actually pay.
	</p>

	<h2>Product information</h2>
	<p>
		Product names and photos come from Open Food Facts, a community database. They may be missing or wrong, and ScanIt
		does not guarantee them.
	</p>

	<h2>Using the app</h2>
	<ul>
		<li>Use ScanIt for your own shopping and in line with each store's rules.</li>
		<li>Do not try to break, reverse engineer or misuse the app.</li>
	</ul>

	<h2>Purchases</h2>
	<p>
		ScanIt is free to use. A one-time purchase may unlock extra features. Purchases are handled by Apple and follow the
		App Store's terms, including refunds.
	</p>

	<h2>No warranty</h2>
	<p>
		ScanIt is provided as it is. To the extent the law allows, we are not liable for losses from relying on its totals,
		prices or product information.
	</p>

	<h2>Contact</h2>
	<p>Questions about these terms: <Contact />.</p>
</LegalPage>
