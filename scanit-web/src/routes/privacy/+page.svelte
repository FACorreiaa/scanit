<script lang="ts">
	import Contact from '$lib/Contact.svelte';
	import LegalPage from '$lib/LegalPage.svelte';
</script>

<LegalPage title="Privacy policy" description="What ScanIt keeps on your phone, the little it sends, and what it never does with your data.">
	<p>
		ScanIt helps you add up your shopping as you go. It is built to work on your phone without an account, and it
		collects as little as it can.
	</p>

	<h2>What stays on your phone</h2>
	<ul>
		<li>Your trips, the items in them, the prices you confirm and the stores you name are stored only on your phone.</li>
		<li>
			The camera is used to read barcodes and price labels. This happens on the device. No photo or video is saved or
			sent anywhere.
		</li>
	</ul>

	<h2>What leaves your phone</h2>
	<ul>
		<li>
			<strong>Product lookups.</strong> When you add a product, its barcode number is sent to
			<a href="https://world.openfoodfacts.org">Open Food Facts</a>, a free public database, to get the product's name
			and photo. Only the barcode number is sent, never the price, the store or anything about you.
		</li>
		<li>
			<strong>Usage statistics.</strong> ScanIt records simple events such as "trip started" or "item added" to learn
			which features help. They never include prices, product names, store names or your location, and they are not
			used for advertising.
		</li>
		<li>
			<strong>Crash reports.</strong> If the app crashes, a technical report is sent so the bug can be fixed. It does not
			include your shopping data.
		</li>
	</ul>

	<h2>What ScanIt never does</h2>
	<ul>
		<li>Sell or share your data with advertisers or data brokers.</li>
		<li>Track you across other apps or websites.</li>
		<li>Use your location.</li>
	</ul>

	<h2>Deleting your data</h2>
	<p>
		Deleting the app deletes everything it stored. See <a href="/delete-account">Delete your data</a> for details.
	</p>

	<h2>Children</h2>
	<p>ScanIt is not directed at children under 13 and does not knowingly collect their data.</p>

	<h2>Changes and contact</h2>
	<p>
		If this policy changes, the date at the top changes too. Questions or requests: <Contact />.
	</p>
</LegalPage>
