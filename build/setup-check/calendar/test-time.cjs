// Run with DevEco's node.exe. Uses the TypeScript compiler already bundled with the full SDK.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const sdk = process.env.OHOS_BASE_SDK_HOME || path.join(process.env.LOCALAPPDATA, 'OpenHarmony', 'Sdk');
const ts = require(path.join(sdk, '20/ets/build-tools/ets-loader/node_modules/typescript'));
process.env.TZ = 'Europe/Warsaw';

function loadArkTs(file) {
  const source = fs.readFileSync(file, 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const loaded = new Module(file, module);
  loaded._compile(code, file);
  return loaded.exports;
}

const { eventTimestamp, dateText, timeText } = loadArkTs(path.join(__dirname, 'entry/src/main/ets/common/EventTime.ets'));
const { deviceTimeContext } = loadArkTs(path.join(__dirname, '../entry/src/main/ets/agent/DeviceTime.ets'));
const party = new Date(eventTimestamp('2026-10-05', '17:00'));
assert.equal(dateText(party), '2026-10-05');
assert.equal(timeText(party), '17:00');
assert.equal(party.getHours(), 17);
assert.equal(new Date(eventTimestamp('2028-02-29', '07:05')).getDate(), 29);
for (const [day, time] of [
  ['2026-02-29', '17:00'], ['2026-04-31', '17:00'], ['2026-13-01', '17:00'],
  ['2026-10-05', '24:00'], ['2026-10-05', '17:60'], ['2026-10-05', '17'],
  ['2026-3-5', '17:00'], ['2026-03-29', '02:30'] // Warsaw's skipped DST hour.
]) {
  assert.throws(() => eventTimestamp(day, time), `${day} ${time} must be rejected`);
}
assert.match(deviceTimeContext(new Date(2026, 11, 31, 23, 59)), /Tomorrow \(jutro\) is 2027-01-01/);
assert.match(deviceTimeContext(new Date(2028, 1, 28, 7, 5)), /Tomorrow \(jutro\) is 2028-02-29/);
assert.match(deviceTimeContext(new Date(2026, 9, 24, 17)), /Tomorrow \(jutro\) is 2026-10-25/);
console.log('Calendar time checks passed: local 17:00, leap days, invalid dates/times, DST and tomorrow rollover.');
