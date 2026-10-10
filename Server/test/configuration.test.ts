import assert from 'node:assert/strict';
import test from 'node:test';
import { developmentBuildsAllowed } from '../src/configuration.js';

test('development builds are denied by default and require an exact opt-in', () => {
  assert.equal(developmentBuildsAllowed(undefined), false);
  assert.equal(developmentBuildsAllowed('false'), false);
  assert.equal(developmentBuildsAllowed('true'), true);
});

test('ambiguous deployment values fail closed without echoing their contents', () => {
  for (const value of ['', 'TRUE', 'False', '1', '0', 'yes', ' true', 'true ', 'unexpected-sensitive-value']) {
    assert.throws(() => developmentBuildsAllowed(value), {
      message: 'invalid_configuration:APPLE_ALLOW_DEVELOPMENT_BUILDS',
    });
  }
});
