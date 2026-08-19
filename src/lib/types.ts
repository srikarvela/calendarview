export type CalEvent = {
  id: string;
  title: string;
  start: string; // ISO datetime, or YYYY-MM-DD for all-day
  end: string;
  allDay: boolean;
  location?: string;
  meetLink?: string;
  attendees: number;
  color: string;
  calendar: string;
  declined: boolean;
};

export type EventsPayload = {
  events: CalEvent[];
  fetchedAt: string;
};
