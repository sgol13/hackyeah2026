/** The one bundled typeface: Bricolage Grotesque SemiBold, for the wordmark, page titles and the greeting. */
export const DISPLAY_FONT = 'Bricolage';

/** Registers the bundled fonts with one window's UI. Call once per window (app and every overlay window). */
export function registerFonts(ui: UIContext): void {
  ui.getFont().registerFont({ familyName: DISPLAY_FONT, familySrc: $rawfile('fonts/BricolageGrotesque-SemiBold.ttf') });
}
