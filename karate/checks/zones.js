// The wall-clock <-> instant arithmetic the schedule's zones imply, in ONE place: the deck
// driver needs it to place an existing meeting on the UTC line, and the mock needs it to
// decide whether two bookings share an instant. Neither may hold a second copy.
//
//   var Z = File.call('/checks/zones.js', {});   -> {offsetMins, utcMs, wireTime, wallAdd}
//
// The offsets are the ones calc.js's zone table declares; on a transition day the offset in
// force before the change applies up to the change (ZoneRules.getOffset(LocalDateTime), which
// is what the service asks).

function offsetMins(zone, date, localMins) {
    if (zone === 'UTC') { return 0; }
    if (date === '2026-01-15') { return 60; }
    if (date === '2026-06-15') { return 120; }
    if (date === '2026-03-29') { return localMins < 180 ? 60 : 120; }
    return localMins < 180 ? 120 : 60;
}

function utcMs(zone, date, time) {
    var d = date.split('-');
    var t = time.split(':');
    var localMins = Number(t[0]) * 60 + Number(t[1]);
    var asIfUtc = Date.UTC(Number(d[0]), Number(d[1]) - 1, Number(d[2]), Number(t[0]), Number(t[1]));
    return asIfUtc - offsetMins(zone, date, localMins) * 60000;
}

function wireTime(ms) {
    var s = new Date(ms).toISOString();
    return { date: s.substring(0, 10), time: s.substring(11, 19) };
}

// the API's `to` is a WALL-CLOCK time, not an instant, so a duration is added on the local
// clock - across a DST fold the two readings differ and the wire's is the contract
function wallAdd(date, time, mins) {
    var d = date.split('-');
    var t = time.split(':');
    var s = new Date(Date.UTC(Number(d[0]), Number(d[1]) - 1, Number(d[2]),
        Number(t[0]), Number(t[1])) + mins * 60000).toISOString();
    return { date: s.substring(0, 10), time: s.substring(11, 19) };
}

function wallMins(fromDate, fromTime, toDate, toTime) {
    var f = fromDate.split('-'), ft = fromTime.split(':');
    var t = toDate.split('-'), tt = toTime.split(':');
    var a = Date.UTC(Number(f[0]), Number(f[1]) - 1, Number(f[2]), Number(ft[0]), Number(ft[1]));
    var b = Date.UTC(Number(t[0]), Number(t[1]) - 1, Number(t[2]), Number(tt[0]), Number(tt[1]));
    return (b - a) / 60000;
}

({ offsetMins: offsetMins, utcMs: utcMs, wireTime: wireTime, wallAdd: wallAdd, wallMins: wallMins });
