// quick-meetings — the meeting-creation oracle (QM-001..004).
// Declared tables first: the zone transitions and the duration bounds are data, not code.
const lookup = {
    // the schedule declares no maximum length - a meeting need only end after it starts
    duration: { minMins: 1 },                                                   // QM-004
    // A local time inside [gapFrom, gapTo) on gapDate is not a real instant; one inside
    // [ambFrom, ambTo) on ambDate happens twice and resolves to the earlier offset (QM-003).
    zones: {
        'UTC': { stdOffset: 0, gapDate: null, ambDate: null },
        'Europe/Amsterdam': {
            stdOffset: 60, dstOffset: 120,
            gapDate: '2026-03-29', gapFrom: 120, gapTo: 180,
            ambDate: '2026-10-25', ambFrom: 120, ambTo: 180
        }
    },
    // Allen's thirteen. The schedule is CLOSED-interval: two meetings that merely touch
    // share an instant and conflict, so only strict disjointness is compatible (QM-002/2).
    compatible: ['before', 'after']
};

function minutesOfDay(hhmm) {
    const parts = hhmm.split(':');
    return Number(parts[0]) * 60 + Number(parts[1]);
}

// Allen's thirteen relations of the proposed interval to the existing one, each its own arm
// so every cell of the two-interval space is a branch the analysis can reach and grade.
function relationOf(calc, ps, pe, es, ee) {
    calc.label('Disjoint before');
    if (pe < es) { return 'before'; }
    calc.label('Touches at the existing start');
    if (pe === es) { return 'meets'; }
    calc.label('Disjoint after');
    if (ps > ee) { return 'after'; }
    calc.label('Touches at the existing end');
    if (ps === ee) { return 'metBy'; }
    calc.label('Starts before the existing meeting');
    if (ps < es) {
        calc.label('Ends inside the existing meeting');
        if (pe < ee) { return 'overlaps'; }
        calc.label('Ends with the existing meeting');
        if (pe === ee) { return 'finishedBy'; }
        return 'contains';
    }
    calc.label('Starts with the existing meeting');
    if (ps === es) {
        calc.label('Ends before the existing meeting');
        if (pe < ee) { return 'starts'; }
        calc.label('Ends with the existing meeting, having started with it');
        if (pe === ee) { return 'equals'; }
        return 'startedBy';
    }
    calc.label('Ends before the existing meeting, having started after it');
    if (pe < ee) { return 'during'; }
    calc.label('Ends with the existing meeting, having started after it');
    if (pe === ee) { return 'finishes'; }
    return 'overlappedBy';
}

const execute = function (calc) {
    const input = calc.input;
    const zone = lookup.zones[input.zone];
    const startOfDay = minutesOfDay(input.time);

    let decision = null;
    let reason = null;
    let relation = null;

    calc.log('# The proposed meeting');
    calc.log(input.zone + ' ' + input.date + ' ' + input.time + ' for ' + input.durationMins + ' minutes');

    calc.label('Ends after it starts');
    if (input.durationMins < lookup.duration.minMins) {
        calc.req('QM-004/1');
        calc.log('refused: duration ' + input.durationMins + ' - a meeting must end after it starts');
        decision = 'refused';
        reason = 'invalid_duration';
    }

    let inGap = false;
    let ambiguous = false;
    if (decision === null) {
        calc.log('# Local time resolution');
        calc.label('Nonexistent local start');
        if (input.date === zone.gapDate && startOfDay >= zone.gapFrom && startOfDay < zone.gapTo) {
            inGap = true;
            calc.req('QM-003/1');
            calc.log('refused: ' + input.time + ' does not exist on ' + input.date + ' in ' + input.zone + ' (clocks jump forward)');
            decision = 'refused';
            reason = 'nonexistent_local_time';
        } else {
            calc.label('Ambiguous local start');
            if (input.date === zone.ambDate && startOfDay >= zone.ambFrom && startOfDay < zone.ambTo) {
                ambiguous = true;
                calc.req('QM-003/2');
                calc.log(input.time + ' happens twice on ' + input.date + ' in ' + input.zone + ' - resolved to the earlier offset');
            }
        }
    }

    if (decision === null) {
        calc.log('# Interval algebra against the confirmed schedule');
        calc.label('An existing confirmed meeting');
        if (!input.hasExisting || input.existingDurationMins === 0) {
            calc.req('QM-001/2');
            calc.log('no confirmed meeting to conflict with');
            relation = 'free';
            decision = 'created';
        } else {
            const ps = 0;
            const pe = input.durationMins;
            const es = input.relStartMins;
            const ee = input.relStartMins + input.existingDurationMins;
            calc.log('proposed [' + ps + ', ' + pe + '] against existing [' + es + ', ' + ee + '] (minutes from the proposed start)');
            relation = relationOf(calc, ps, pe, es, ee);
            calc.log('interval relation: ' + relation);
            calc.label('Conflict decision');
            if (lookup.compatible.indexOf(relation) < 0) {
                calc.req('QM-001/1');
                calc.req('QM-002/1');
                calc.log('refused: ' + relation + ' shares at least an instant with the existing meeting');
                decision = 'refused';
                reason = 'conflict';
            } else {
                calc.req('QM-002/2');
                calc.log('created: ' + relation + ' shares no instant with the existing meeting');
                decision = 'created';
            }
        }
    }

    calc.outcome(decision);

    calc.sometimes('the proposed meeting strictly contains an existing one', relation === 'contains', { req: 'QM-002/1' });
    calc.sometimes('an existing meeting strictly contains the proposed one', relation === 'during', { req: 'QM-002/1' });
    calc.sometimes('the two meetings are the same interval', relation === 'equals', { req: 'QM-002/1' });
    calc.sometimes('the two meetings only touch', relation === 'meets' || relation === 'metBy', { req: 'QM-002/1' });
    calc.sometimes('a nonexistent local start is refused', inGap, { req: 'QM-003/1' });
    calc.sometimes('an ambiguous local start is scheduled', ambiguous, { req: 'QM-003/2' });

    calc.log('# Guarantees');
    calc.always('a refusal always names its reason', decision !== 'refused' || reason !== null, { req: 'QM-001/1' });
    calc.always('a created meeting names no reason', decision !== 'created' || reason === null, { req: 'QM-001/2' });
    calc.always('containment is always a conflict',
        (relation !== 'contains' && relation !== 'during') || decision === 'refused', { req: 'QM-002/1' });
    calc.always('a meeting that shares no instant is never refused for conflict',
        lookup.compatible.indexOf(relation) < 0 || reason !== 'conflict', { req: 'QM-002/2' });

    calc.output = {
        decision: decision,
        reason: reason,
        relation: relation
    };
};
