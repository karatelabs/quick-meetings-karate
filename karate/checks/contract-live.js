// The transport contract, below the business rules: whatever we send, the service answers with a
// JSON object and never a 5xx. Nothing here consults the rulebook - these are properties of the
// surface, not of the schedule.
//
//   File.call('/checks/contract-live.js', {baseUrl: 'http://localhost:9981'})
//     -> {probes, ok, violations[]}

var PATHS = ['/user', '/meeting', '/meeting/invite', '/meeting/accept', '/meeting/reject',
    '/nothing-here', '/'];
var ACCEPTS = ['application/json', 'text/html', '*/*'];
var BODIES = [
    null,
    {},
    { userId: 1 },
    { userId: 1, name: 'x', timezone: 'UTC' },
    { userId: 1, name: 'x', timezone: 'UTC', duration: {} },
    { userId: 1, name: 'x', timezone: 'Mars/Olympus', duration: { from: { date: '2026-06-15', time: '09:00:00' }, to: { date: '2026-06-15', time: '10:00:00' } } },
    { meetingId: 999999, userId: 1 },
    { meetingId: 999999, invitees: [1] }
];

var run = function (opts) {
    Http.configure({ baseUrl: opts.baseUrl || 'http://localhost:9981' });
    var probes = 0;
    var violations = [];

    for (var p = 0; p < PATHS.length; p++) {
        for (var a = 0; a < ACCEPTS.length; a++) {
            for (var b = 0; b < BODIES.length; b++) {
                probes = probes + 1;
                var res = Http.send({
                    method: 'POST', url: PATHS[p], body: BODIES[b],
                    headers: { Accept: ACCEPTS[a], 'Content-Type': 'application/json' }, full: true
                });
                var why = null;
                if (res.status >= 500) { why = 'status ' + res.status; }
                else if (res.body === null || res.body === undefined) { why = 'empty body'; }
                else if (typeof res.body !== 'object') { why = 'body is not a JSON object'; }
                if (why !== null) {
                    violations.push({
                        path: PATHS[p], accept: ACCEPTS[a], body: BODIES[b],
                        status: res.status, why: why,
                        got: String(res.body).substring(0, 120)
                    });
                }
            }
        }
    }
    return { probes: probes, ok: probes - violations.length, violations: violations };
};

run;
