import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
test('landing background and white cards use requested exact colors', () => {
 const css = readFileSync(new URL('../frontend/app/assets/css/customer.css', import.meta.url), 'utf8')
 assert.match(css, /\.customer-ui \.customer-shell\.customer-landing\s*\{[^}]*background: #F3F4F6;/)
 for (const name of ['customer-welcome', 'customer-tutorial-entry', 'customer-dine-entry']) {
  assert.match(css, new RegExp('\\.' + name + '[^{]*\\{[^}]*background: #FFFFFF;'))
 }
})
