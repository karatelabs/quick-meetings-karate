// A stand-in for quick-meetings that answers the same five endpoints — so the whole suite can
// run before the app exists, or without it. Every booking decision is DELEGATED: `session.calc`
// is the rulebook's own `Rule.execute('meetings', row)`, and `session.Z` is the shared
// wall-clock/instant arithmetic of checks/zones.js. The mock holds no copy of either, so it
// cannot disagree with the oracle the live lanes grade against.
//
// Started by mock.sh, which seeds those two.

var Z = session.Z;
var calc = session.calc;

session.users = session.users || [];
session.meetings = session.meetings || [];

var MESSAGES = {
    invalid_duration: 'A meeting cannot start after it ends',
    nonexistent_local_time: 'a gap in the local time-line, typically caused by daylight savings',
    conflict: 'Overlapping meetings exist'
};

function nil(v) { return v === null || v === undefined; }

function fail(status, message) {
    response.status = status;
    response.body = { message: message };
}

function confirmed(userId) {
    var out = [];
    for (var i = 0; i < session.meetings.length; i++) {
        var m = session.meetings[i];
        for (var j = 0; j < m.members.length; j++) {
            if (m.members[j].user === userId
                && (m.members[j].role === 'OWNER' || m.members[j].role === 'ACCEPTED')) { out.push(m); }
        }
    }
    return out;
}

// the rulebook decides; this only shapes the row it reads
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

function findMeeting(id) {
    for (var i = 0; i < session.meetings.length; i++) {
        if (session.meetings[i].id === id) { return session.meetings[i]; }
    }
    return null;
}

function memberOf(meeting, user) {
    for (var i = 0; i < meeting.members.length; i++) {
        if (meeting.members[i].user === user) { return meeting.members[i]; }
    }
    return null;
}

// does joining `meeting` double-book `user`? the rulebook answers, over the rest of the schedule
function conflictsWith(meeting, user) {
    var busy = [];
    var mine = confirmed(user);
    for (var i = 0; i < mine.length; i++) { if (mine[i].id !== meeting.id) { busy.push(mine[i]); } }
    var w = Z.wireTime(meeting.startMs);
    return decide(meeting.startMs, (meeting.endMs - meeting.startMs) / 60000, 'UTC',
                  w.date, w.time.substring(0, 5), busy) !== null;
}

if (!request.post) {
    fail(404, 'No static resource ' + request.path + '.');
} else if (request.pathMatches('/__reset')) {
    // the stand-in's out-of-band reset, the counterpart of reset-sut.sh's database truncate:
    // no meetings, and the three fixture users the twin names as ids 1, 2 and 3
    session.users = [{ id: 1, name: 'alice' }, { id: 2, name: 'bob' }, { id: 3, name: 'charlie' }];
    session.meetings = [];
    response.body = { users: session.users };
} else if (request.pathMatches('/user')) {
    var name = request.param('name');
    if (name === null || name === undefined) {
        fail(400, 'Required parameter \'name\' is not present.');
    } else {
        var user = { id: session.users.length + 1, name: name };
        session.users.push(user);
        response.body = user;
    }
} else if (request.pathMatches('/meeting')) {
    var b = request.body;
    var bad = nil(b) || nil(b.duration) || nil(b.duration.from) || nil(b.duration.to)
        || nil(b.duration.from.date) || nil(b.duration.from.time)
        || nil(b.duration.to.date) || nil(b.duration.to.time) || nil(b.timezone);
    if (bad) {
        fail(400, 'Errors in request body');
    } else if (b.timezone !== 'UTC' && b.timezone !== 'Europe/Amsterdam') {
        fail(400, 'Unknown time-zone ID: ' + b.timezone);
    } else {
        var from = b.duration.from;
        var to = b.duration.to;
        var mins = Z.wallMins(from.date, from.time, to.date, to.time);
        var startMs = Z.utcMs(b.timezone, from.date, from.time);
        var time = from.time.substring(0, 5);
        var reason = decide(startMs, mins, b.timezone, from.date, time, confirmed(b.userId));
        if (reason !== null) {
            fail(400, MESSAGES[reason]);
        } else {
            var m = {
                id: session.meetings.length + 1, name: b.name,
                startMs: startMs, endMs: startMs + mins * 60000,
                members: [{ user: b.userId, role: 'OWNER' }]
            };
            session.meetings.push(m);
            response.body = { id: m.id, name: b.name, message: 'Meeting created' };
        }
    }
} else if (request.pathMatches('/meeting/invite')) {
    var ib = request.body;
    if (nil(ib) || nil(ib.meetingId) || nil(ib.invitees)) {
        fail(400, 'Errors in request body');
    } else {
        var mtg = findMeeting(ib.meetingId);
        if (mtg === null) {
            fail(404, 'Meeting ' + ib.meetingId + ' not found');
        } else {
            var clash = false;
            for (var i = 0; i < ib.invitees.length; i++) {
                if (memberOf(mtg, ib.invitees[i]) !== null) { continue; }
                if (conflictsWith(mtg, ib.invitees[i])) { clash = true; }
            }
            if (clash) {
                fail(400, 'Users have conflicts');
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
} else if (request.pathMatches('/meeting/accept')) {
    var ab = request.body;
    if (nil(ab) || nil(ab.meetingId) || nil(ab.userId)) {
        fail(400, 'Errors in request body');
    } else {
        var am = findMeeting(ab.meetingId);
        var mem = am === null ? null : memberOf(am, ab.userId);
        if (am === null) {
            fail(404, 'Meeting ' + ab.meetingId + ' not found');
        } else if (mem === null || mem.role !== 'INVITED') {
            fail(400, 'Failed to accept invite');
        } else if (conflictsWith(am, ab.userId)) {
            fail(400, 'Overlapping meetings exist');
        } else {
            mem.role = 'ACCEPTED';
            response.body = { message: 'Accepted' };
        }
    }
} else if (request.pathMatches('/meeting/reject')) {
    var rb = request.body;
    if (nil(rb) || nil(rb.meetingId) || nil(rb.userId)) {
        fail(400, 'Errors in request body');
    } else {
        var rm = findMeeting(rb.meetingId);
        var rmem = rm === null ? null : memberOf(rm, rb.userId);
        if (rm === null) {
            fail(404, 'Meeting ' + rb.meetingId + ' not found');
        } else if (rmem === null || rmem.role === 'OWNER' || rmem.role === 'REJECTED') {
            fail(400, 'Failed to reject invite');
        } else {
            rmem.role = 'REJECTED';
            response.body = { message: 'Rejected' };
        }
    }
} else {
    fail(404, 'No static resource ' + request.path + '.');
}
