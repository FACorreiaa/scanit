<script lang="ts">
	// Decorative wall of thematic cards along the bottom of the hero. Plain 2D: each slot is placed
	// with left/translate/rotate on an arch, and an inner element sways so the two never fight.
	// Content lives in wall-cards.ts. Expects --card-h to be set by the parent.
	import { frontRow, backRow, type WallCard } from '$lib/wall-cards';
	import { ean13Bars, withCheckDigit } from '$lib/ean';

	type Slot = { card: WallCard; x: number; rot: number; y: number; z: number; show: 'base' | 'md' | 'lg'; delay: number };

	const r = (n: number) => Math.round(n * 100) / 100;

	// Front: 15 slots, x 0→100%, rotation +21°→−21°, y +20% at the centre, up to +36.8% at the edges.
	const front: Slot[] = frontRow.slice(0, 15).map((card, i) => ({
		card,
		x: r((i * 100) / 14),
		rot: 21 - 3 * i,
		y: r(20 + 16.8 * ((i - 7) / 7) ** 2),
		z: 20 - Math.abs(i - 7),
		show: [0, 4, 7, 10, 14].includes(i) ? 'base' : [2, 5, 9, 12].includes(i) ? 'md' : 'lg',
		delay: (i % 5) * 0.7
	}));

	// Back: 14 slots, x 3.6→96.4%, rotation +15.6°→−15.6°, y ≈ −14.6% at the centre, ≈ +4% at the edges.
	const back: Slot[] = backRow.slice(0, 14).map((card, i) => ({
		card,
		x: r(3.6 + (i * 92.8) / 13),
		rot: r(15.6 - 2.4 * i),
		y: r(-14.6 + 18.6 * ((i - 6.5) / 6.5) ** 2),
		z: 0,
		show: 'md',
		delay: ((i + 2) % 5) * 0.7
	}));

	const barsCache = new Map<string, ReturnType<typeof ean13Bars>>();
	function bars(ean: string) {
		const code = withCheckDigit(ean);
		if (!barsCache.has(code)) barsCache.set(code, ean13Bars(code));
		return { code, bars: barsCache.get(code)! };
	}
</script>

