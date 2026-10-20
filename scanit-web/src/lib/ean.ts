// EAN-13 bar pattern for the decorative shelf labels, so the barcodes on the page are real ones.

const L = ['0001101', '0011001', '0010011', '0111101', '0100011', '0110001', '0101111', '0111011', '0110111', '0001011'];
const G = ['0100111', '0110011', '0011011', '0100001', '0011101', '0111001', '0000101', '0010001', '0001001', '0010111'];
const R = ['1110010', '1100110', '1101100', '1000010', '1011100', '1001110', '1010000', '1000100', '1001000', '1110100'];
const PARITY = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL'];

/** Appends the check digit to 12 digits. */
export function withCheckDigit(twelve: string): string {
	const sum = [...twelve].reduce((s, d, i) => s + Number(d) * (i % 2 ? 3 : 1), 0);
	return twelve + ((10 - (sum % 10)) % 10);
}

export type Bar = { x: number; w: number; guard: boolean };

/** Bars of an EAN-13 in module units (95 wide). Guard bars are flagged so they can be drawn longer. */
export function ean13Bars(code: string): Bar[] {
	const d = [...code].map(Number);
	const parity = PARITY[d[0]];
	let bits = '101';
	for (let i = 1; i <= 6; i++) bits += (parity[i - 1] === 'L' ? L : G)[d[i]];
	bits += '01010';
	for (let i = 7; i <= 12; i++) bits += R[d[i]];
	bits += '101';

	const guard = (x: number) => x < 3 || (x >= 45 && x < 50) || x >= 92;
	const bars: Bar[] = [];
	for (let x = 0; x < bits.length; x++) {
		if (bits[x] !== '1') continue;
		const last = bars[bars.length - 1];
		if (last && last.x + last.w === x && last.guard === guard(x)) last.w++;
		else bars.push({ x, w: 1, guard: guard(x) });
	}
	return bars;
}
