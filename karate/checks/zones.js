// The wall-clock <-> instant arithmetic the schedule's zones imply, in ONE place: the deck
// driver needs it to place an existing meeting on the UTC line, and the mock needs it to
// decide whether two bookings share an instant. Neither may hold a second copy.
//
//   var Z = File.call('/checks/zones.js', {});   -> {offsetMins, utcMs, wireTime, wallAdd, wallMins}
//
// The copy lives in mock/handlers.js and this reads it back. That is the wrong way round on
// the face of it, and it is forced: Twin.mutate evaluates the handler file with only `Rule`
// bound, so the mock cannot pull anything in and this side has to do the pulling.

File.call('/mock/handlers.js').zones;
