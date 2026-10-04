/** Local device time for resolving relative dates such as "tomorrow" / "jutro". */
export function twoDigits(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function localDate(date: Date): string {
  return `${date.getFullYear()}-${twoDigits(date.getMonth() + 1)}-${twoDigits(date.getDate())}`;
}

export function deviceTimeContext(now: Date = new Date()): string {
  const tomorrow = new Date(now.getTime());
  tomorrow.setDate(tomorrow.getDate() + 1);
  const offset = -now.getTimezoneOffset();
  const zone = `UTC${offset >= 0 ? '+' : '-'}${twoDigits(Math.floor(Math.abs(offset) / 60))}:${twoDigits(Math.abs(offset) % 60)}`;
  return `Phone local date and time: ${localDate(now)} ${twoDigits(now.getHours())}:${twoDigits(now.getMinutes())} (${zone}).\n` +
    `Tomorrow (jutro) is ${localDate(tomorrow)}. Interpret relative dates and times in the phone's local time.`;
}
