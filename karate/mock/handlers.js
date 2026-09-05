// A stand-in for quick-meetings that answers the same five operations — so the whole suite can
// run before the app exists, or without it. Every booking decision is DELEGATED: `calc` below is
// the rulebook's own `Rule.execute('meetings', row)`. The mock holds no copy of the rules, so it
// cannot disagree with the oracle the live lanes grade against.
//
// Two ways in, one file. `mock.sh` serves it on :9981 over the app's own OpenAPI spec, and
// `Twin.mutate` starts it in memory to grade the pinned sequences against mutants of these
// guards. Twin.mutate binds only `Rule` when it evaluates this file — no `File`, no `session`,
// no `Http` — which is why the file is an operation map, why the zone arithmetic lives here
// rather than being pulled in, and why the world is seeded lazily per request.
// `checks/zones.js` reads that arithmetic back out, so there is still only one copy of it.
(function () {

    // ---- wall-clock <-> instant, for the zones calc.js declares -------------------------
    // On a transition day the offset in force BEFORE the change applies up to the change,
    // which is what ZoneRules.getOffset(LocalDateTime) answers and so what the service asks.
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

    // ---- the world -----------------------------------------------------------------------
    // Seeded on first touch, not at eval time - Twin.mutate binds no session when it evaluates
    // this file. The twin's root world is no meetings and exactly the three fixture users it
    // names as ids 1, 2 and 3.
    function seed(session) {
        session.users = [{ id: 1, name: 'alice' }, { id: 2, name: 'bob' }, { id: 3, name: 'charlie' }];
        session.meetings = [];
        return session;
    }

    function store(session) {
        return session.meetings ? session : seed(session);
    }

    var MESSAGES = {
        invalid_duration: 'A meeting cannot start after it ends',
        nonexistent_local_time: 'a gap in the local time-line, typically caused by daylight savings',
        conflict: 'Overlapping meetings exist'
    };

    function nil(v) { return v === null || v === undefined; }

    function fail(response, status, message) {
        response.status = status;
        response.body = { message: message };
    }

    function confirmed(s, userId) {
        var out = [];
        for (var i = 0; i < s.meetings.length; i++) {
            var m = s.meetings[i];
            for (var j = 0; j < m.members.length; j++) {
                if (m.members[j].user === userId
                    && (m.members[j].role === 'OWNER' || m.members[j].role === 'ACCEPTED')) { out.push(m); }
            }
        }
        return out;
    }

    // the rulebook decides; this only shapes the row it reads
    function calc(row) { return Rule.execute('meetings', row); }

    function decide(startMs, durationMins, zone, date, time, against) {
        var free = calc({
            zone: zone, date: date, time: time, durationMins: durationMins,
            hasExisting: false, relStartMins: 0, existingDurationMins: 0
        });
        if (free.outcome === 'refused') { return free.output.reason; }
        for (var i = 0; i < against.length; i++) {
            var e = against[i];
            var r = calc({
                zone: zone, date: date, time: time, durationMins: durationMins, hasExisting: true,
                relStartMins: (e.startMs - startMs) / 60000,
                existingDurationMins: (e.endMs - e.startMs) / 60000
            });
            if (r.outcome === 'refused') { return r.output.reason; }
        }
        return null;
    }

    function findMeeting(s, id) {
        for (var i = 0; i < s.meetings.length; i++) {
            if (s.meetings[i].id === id) { return s.meetings[i]; }
        }
        return null;
    }

    function memberOf(meeting, user) {
        for (var i = 0; i < meeting.members.length; i++) {
            if (meeting.members[i].user === user) { return meeting.members[i]; }
        }
        return null;
    }

    // does joining `meeting` double-book `user`? the rulebook answers, over the whole schedule -
    // the meeting itself included, so a user already confirmed on it conflicts with their own
    // commitment, which is what the app answers
    function conflictsWith(s, meeting, user) {
        var busy = confirmed(s, user);
        var w = wireTime(meeting.startMs);
        return decide(meeting.startMs, (meeting.endMs - meeting.startMs) / 60000, 'UTC',
                      w.date, w.time.substring(0, 5), busy) !== null;
    }

    // ---- the five operations -------------------------------------------------------------

    var createUser = function (request, response, session) {
        var s = store(session);
        var name = request.param('name');
        if (nil(name)) {
            fail(response, 400, 'Required parameter \'name\' is not present.');
        } else {
            var user = { id: s.users.length + 1, name: name };
            s.users.push(user);
            response.body = user;
        }
    };

    var createMeeting = function (request, response, session) {
        var s = store(session);
        var b = request.body;
        var bad = nil(b) || nil(b.duration) || nil(b.duration.from) || nil(b.duration.to)
            || nil(b.duration.from.date) || nil(b.duration.from.time)
            || nil(b.duration.to.date) || nil(b.duration.to.time) || nil(b.timezone);
        if (bad) {
            fail(response, 400, 'Errors in request body');
        } else if (b.timezone !== 'UTC' && b.timezone !== 'Europe/Amsterdam') {
            fail(response, 400, 'Unknown time-zone ID: ' + b.timezone);
        } else {
            var from = b.duration.from;
            var to = b.duration.to;
            var mins = wallMins(from.date, from.time, to.date, to.time);
            var startMs = utcMs(b.timezone, from.date, from.time);
            var time = from.time.substring(0, 5);
            var reason = decide(startMs, mins, b.timezone, from.date, time, confirmed(s, b.userId));
            if (reason !== null) {
                fail(response, 400, MESSAGES[reason]);
            } else {
                var m = {
                    id: s.meetings.length + 1, name: b.name,
                    startMs: startMs, endMs: startMs + mins * 60000,
                    members: [{ user: b.userId, role: 'OWNER' }]
                };
                s.meetings.push(m);
                response.body = { id: m.id, name: b.name, message: 'Meeting created' };
            }
        }
    };

    var invite = function (request, response, session) {
        var s = store(session);
        var ib = request.body;
        if (nil(ib) || nil(ib.meetingId) || nil(ib.invitees)) {
            fail(response, 400, 'Errors in request body');
        } else {
            var mtg = findMeeting(s, ib.meetingId);
            if (mtg === null) {
                fail(response, 404, 'Meeting ' + ib.meetingId + ' not found');
            } else {
                var clash = false;
                // the conflict is decided for every invitee, member or not, before membership is
                for (var i = 0; i < ib.invitees.length; i++) {
                    if (conflictsWith(s, mtg, ib.invitees[i])) { clash = true; }
                }
                if (clash) {
                    fail(response, 400, 'Users have conflicts');
                } else {
                    for (var n = 0; n < ib.invitees.length; n++) {
                        if (memberOf(mtg, ib.invitees[n]) === null) {
                            mtg.members.push({ user: ib.invitees[n], role: 'INVITED' });
                        }
                    }
                    response.body = { message: 'Invited successfully' };
                }
            }
        }
    };

    var accept = function (request, response, session) {
        var s = store(session);
        var ab = request.body;
        if (nil(ab) || nil(ab.meetingId) || nil(ab.userId)) {
            fail(response, 400, 'Errors in request body');
        } else {
            var am = findMeeting(s, ab.meetingId);
            var mem = am === null ? null : memberOf(am, ab.userId);
            if (am === null) {
                fail(response, 404, 'Meeting ' + ab.meetingId + ' not found');
            } else if (conflictsWith(s, am, ab.userId)) {
                fail(response, 400, 'Overlapping meetings exist');
            } else if (mem === null || mem.role !== 'INVITED') {
                fail(response, 400, 'Failed to accept invite');
            } else {
                mem.role = 'ACCEPTED';
                response.body = { message: 'Accepted' };
            }
        }
    };

    var reject = function (request, response, session) {
        var s = store(session);
        var rb = request.body;
        if (nil(rb) || nil(rb.meetingId) || nil(rb.userId)) {
            fail(response, 400, 'Errors in request body');
        } else {
            var rm = findMeeting(s, rb.meetingId);
            var rmem = rm === null ? null : memberOf(rm, rb.userId);
            if (rm === null) {
                fail(response, 404, 'Meeting ' + rb.meetingId + ' not found');
            } else if (rmem === null || rmem.role === 'OWNER' || rmem.role === 'REJECTED') {
                fail(response, 400, 'Failed to reject invite');
            } else {
                rmem.role = 'REJECTED';
                response.body = { message: 'Rejected' };
            }
        }
    };

    // Not an operation of quick-meetings: the mock's own out-of-band reset, the counterpart of
    // reset-sut.sh's database truncate. It is a request rather than a JS call because the engine
    // runs the reset hook while it is inside Twin.live, so a hook that called back into the
    // engine's own eval would deadlock against the replay holding it.
    var resetWorld = function (request, response, session) {
        response.body = { users: seed(session).users };
    };

    return {
        resetWorld: resetWorld,
        createUser: createUser,
        createMeeting: createMeeting,
        invite: invite,
        accept: accept,
        reject: reject,
        // not an operation - the one copy of the zone arithmetic, read back by checks/zones.js
        zones: {
            offsetMins: offsetMins, utcMs: utcMs, wireTime: wireTime,
            wallAdd: wallAdd, wallMins: wallMins
        }
    };
})();
