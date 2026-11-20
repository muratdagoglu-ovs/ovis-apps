import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { makeServer, validate, pickEstimator, makeLimiter, analyze, MODEL, AnalysisError } from './server.mjs';

const plate = {foods:[{name:'Pilav', grams:150, low:180, high:260, group:'tahil', protein:4, carbs:42, fat:0.4, fiber:0.6, sugar:0.1}]};
const jpeg = Buffer.from([255,216,255,217]);

async function start(estimate) {
  const server = makeServer(estimate, () => true).listen(0,'127.0.0.1');
  await once(server, 'listening');
  return { server, base: 'http://127.0.0.1:' + server.address().port };
}

test('model contract', () => {
  assert.ok(validate(plate));
  assert.ok(validate({foods:[]}));
  assert.equal(validate({foods:[{...plate.foods[0], high:4}]}), false);
  assert.equal(validate({foods:[{...plate.foods[0], grams:0}]}), false);
  assert.equal(validate({foods:[{...plate.foods[0], group:'tatli'}]}), false);
  assert.equal(validate({foods:[{...plate.foods[0], name:' '}]}), false);
  assert.equal(validate({foods:[{...plate.foods[0], protein:-1}]}), false);
  assert.equal(validate({foods:[{...plate.foods[0], sugar:undefined}]}), false);
});

test('photo endpoint and request errors', async t => {
  const { server, base } = await start(async () => plate);
  t.after(() => server.close());
  const url = base + '/plate';
  const send = (type, bytes) => fetch(url,{method:'POST',headers:{'Content-Type':type},body:bytes});
  assert.equal((await send('text/plain','bad')).status,415);
  assert.equal((await send('image/jpeg','bad')).status,400);
  assert.equal((await fetch(base + '/other')).status, 404);
  assert.equal((await send('image/jpeg', Buffer.concat([jpeg, Buffer.alloc(3 * 1024 * 1024 + 1)]))).status, 413);
  const response = await send('image/jpeg', jpeg);
  assert.equal(response.status,200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(),plate);
});

test('upstream failure becomes 502', async t => {
  const { server, base } = await start(async () => { throw Error('down'); });
  t.after(() => server.close());
  const r = await fetch(base + '/plate', {method:'POST', headers:{'Content-Type':'image/jpeg'}, body: jpeg});
  assert.equal(r.status, 502);
});

test('without key: 503 and health reports unconfigured', async t => {
  assert.equal(pickEstimator({}), null);
  assert.equal(pickEstimator({ ANTHROPIC_API_KEY: 'x' }), analyze);
  const off = await start(null);
  t.after(() => off.server.close());
  const r1 = await fetch(off.base + '/plate', {method:'POST', headers:{'Content-Type':'image/jpeg'}, body: jpeg});
  assert.equal(r1.status, 503);
  assert.deepEqual(await (await fetch(off.base + '/health')).json(), { ok: true, mode: 'unconfigured', model: null });
});

function fakeClient(response) {
  const calls = [];
  return { calls, messages: { parse: async params => { calls.push(params); return response; } } };
}

test('analyze sends the photo to Claude Haiku with structured output', async () => {
  const good = plate.foods[0];
  const bad = { ...good, name: 'Bozuk', high: 1 };   // high < low: elenir
  const api = fakeClient({ stop_reason: 'end_turn', parsed_output: { foods: [good, bad] }, usage: { input_tokens: 1, output_tokens: 1 } });
  const result = await analyze(Buffer.from([255, 216, 255, 217]), api);
  assert.deepEqual(result, { foods: [good], mode: 'live' });
  const p = api.calls[0];
  assert.equal(p.model, 'claude-haiku-5-5');
  assert.equal(MODEL, 'claude-haiku-5-5');
  assert.equal(p.output_config.effort, 'low');
  assert.ok(p.output_config.format, 'yapılandırılmış çıktı');
  assert.equal(p.messages[0].content[0].type, 'image');
  assert.equal(p.messages[0].content[0].source.media_type, 'image/jpeg');
  assert.equal(p.messages[0].content[0].source.data, Buffer.from([255, 216, 255, 217]).toString('base64'));
  assert.ok(!('temperature' in p) && !('thinking' in p));
});

