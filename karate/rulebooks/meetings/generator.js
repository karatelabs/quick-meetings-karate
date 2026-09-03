function generate(g) {
    g.enum('zone', ['UTC', 'Europe/Amsterdam']);
    // 2026-03-29 carries the Amsterdam spring-forward gap, 2026-10-25 the autumn ambiguity
    g.enum('date', ['2026-01-15', '2026-03-29', '2026-06-15', '2026-10-25']);
    g.enum('time', ['09:00', '02:30', '03:30']);
    // bounds are 1..480, so 0 and 540 are the two out-of-band rows
    g.int('durationMins', 0, 600, [0, 1, 30, 60, 120, 480, 540]);
    g.bool('hasExisting');
    // the offsets and durations below reach every one of Allen's thirteen relations
    g.int('relStartMins', -120, 120, [-90, -60, -30, -15, 0, 15, 30, 60, 90]);
    g.int('existingDurationMins', 0, 480, [0, 30, 60, 90, 120]);
}
