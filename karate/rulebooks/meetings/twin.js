// quick-meetings — the scheduling lifecycle as a behaviour model.
// Three users share a calendar; a meeting is created, invited to, accepted and rejected.
// The overlap decision is never re-implemented here: every conflict question goes to the
// rulebook through t.calc.

var USERS = [1, 2, 3];
var MAX_MEETINGS = 2;
var DAY = '2026-06-15';
var ZONE = 'UTC';
var MISSING_MEETING_ID = 999999;

// minutes of day; A and B overlap, C only touches A (a conflict under the closed-interval
// convention the schedule uses), D is clear of all of them and E sits strictly inside A
var SLOTS = {
    A: { time: '09:00', start: 540, end: 600 },
    B: { time: '09:30', start: 570, end: 630 },
    C: { time: '10:00', start: 600, end: 660 },
    D: { time: '14:00', start: 840, end: 900 },
    E: { time: '09:15', start: 555, end: 585 }
};

function hhmmss(mins) {
    var h = Math.floor(mins / 60);
    var m = mins - h * 60;
    return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m + ':00';
}

function memberOf(meeting, user) {
    for (var i = 0; i < meeting.members.length; i++) {
        if (meeting.members[i].user === user) { return meeting.members[i]; }
    }
    return null;
}

function isConfirmed(role) {
    return role === 'OWNER' || role === 'ACCEPTED';
}

// the user's confirmed schedule — the only rows the overlap rule looks at
function confirmed(w, user) {
    var out = [];
    for (var i = 0; i < w.meetings.length; i++) {
        var m = memberOf(w.meetings[i], user);
        if (m !== null && isConfirmed(m.role)) { out.push(w.meetings[i]); }
    }
    return out;
}

// the rulebook decides; this only shapes the row
function conflicts(proposed, existing) {
    var r = t.calc({
        zone: ZONE, date: DAY, time: hhmmss(proposed.start).substring(0, 5),
        durationMins: proposed.end - proposed.start,
        hasExisting: true,
        relStartMins: existing.start - proposed.start,
        existingDurationMins: existing.end - existing.start
    });
    return r.output.decision === 'refused';
}

// the schedule is not read as excluding the proposed meeting: a user already confirmed on it holds
// a commitment that overlaps it - itself - and the service refuses the invite and the acceptance on
// exactly that ground
function conflictsWithSchedule(w, user, proposed) {
    var busy = confirmed(w, user);
    for (var i = 0; i < busy.length; i++) {
        if (conflicts(proposed, busy[i])) { return true; }
    }
    return false;
}

// ---- refusal reasons, at the granularity the wire can tell apart --------------------
// reject answers every refusal with one body, so the model declares one reject reason.
var CREATE_CONFLICT = 'the meeting overlaps a meeting the user has already confirmed';
var INVITE_NO_MEETING = 'there is no such meeting to invite anyone to';
var INVITE_CONFLICT = 'the meeting overlaps a meeting the invitee has already confirmed';
var ACCEPT_NO_MEETING = 'there is no such meeting to accept';
var ACCEPT_NOT_INVITED = 'the user holds no open invitation to this meeting';
var ACCEPT_CONFLICT = 'accepting would overlap a meeting the user has already confirmed';
var REJECT_REFUSED = 'reject is refused - the user holds no invitation or acceptance on this meeting';

t.init(function (w) {
    w.meetings = [];
});

t.state('empty', function (w) { return w.meetings.length === 0; });
t.state('scheduled', function (w) {
    return w.meetings.length > 0 && !anyRole(w, 'INVITED') && !anyRole(w, 'ACCEPTED');
});
t.state('hasPending', function (w) { return anyRole(w, 'INVITED'); });
t.state('hasAccepted', function (w) { return anyRole(w, 'ACCEPTED'); });
t.state('booked', function (w) { return w.meetings.length === MAX_MEETINGS; });

function anyRole(w, role) {
    for (var i = 0; i < w.meetings.length; i++) {
        for (var j = 0; j < w.meetings[i].members.length; j++) {
            if (w.meetings[i].members[j].role === role) { return true; }
        }
    }
    return false;
}

t.command('create', {
    // the model carries two meetings; a full world is where it stops looking, not a rule the
    // service holds - no request can make the app refuse a third meeting
    when: function (w) { return w.meetings.length < MAX_MEETINGS; },
    scopeGuard: true,
    args: function (a) {
        a.enum('owner', [1, 2]);
        a.enum('slot', ['A', 'B', 'C', 'D', 'E']);
    },
    apply: function (w, a) {
        var s = SLOTS[a.slot];
        var proposed = { id: -1, start: s.start, end: s.end };
        if (conflictsWithSchedule(w, a.owner, proposed)) { t.reject(CREATE_CONFLICT); }
        w.meetings.push({
            id: w.meetings.length + 1, owner: a.owner, slot: a.slot,
            start: s.start, end: s.end,
            members: [{ user: a.owner, role: 'OWNER' }]
        });
    },
    then: function (before, after) { return after.meetings.length === before.meetings.length + 1; },
    req: 'QM-001/1',
    request: function (w, a) {
        var s = SLOTS[a.slot];
        return {
            method: 'POST', path: '/meeting',
            body: {
                userId: a.owner, name: 'slot-' + a.slot, timezone: ZONE,
                duration: {
                    from: { date: DAY, time: hhmmss(s.start) },
                    to: { date: DAY, time: hhmmss(s.end) }
                }
            }
        };
    },
    observe: function (r) {
        if (r.status === 200) { return { kind: 'applied' }; }
        if (r.status === 400) { return { kind: 'refused', reason: CREATE_CONFLICT }; }
        return { kind: 'unknown' };
    },
    captures: ['meetings[*].id'],
    capture: function (w, r) { w.meetings[w.meetings.length - 1].id = r.body.id; }
});

