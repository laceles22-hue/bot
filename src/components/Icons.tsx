export function IconSprite() {
  return (
    <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true">
      <symbol id="i-calendar" viewBox="0 0 24 24">
        <rect x="3.5" y="5" width="17" height="15" rx="2.5" />
        <line x1="3.5" y1="9.5" x2="20.5" y2="9.5" />
        <line x1="8" y1="3" x2="8" y2="6.5" />
        <line x1="16" y1="3" x2="16" y2="6.5" />
      </symbol>
      <symbol id="i-users" viewBox="0 0 24 24">
        <circle cx="9" cy="8.5" r="3.2" />
        <path d="M3.5 19.5c0-3 2.5-5 5.5-5s5.5 2 5.5 5" />
        <circle cx="17" cy="9.5" r="2.4" />
        <path d="M15.8 14.7c2.4.3 4.2 2 4.2 4.3" />
      </symbol>
      <symbol id="i-receipt" viewBox="0 0 24 24">
        <path d="M6 3.5h12v17l-2.2-1.5-2.1 1.5-2.2-1.5-2.1 1.5-2.2-1.5-1.2.9v-16Z" />
        <line x1="8.5" y1="8" x2="15.5" y2="8" />
        <line x1="8.5" y1="11.5" x2="15.5" y2="11.5" />
      </symbol>
      <symbol id="i-box" viewBox="0 0 24 24">
        <path d="M4 8.2 12 4l8 4.2v7.6L12 20l-8-4.2z" />
        <path d="M4 8.2 12 12l8-3.8" />
        <line x1="12" y1="12" x2="12" y2="20" />
      </symbol>
      <symbol id="i-bars" viewBox="0 0 24 24">
        <line x1="5" y1="19" x2="5" y2="12" />
        <line x1="12" y1="19" x2="12" y2="7" />
        <line x1="19" y1="19" x2="19" y2="15" />
      </symbol>
      <symbol id="i-trend" viewBox="0 0 24 24">
        <polyline points="4,17 9,12 13,15 20,6" />
        <polyline points="14,6 20,6 20,12" />
      </symbol>
    </svg>
  );
}

export function Icon({ name }: { name: string }) {
  return (
    <svg className="icon">
      <use href={`#i-${name}`} />
    </svg>
  );
}
