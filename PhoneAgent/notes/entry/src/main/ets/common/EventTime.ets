export function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function dateText(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function timeText(date: Date): string {
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** Parse local wall time explicitly; reject dates that JavaScript would silently normalize. */
export function eventTimestamp(day: string, time: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !/^\d{2}:\d{2}$/.test(time)) {
    throw new Error('Use YYYY-MM-DD for the date and HH:mm for the time.');
  }
  const year = Number(day.substring(0, 4));
  const month = Number(day.substring(5, 7));
  const date = Number(day.substring(8, 10));
  const hour = Number(time.substring(0, 2));
  const minute = Number(time.substring(3, 5));
  if (year < 1900 || year > 2100 || hour > 23 || minute > 59) {
    throw new Error('Enter a valid date and time.');
  }
  const parsed = new Date(year, month - 1, date, hour, minute);
  if (dateText(parsed) !== day || timeText(parsed) !== time) {
    throw new Error('This date or local time does not exist.');
  }
  return parsed.getTime();
}
