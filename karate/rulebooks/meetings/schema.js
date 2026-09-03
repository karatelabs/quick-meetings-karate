schema = {
    zone: ['UTC', 'Europe/Amsterdam'],
    date: ['2026-01-15', '2026-03-29', '2026-06-15', '2026-10-25'],
    time: '#string',
    durationMins: '#number',
    hasExisting: '#boolean',
    // the existing confirmed meeting, placed relative to the proposed start on the UTC line
    relStartMins: '#number',
    existingDurationMins: '#number'
};