t.command('invite', {
    when: function (w) { return w.meetings.length > 0; },
    args: function (a) {
        a.enum('m', [0, 1]);
        a.enum('user', USERS);
    },
    // re-inviting someone who already holds an open invitation is a no-op the service answers 200
    // to, so the command declares itself idempotent rather than refusing something the wire accepts
    idempotent: true,
    apply: function (w, a) {
        if (a.m >= w.meetings.length) { t.reject(INVITE_NO_MEETING); }
        var mtg = w.meetings[a.m];
        // the conflict is decided before membership is, as the service decides it
        if (conflictsWithSchedule(w, a.user, mtg)) { t.reject(INVITE_CONFLICT); }
        if (memberOf(mtg, a.user) !== null) { return; }
        mtg.members.push({ user: a.user, role: 'INVITED' });
    },
    req: 'QM-005/1',
    request: function (w, a) {
        var id = a.m < w.meetings.length ? w.meetings[a.m].id : MISSING_MEETING_ID;
        return { method: 'POST', path: '/meeting/invite', body: { meetingId: id, invitees: [a.user] } };
    },
    observe: function (r) {
        if (r.status === 200) { return { kind: 'applied' }; }
        if (r.status === 404) { return { kind: 'refused', reason: INVITE_NO_MEETING }; }
        if (r.status === 400) { return { kind: 'refused', reason: INVITE_CONFLICT }; }
        return { kind: 'unknown' };
    },
    // the empty world sends MISSING_MEETING_ID, so the guard's refusal reaches the wire as the
    // observer's 404 reason
    refusals: { guard: INVITE_NO_MEETING }
});

t.command('accept', {
    when: function (w) { return w.meetings.length > 0; },
    args: function (a) {
        a.enum('m', [0, 1]);
        a.enum('user', USERS);
    },
    apply: function (w, a) {
        if (a.m >= w.meetings.length) { t.reject(ACCEPT_NO_MEETING); }
        var mtg = w.meetings[a.m];
        if (conflictsWithSchedule(w, a.user, mtg)) { t.reject(ACCEPT_CONFLICT); }
        var mem = memberOf(mtg, a.user);
        if (mem === null || mem.role !== 'INVITED') { t.reject(ACCEPT_NOT_INVITED); }
        mem.role = 'ACCEPTED';
    },
    req: 'QM-006/1',
    request: function (w, a) {
        var id = a.m < w.meetings.length ? w.meetings[a.m].id : MISSING_MEETING_ID;
        return { method: 'POST', path: '/meeting/accept', body: { meetingId: id, userId: a.user } };
    },
    observe: function (r) {
        if (r.status === 200) { return { kind: 'applied' }; }
        if (r.status === 404) { return { kind: 'refused', reason: ACCEPT_NO_MEETING }; }
        if (r.status === 400) {
            return r.body && r.body.message === 'Overlapping meetings exist'
                ? { kind: 'refused', reason: ACCEPT_CONFLICT }
                : { kind: 'refused', reason: ACCEPT_NOT_INVITED };
        }
        return { kind: 'unknown' };
    },
    refusals: { guard: ACCEPT_NO_MEETING }
});

t.command('reject', {
    when: function (w) { return w.meetings.length > 0; },
    args: function (a) {
        a.enum('m', [0, 1]);
        a.enum('user', USERS);
    },
    apply: function (w, a) {
        if (a.m >= w.meetings.length) { t.reject(REJECT_REFUSED); }
        var mtg = w.meetings[a.m];
        var mem = memberOf(mtg, a.user);
        // an owner may not walk out of their own meeting - it would leave nobody confirmed
        if (mem === null || mem.role === 'OWNER' || mem.role === 'REJECTED') { t.reject(REJECT_REFUSED); }
        mem.role = 'REJECTED';
    },
    req: 'QM-007/1',
    request: function (w, a) {
        var id = a.m < w.meetings.length ? w.meetings[a.m].id : MISSING_MEETING_ID;
        return { method: 'POST', path: '/meeting/reject', body: { meetingId: id, userId: a.user } };
    },
    observe: function (r) {
        if (r.status === 200) { return { kind: 'applied' }; }
        if (r.status === 400 || r.status === 404) { return { kind: 'refused', reason: REJECT_REFUSED }; }
        return { kind: 'unknown' };
    },
    refusals: { guard: REJECT_REFUSED }
});

// t.calc is apply-only, so the invariant states the closed-interval test directly (QM-002)
t.always('no user holds two overlapping confirmed meetings', function (w) {
    for (var u = 0; u < USERS.length; u++) {
        var busy = confirmed(w, USERS[u]);
        for (var i = 0; i < busy.length; i++) {
            for (var j = i + 1; j < busy.length; j++) {
                if (busy[i].start <= busy[j].end && busy[j].start <= busy[i].end) { return false; }
            }
        }
    }
    return true;
});

t.always('every meeting has an owner or an accepted member', function (w) {
    for (var i = 0; i < w.meetings.length; i++) {
        var ok = false;
        for (var j = 0; j < w.meetings[i].members.length; j++) {
            if (isConfirmed(w.meetings[i].members[j].role)) { ok = true; }
        }
        if (!ok) { return false; }
    }
    return true;
});
