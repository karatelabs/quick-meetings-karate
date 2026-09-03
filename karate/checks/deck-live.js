// Drive a deck of `meetings` rows through the live quick-meetings API with calc.js as the oracle.
// Every row gets a fresh user, so rows never see each other and no database reset is needed.
//
//   File.call('/checks/deck-live.js', {rows: [...], baseUrl: 'http://localhost:9981'})
//     -> {rows, agreed, diverged[], setupFailed[], byRelation}
//
// A row agrees when the verdict AND the refusal reason match: a service that refuses the right
// input for the wrong reason has a different bug, not the same behaviour.

// the offsets the calc's zone table implies, as the wire needs them
function offsetMins(zone, date, localMins) {
    if (zone === 'UTC') { return 0; }
    if (date === '2026-01-15') { return 60; }
    if (date === '2026-06-15') { return 120; }
    // on a transition day the offset before the change applies up to the change (the rule
    // ZoneRules.getOffset(LocalDateTime) follows, which is what the service asks)
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

// the service's refusal messages, read back as the rulebook's own reasons
function liveReason(status, body) {
    if (status === 200) { return null; }
    var msg = (body && body.message) || '';
    if (msg.indexOf('gap in the local time-line') >= 0) { return 'nonexistent_local_time'; }
    if (msg.indexOf('cannot start') >= 0) { return 'invalid_duration'; }
    if (msg.indexOf('Overlapping meetings exist') >= 0) { return 'conflict'; }
    return 'unclassified: ' + msg;
}

function createBody(userId, name, zone, fromDate, fromTime, toDate, toTime) {
    return {
        userId: userId, name: name, timezone: zone,
        duration: { from: { date: fromDate, time: fromTime }, to: { date: toDate, time: toTime } }
    };
}

var run = function (opts) {
    var rows = opts.rows;
    var base = opts.baseUrl || 'http://localhost:9981';
    Http.configure({ baseUrl: base });

    var agreed = 0;
    var diverged = [];
    var setupFailed = [];
    var byRelation = {};

    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        var oracle = Rule.execute('meetings', row);
        var relation = String(oracle.output.relation);
        byRelation[relation] = (byRelation[relation] || 0) + 1;

        var user = Http.send({ method: 'POST', url: '/user', query: { name: 'deck-' + i }, full: true });
        if (user.status !== 200) { setupFailed.push({ at: i, stage: 'user', status: user.status }); continue; }
        var uid = user.body.id;

        var startMs = utcMs(row.zone, row.date, row.time);

        if (row.hasExisting && row.existingDurationMins > 0) {
            var eFrom = wireTime(startMs + row.relStartMins * 60000);
            var eTo = wireTime(startMs + (row.relStartMins + row.existingDurationMins) * 60000);
            var pre = Http.post('/meeting',
                createBody(uid, 'existing-' + i, 'UTC', eFrom.date, eFrom.time, eTo.date, eTo.time),
                { full: true });
            if (pre.status !== 200) {
                setupFailed.push({ at: i, stage: 'existing', status: pre.status, body: pre.body, row: row });
                continue;
            }
        }

        // the API's `to` is a WALL-CLOCK time, not an instant, so the duration is added on the
        // local clock - across a DST fold the two readings differ and the wire's is the contract
        var pFrom = { date: row.date, time: row.time + ':00' };
        var pTo = wallAdd(row.date, row.time, row.durationMins);
        var res = Http.post('/meeting',
            createBody(uid, 'proposed-' + i, row.zone, pFrom.date, pFrom.time, pTo.date, pTo.time),
            { full: true });

        var live = res.status === 200 ? 'created' : 'refused';
        var reason = liveReason(res.status, res.body);
        if (live === oracle.outcome && reason === oracle.output.reason) {
            agreed = agreed + 1;
        } else {
            diverged.push({
                at: i, row: row, relation: relation,
                oracle: oracle.outcome, oracleReason: oracle.output.reason,
                live: live, liveReason: reason, status: res.status, body: res.body
            });
        }
    }

    return { rows: rows.length, agreed: agreed, diverged: diverged, setupFailed: setupFailed, byRelation: byRelation };
};

function wallAdd(date, time, mins) {
    var d = date.split('-');
    var t = time.split(':');
    var s = new Date(Date.UTC(Number(d[0]), Number(d[1]) - 1, Number(d[2]),
        Number(t[0]), Number(t[1])) + mins * 60000).toISOString();
    return { date: s.substring(0, 10), time: s.substring(11, 19) };
}

run;
