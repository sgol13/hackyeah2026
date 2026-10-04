/** Where the floating orb settles after a drag (all values in px). */
export interface OrbPoint {
  x: number;
  y: number;
}

/** Snaps the orb to the nearer side edge and keeps it between the status bar and the navigation bar. */
export function snapOrb(x: number, y: number, size: number, screenW: number, screenH: number, margin: number,
  topInset: number, bottomInset: number): OrbPoint {
  const nx = x + size / 2 < screenW / 2 ? margin : screenW - size - margin;
  const minY = topInset + margin;
  const maxY = Math.max(minY, screenH - bottomInset - size - margin);
  return { x: nx, y: Math.min(Math.max(y, minY), maxY) };
}
