/**
 * Values the owner fills in (BACKLOG FND-001, WEB-002). Until then the page says so honestly
 * instead of linking nowhere.
 */
export const site = {
	name: 'ScanItNow',
	/**
	 * TestFlight public link now, App Store URL after REL-004. Empty: the Apple badge shows
	 * muted with "Coming soon". A testflight.apple.com link adds a "Beta · TestFlight" caption.
	 */
	downloadUrl: '' as string,
	/** Google Play listing (P8). Empty: the Play badge shows muted with "Coming soon". */
	playUrl: '' as string,
	/** Owner's X profile, linked from the header. */
	xUrl: 'https://x.com/fatc88',
	/** Contact for privacy and deletion requests. OPEN: owner's choice. */
	contactEmail: '' as string,
	/** Last change to the legal pages. */
	legalUpdated: '9 October 2026'
};
