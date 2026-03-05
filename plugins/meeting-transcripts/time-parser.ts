/**
 * time-parser.ts — Natural language date/time parser for transcript lookup.
 *
 * Parses a user-supplied string into a DateRange (start/end Date pair), or
 * returns null to signal "grab most recent by mtime".
 *
 * Supported inputs:
 *   'latest' | 'last'           → null (most recent by mtime)
 *   'today'                     → today 00:00–23:59
 *   'yesterday'                 → yesterday 00:00–23:59
 *   '9am' | '2pm' | '14:00'    → closest transcript to that hour, today
 *   'Monday' | 'last Friday'    → that weekday's full day
 *   'YYYY-MM-DD'               → that date's full day
 *
 * Transcript filenames use format: YYYY-MM-DDTHH-MM-SS.md
 */

export interface DateRange {
  start: Date;
  end: Date;
  /** If true, caller should find transcript closest to this time rather than all in range */
  closestTo?: Date;
}

const DAYS_OF_WEEK = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

function startOfDay(d: Date): Date {
  const out = new Date(d);
  out.setHours(0, 0, 0, 0);
  return out;
}

function endOfDay(d: Date): Date {
  const out = new Date(d);
  out.setHours(23, 59, 59, 999);
  return out;
}

function dayRange(d: Date): DateRange {
  return { start: startOfDay(d), end: endOfDay(d) };
}

/** Parse '9am', '2pm', '14:00', '9:30am' → hour (0–23) and minute (0–59), or null. */
function parseTimeOfDay(input: string): { hour: number; minute: number } | null {
  // Match patterns like: 9am, 9:30am, 14:00, 2pm, 11:45pm
  const match = input.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/i);
  if (!match) return null;

  let hour = parseInt(match[1], 10);
  const minute = match[2] ? parseInt(match[2], 10) : 0;
  const meridiem = match[3]?.toLowerCase();

  if (hour < 0 || hour > 23) return null;
  if (minute < 0 || minute > 59) return null;

  if (meridiem === "am") {
    if (hour === 12) hour = 0;
  } else if (meridiem === "pm") {
    if (hour !== 12) hour += 12;
  }

  return { hour, minute };
}

/** Return the most recent past occurrence of a weekday (0=Sun … 6=Sat). */
function mostRecentWeekday(targetDay: number, reference: Date = new Date()): Date {
  const ref = startOfDay(reference);
  const currentDay = ref.getDay();
  let daysBack = (currentDay - targetDay + 7) % 7;
  // If it's today but user said e.g. "Monday" on Monday, give them today
  if (daysBack === 0) daysBack = 0;
  const result = new Date(ref);
  result.setDate(ref.getDate() - daysBack);
  return result;
}

/**
 * Parse a natural-language query into a DateRange, or null for "latest".
 * Throws if the input is unrecognisable.
 */
export function parseTimeQuery(query: string): DateRange | null {
  const normalized = query.trim().toLowerCase();

  // --- latest / last ---
  if (normalized === "latest" || normalized === "last") {
    return null;
  }

  // --- today ---
  if (normalized === "today") {
    return dayRange(new Date());
  }

  // --- yesterday ---
  if (normalized === "yesterday") {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    return dayRange(yesterday);
  }

  // --- YYYY-MM-DD ---
  const isoMatch = normalized.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (isoMatch) {
    const d = new Date(parseInt(isoMatch[1]), parseInt(isoMatch[2]) - 1, parseInt(isoMatch[3]));
    if (!isNaN(d.getTime())) return dayRange(d);
  }

  // --- time of day: 9am, 2pm, 14:00, etc. ---
  const timeOfDay = parseTimeOfDay(normalized);
  if (timeOfDay !== null) {
    const target = new Date();
    target.setHours(timeOfDay.hour, timeOfDay.minute, 0, 0);
    // Search window: ±3 hours around the specified time, on today
    const start = new Date(target);
    start.setHours(Math.max(0, timeOfDay.hour - 3), 0, 0, 0);
    const end = new Date(target);
    end.setHours(Math.min(23, timeOfDay.hour + 3), 59, 59, 999);
    return { start, end, closestTo: target };
  }

  // --- weekday: 'monday', 'last friday', 'this tuesday' ---
  const weekdayMatch = normalized.match(/^(?:(last|this)\s+)?(\w+)$/);
  if (weekdayMatch) {
    const modifier = weekdayMatch[1]; // 'last' | 'this' | undefined
    const dayName = weekdayMatch[2];
    const dayIndex = DAYS_OF_WEEK.indexOf(dayName);
    if (dayIndex !== -1) {
      let base = mostRecentWeekday(dayIndex);
      if (modifier === "last") {
        // Force one week back from the most recent occurrence
        const todayIndex = new Date().getDay();
        if (dayIndex === todayIndex) {
          // "last monday" on monday → previous monday
          base.setDate(base.getDate() - 7);
        } else {
          // Already got most recent; go one more week back
          base.setDate(base.getDate() - 7);
        }
      }
      return dayRange(base);
    }
  }

  throw new Error(`Unrecognised time query: "${query}". Try: latest, today, yesterday, 9am, Monday, 2026-01-15`);
}

/**
 * Parse a filename like YYYY-MM-DDTHH-MM-SS.md into a Date.
 * Returns null if the filename doesn't match the expected format.
 */
export function parseTranscriptDate(filename: string): Date | null {
  // Match YYYY-MM-DDTHH-MM-SS (with optional .md extension, optional leading path)
  const base = filename.split("/").pop() ?? filename;
  const match = base.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})\.md$/);
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match.map(Number);
  return new Date(year, month - 1, day, hour, minute, second);
}
