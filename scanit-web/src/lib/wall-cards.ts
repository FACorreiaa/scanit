// Content of the hero card wall. Edit freely: order is left → right, the positions come from the
// row geometry in CardWall.svelte. Front row has 15 slots, back row 14 (shown from md up).
// On phones only front slots 1, 5, 8, 11 and 15 show, so keep those varied.

export type WallCard =
	| { kind: 'tag'; name: string; size: string; ean: string; price: string; unit: string; promo?: boolean }
	| { kind: 'total'; store: string; items: number; total: string; limit: string; left: string; pct: number }
	| { kind: 'over'; total: string; limit: string; by: string }
	| { kind: 'receipt'; store: string; lines: [string, string][]; total: string }
	| { kind: 'memory'; store: string; product: string; price: string; note: string; up?: boolean }
	| { kind: 'insights'; month: string; avg: string; under: string; stores: [string, string, number][] }
	| { kind: 'image'; src: string }
	| { kind: 'mascot' };

export const frontRow: WallCard[] = [
	{ kind: 'tag', name: 'Bananas da Madeira', size: 'per kg', ean: '560123450001', price: '€1.29', unit: '€1.29 / kg' },
	{ kind: 'receipt', store: 'LIDL', lines: [['BANANAS', '1.29'], ['IOGURTE ×6', '2.94'], ['PÃO DE FORMA', '1.39'], ['AZEITE 750ML', '8.99']], total: '14.61' },
	{ kind: 'image', src: '/wall/history-framed.webp' },
	{ kind: 'insights', month: '€39.07', avg: '€16.08', under: '5 of 5', stores: [['Lidl', '€19.55', 100], ['Continente', '€19.52', 98]] },
	{ kind: 'over', total: '€52.10', limit: '€50', by: '€2.10' },
	{ kind: 'tag', name: 'Azeite virgem extra', size: '750 ml', ean: '560987650042', price: '€8.99', unit: '€11.99 / l', promo: true },
	{ kind: 'memory', store: 'Continente', product: 'Queijo flamengo', price: '€2.49', note: 'Continente · last time €2.49' },
	{ kind: 'total', store: 'Lidl', items: 14, total: '€38.20', limit: '€50', left: '€11.80 left', pct: 76 },
	{ kind: 'tag', name: 'Iogurte natural', size: '6 × 125 g', ean: '560555120013', price: '€2.94', unit: '€3.92 / kg' },
	{ kind: 'image', src: '/screens/trip.jpg' },
	{ kind: 'mascot' },
	{ kind: 'receipt', store: 'CONTINENTE', lines: [['LEITE MEIO GORDO', '0.89'], ['ARROZ AGULHA', '1.45'], ['CAFÉ MOÍDO', '3.79']], total: '6.13' },
	{ kind: 'tag', name: 'Pão de forma', size: '500 g', ean: '560333780025', price: '€1.39', unit: '€2.78 / kg' },
	{ kind: 'image', src: '/screens/insights.jpg' },
	{ kind: 'memory', store: 'Lidl', product: 'Bananas da Madeira', price: '€1.29', note: 'Lidl · last time €1.29' }
];

export const backRow: WallCard[] = [
	{ kind: 'tag', name: 'Leite meio gordo', size: '1 l', ean: '560444210038', price: '€0.89', unit: '€0.89 / l' },
	{ kind: 'insights', month: '€41.31', avg: '€13.77', under: '3 of 3', stores: [['Lidl', '€25.61', 100], ['Continente', '€15.70', 61]] },
	{ kind: 'receipt', store: 'PINGO DOCE', lines: [['DETERGENTE 1,5L', '6.99'], ['BANANAS', '3.12'], ['ÁGUA 6×1,5L', '1.74']], total: '11.85' },
	{ kind: 'tag', name: 'Café moído', size: '250 g', ean: '560777630041', price: '€3.79', unit: '€15.16 / kg', promo: true },
	{ kind: 'image', src: '/wall/trip-framed.webp' },
	{ kind: 'memory', store: 'Pingo Doce', product: 'Pão de forma', price: '€1.39', note: '↑ 8% since September', up: true },
	{ kind: 'tag', name: 'Arroz agulha', size: '1 kg', ean: '560222910057', price: '€1.45', unit: '€1.45 / kg' },
	{ kind: 'over', total: '€31.40', limit: '€30', by: '€1.40' },
	{ kind: 'total', store: 'Continente', items: 6, total: '€12.40', limit: '€30', left: '€17.60 left', pct: 41 },
	{ kind: 'receipt', store: 'LIDL', lines: [['QUEIJO FLAMENGO', '2.49'], ['IOGURTE ×6', '2.94'], ['LEITE', '0.89']], total: '6.32' },
	{ kind: 'tag', name: 'Detergente líquido', size: '1,5 l', ean: '560666180066', price: '€6.99', unit: '€4.66 / l' },
	{ kind: 'memory', store: 'Lidl', product: 'Iogurte natural', price: '€2.94', note: 'Lidl · last time €2.94' },
	{ kind: 'image', src: '/wall/history-framed.webp' },
	{ kind: 'tag', name: 'Água mineral', size: '6 × 1,5 l', ean: '560111470079', price: '€1.74', unit: '€0.19 / l', promo: true }
];