{#snippet face(card: WallCard)}
	{#if card.kind === 'tag'}
		{@const b = bars(card.ean)}
		<div class="tag" class:promo={card.promo}>
			<div class="tag-top">
				<p class="tag-name">{card.name}</p>
				<p class="muted">{card.size}</p>
			</div>
			<div class="tag-price-box">
				<p class="tag-price">{card.price}</p>
				<p class="tag-unit">{card.unit}</p>
			</div>
			<div class="tag-code">
				<svg viewBox="-6 0 107 32" preserveAspectRatio="none" class="ean">
					{#each b.bars as bar}
						<rect x={bar.x} y="0" width={bar.w} height={bar.guard ? 32 : 27} />
					{/each}
				</svg>
				<p class="ean-digits">{b.code}</p>
			</div>
		</div>
	{:else if card.kind === 'total'}
		<div class="pad stack">
			<p class="eyebrow">{card.store} · {card.items} items</p>
			<div class="center-v">
				<p class="muted">Running total</p>
				<p class="big">{card.total}</p>
				<p class="muted">of {card.limit} limit</p>
			</div>
			<div class="bar"><span style="width: {card.pct}%"></span></div>
			<p class="small accent-ink">{card.left}</p>
		</div>
	{:else if card.kind === 'over'}
		<div class="pad stack over">
			<p class="eyebrow warn-ink">
				<svg viewBox="0 0 16 16" class="ico" aria-hidden="true"><path d="M8 1.5 15 14H1L8 1.5Z" fill="currentColor" /><path d="M8 6v3.6M8 11.4v.1" stroke="var(--over-bg)" stroke-width="1.6" stroke-linecap="round" /></svg>
				Limit
			</p>
			<div class="center-v">
				<p class="warn-ink strong">Over limit by {card.by}</p>
				<p class="big">{card.total}</p>
				<p class="muted">of {card.limit} limit</p>
			</div>
			<div class="bar warn"><span style="width: 100%"></span></div>
		</div>
	{:else if card.kind === 'receipt'}
		<div class="receipt">
			<p class="r-store">{card.store}</p>
			<p class="r-rule"></p>
			{#each card.lines as [name, amount]}
				<p class="r-line"><span>{name}</span><span>{amount}</span></p>
			{/each}
			<p class="r-rule"></p>
			<p class="r-line r-total"><span>TOTAL €</span><span>{card.total}</span></p>
			<p class="r-foot">Scanned with ScanItNow</p>
		</div>
	{:else if card.kind === 'memory'}
		<div class="pad stack">
			<p class="eyebrow">Remembered price</p>
			<div class="center-v">
				<p class="chip">{card.store}</p>
				<p class="strong mt">{card.product}</p>
				<p class="big">{card.price}</p>
				<p class="small" class:up={card.up} class:muted={!card.up}>{card.note}</p>
			</div>
			<p class="small accent-ink">✓ Filled in for you</p>
		</div>
	{:else if card.kind === 'insights'}
		<div class="pad stack">
			<p class="eyebrow">Insights</p>
			<div class="tiles">
				<div class="tile"><p class="muted">This month</p><p class="strong">{card.month}</p></div>
				<div class="tile"><p class="muted">Avg trip</p><p class="strong">{card.avg}</p></div>
			</div>
			<div class="tile wide"><p class="muted">Under limit</p><p class="strong">{card.under}</p></div>
			<div class="stores">
				<p class="muted">By store</p>
				{#each card.stores as [name, amount, pct]}
					<div class="store-row"><span>{name}</span><span class="muted">{amount}</span></div>
					<div class="bar thin"><span style="width: {pct}%"></span></div>
				{/each}
			</div>
		</div>
	{:else if card.kind === 'image'}
		<img src={card.src} alt="" loading="lazy" decoding="async" class="shot" />
	{:else if card.kind === 'mascot'}
		<div class="mascot">
			<picture>
				<source srcset="/brand/mascot.avif" type="image/avif" />
				<img src="/brand/mascot.png" alt="" loading="lazy" decoding="async" />
			</picture>
		</div>
	{/if}
{/snippet}

<div class="wall" aria-hidden="true">
	{#each [...back.map((s) => ({ ...s, row: 'back' })), ...front.map((s) => ({ ...s, row: 'front' }))] as s}
		<div
			class="slot {s.row} show-{s.show}"
			style="--x: {s.x}%; --rot: {s.rot}deg; --y: {s.y}%; z-index: {s.z}"
		>
			<div class="card" style="animation-delay: {s.delay}s">
				<div class="face">{@render face(s.card)}</div>
			</div>
		</div>
	{/each}
	<div class="wall-fade"></div>
</div>

<style>
	.wall {
		--over: #d70015;
		--over-bg: #fff1f1;
		--promo: #ffd60a;
		position: absolute;
		inset-inline: 0;
		bottom: 0;
		height: calc(var(--card-h) * 1.45);
		overflow: hidden;
		pointer-events: none;
		user-select: none;
	}
	@media (prefers-color-scheme: dark) {
		.wall {
			--over: #ff6961;
			--over-bg: #2a1416;
		}
	}

	.slot {
		position: absolute;
		bottom: 0;
		left: var(--x);
		transform-origin: bottom;
		rotate: calc(var(--rot) * 0.55);
		translate: -50% var(--y);
	}
	.slot.back {
		scale: 0.9;
	}
	.show-md,
	.show-lg {
		display: none;
	}
	@media (min-width: 768px) {
		.slot {
			rotate: var(--rot);
		}
		.show-md {
			display: block;
		}
	}
	@media (min-width: 1024px) {
		.show-lg {
			display: block;
		}
	}

	.card {
		position: relative;
		height: var(--card-h);
		aspect-ratio: 2 / 3;
		border-radius: 16px;
		border: 1px solid var(--hairline);
		background: var(--surface-raised);
		box-shadow: 0 22px 44px -14px rgb(28 28 30 / 0.3);
		overflow: hidden;
		font-size: calc(var(--card-h) / 20);
		line-height: 1.25;
		color: var(--ink);
		animation: sway 7s ease-in-out infinite;
	}
	/* Fade each card towards the page so the wall sits behind the copy. */
	.card::after {
		content: '';
		position: absolute;
		inset: 0;
		background: linear-gradient(to top, color-mix(in srgb, var(--surface) 50%, transparent), transparent 60%);
	}
	.face {
		height: 100%;
		filter: brightness(0.94);
	}
	@media (prefers-color-scheme: dark) {
		.card {
			border-color: rgb(255 255 255 / 0.1);
			box-shadow: 0 24px 50px -12px rgb(0 0 0 / 0.7);
		}
		.face {
			filter: brightness(0.7);
		}
	}
	@keyframes sway {
		0%,
		100% {
			transform: translateY(0);
		}
		50% {
			transform: translateY(-10px);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.card {
			animation: none;
		}
	}

	.wall-fade {
		position: absolute;
		inset-inline: 0;
		bottom: 0;
		height: 3rem;
		z-index: 30;
		background: linear-gradient(to top, var(--surface), transparent);
	}

	/* Shared bits */
	p {
		margin: 0;
	}
	.pad {
		height: 100%;
		padding: 1.1em 1em;
	}
	.stack {
		display: flex;
		flex-direction: column;
		gap: 0.5em;
	}
	/* Content flows from the top: the lower third of front-row cards sits below the fold. */
	.center-v {
		display: flex;
		flex-direction: column;
		margin-top: 0.8em;
	}
	.eyebrow {
		display: flex;
		align-items: center;
		gap: 0.35em;
		font-size: 0.85em;
		font-weight: 600;
		color: var(--ink-muted);
	}
	.muted {
		color: var(--ink-muted);
	}
	.small {
		font-size: 0.85em;
	}
	.strong {
		font-weight: 600;
	}
	.mt {
		margin-top: 0.5em;
	}
	.big {
		font-size: 2.4em;
		font-weight: 700;
		letter-spacing: -0.03em;
		line-height: 1.1;
		font-variant-numeric: tabular-nums;
	}
	.accent-ink {
		color: var(--link);
		font-weight: 600;
	}
	.bar {
		height: 0.55em;
		border-radius: 99px;
		background: var(--hairline);
		overflow: hidden;
	}
	.bar span {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--color-accent);
	}
	.bar.thin {
		height: 0.35em;
		margin-bottom: 0.3em;
	}
	.bar.warn span {
		background: var(--over);
	}
	.ico {
		width: 1.1em;
		height: 1.1em;
	}

	/* Over limit */
	.over {
		background: var(--over-bg);
	}
	.warn-ink {
		color: var(--over);
	}

	/* Shelf label */
	.tag {
		height: 100%;
		display: flex;
		flex-direction: column;
		border-top: 0.55em solid var(--color-accent);
	}
	.tag-top {
		padding: 0.9em 1em 0.4em;
	}
	.tag-name {
		font-weight: 700;
		font-size: 1.1em;
		line-height: 1.15;
	}
	.tag-price-box {
		display: flex;
		flex-direction: column;
		padding: 0.6em 1em;
	}
	.tag-price {
		font-size: 3em;
		font-weight: 800;
		letter-spacing: -0.04em;
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.tag-unit {
		margin-top: 0.3em;
		font-size: 0.85em;
		color: var(--ink-muted);
	}
	.tag.promo {
		border-top-color: #1c1c1e;
	}
	.tag.promo .tag-price-box {
		background: var(--promo);
		color: #1c1c1e;
		margin: 0.2em 0.7em 0;
		padding: 0.5em 0.6em;
		border-radius: 0.5em;
	}
	.tag.promo .tag-unit {
		color: rgb(28 28 30 / 0.7);
	}
	.tag-code {
		padding: 0.5em 1em 0;
		width: 82%;
	}
	.ean {
		display: block;
		width: 100%;
		height: 2.6em;
		fill: var(--ink);
	}
	.ean-digits {
		margin-top: 0.2em;
		text-align: center;
		font-family: ui-monospace, 'SF Mono', Menlo, monospace;
		font-size: 0.7em;
		letter-spacing: 0.12em;
	}

	/* Receipt */
	.receipt {
		height: 100%;
		padding: 1.2em 0.9em;
		font-family: ui-monospace, 'SF Mono', Menlo, monospace;
		font-size: 0.78em;
		display: flex;
		flex-direction: column;
		gap: 0.45em;
		background: repeating-linear-gradient(to bottom, transparent 0 0.9em, rgb(128 128 128 / 0.04) 0.9em 1.8em);
	}
	.r-store {
		text-align: center;
		font-weight: 700;
		letter-spacing: 0.15em;
	}
	.r-rule {
		border-top: 1px dashed var(--ink-muted);
		opacity: 0.6;
		margin: 0.2em 0;
	}
	.r-line {
		display: flex;
		justify-content: space-between;
		gap: 0.5em;
	}
	.r-line span:first-child {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.r-total {
		font-weight: 700;
		font-size: 1.15em;
	}
	.r-foot {
		margin-top: 0.6em;
		text-align: center;
		color: var(--ink-muted);
		font-size: 0.85em;
	}

	/* Store memory */
	.chip {
		align-self: flex-start;
		padding: 0.15em 0.6em;
		border-radius: 99px;
		background: color-mix(in srgb, var(--color-accent) 14%, transparent);
		color: var(--link);
		font-weight: 600;
		font-size: 0.85em;
	}
	.up {
		color: #c46a00;
		font-weight: 600;
	}
	@media (prefers-color-scheme: dark) {
		.up {
			color: #ffb340;
		}
	}

	/* Insights */
	.tiles {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.4em;
	}
	.tile {
		padding: 0.45em 0.55em;
		border-radius: 0.6em;
		background: var(--surface);
		font-size: 0.9em;
	}
	.stores {
		display: flex;
		flex-direction: column;
		margin-top: 0.3em;
		gap: 0.25em;
		font-size: 0.9em;
	}
	.store-row {
		display: flex;
		justify-content: space-between;
	}

	/* Images */
	.shot {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: top;
	}
	.mascot {
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		background: radial-gradient(circle at 50% 55%, rgb(16 170 81 / 0.22), rgb(16 170 81 / 0.06) 70%, transparent 71%);
	}
	.mascot img {
		width: 92%;
		height: auto;
	}
</style>