test('analyze handles refusal, truncation and empty plates', async () => {
  assert.deepEqual(await analyze(jpeg, fakeClient({ stop_reason: 'refusal', parsed_output: null, usage: {} })), { foods: [], mode: 'live' });
  await assert.rejects(analyze(jpeg, fakeClient({ stop_reason: 'max_tokens', parsed_output: null, usage: {} })), AnalysisError);
  const empty = await analyze(jpeg, fakeClient({ stop_reason: 'end_turn', parsed_output: { foods: [] }, usage: {} }));
  assert.deepEqual(empty, { foods: [], mode: 'live' });
});

// Uygulamanın paketlediği besin ve tarif verisi (iOS/Resources/foods.json)
const db = JSON.parse(readFileSync(new URL('../iOS/Resources/foods.json', import.meta.url)));
const groups = ['sebze', 'protein', 'tahil', 'sos', 'diger'];
const allergens = ['milk', 'egg', 'gluten', 'nuts', 'fish', 'soy'];

test('food database: sources, groups, allergens, macros', () => {
  const sourceIds = new Set(db.sources.map(s => s.id));
  const ids = new Set();
  for (const f of db.foods) {
    assert.ok(!ids.has(f.id), 'tekil kimlik ' + f.id); ids.add(f.id);
    assert.ok(groups.includes(f.group), f.id);
    assert.ok(sourceIds.has(f.source) && f.sourceName, 'kaynak ' + f.id);
    assert.ok(f.allergens.every(a => allergens.includes(a)), f.id);
    const macros = f.protein * 4 + f.carbs * 4 + f.fat * 9;
    assert.ok(Math.abs(macros - f.kcal) <= Math.max(10, f.kcal * 0.15), `${f.id}: ${macros} vs ${f.kcal}`);
  }
  const byId = Object.fromEntries(db.foods.map(f => [f.id, f]));
  assert.deepEqual(byId.yogurt.allergens, ['milk']);
  assert.ok(byId.ekmek.allergens.includes('gluten'));
  for (const r of db.recipes) {
    assert.ok(r.ingredients.every(i => byId[i.food] && i.grams > 0), r.id);
    const kcal = r.ingredients.reduce((s, i) => s + byId[i.food].kcal * i.grams / 100, 0);
    assert.ok(kcal > 100 && kcal < 900, `${r.id}: ${kcal} kcal`);
  }
});

test('every slot and lunch context has milk-free options', () => {
  const byId = Object.fromEntries(db.foods.map(f => [f.id, f]));
  const milkFree = db.recipes.filter(r => r.ingredients.every(i => !byId[i.food].allergens.includes('milk')));
  for (const slot of ['breakfast', 'lunch', 'snack', 'dinner']) assert.ok(milkFree.some(r => r.slots.includes(slot)), slot);
  for (const ctx of ['out', 'home', 'quick']) {
    assert.ok(db.recipes.filter(r => r.slots.includes('lunch') && r.contexts.includes(ctx)).length >= 2, ctx);
  }
});

test('rate limit per client', async t => {
  let clock = 0;
  const allow = makeLimiter(2, () => clock);
  assert.ok(allow('a')); assert.ok(allow('a')); assert.equal(allow('a'), false);
  assert.ok(allow('b'));
  clock = 3600_001;
  assert.ok(allow('a'));
  const limited = makeServer(async () => plate, makeLimiter(1)).listen(0, '127.0.0.1');
  await once(limited, 'listening');
  t.after(() => limited.close());
  const url = 'http://127.0.0.1:' + limited.address().port + '/plate';
  const send = () => fetch(url, {method:'POST', headers:{'Content-Type':'image/jpeg'}, body: jpeg});
  assert.equal((await send()).status, 200);
  assert.equal((await send()).status, 429);
});
