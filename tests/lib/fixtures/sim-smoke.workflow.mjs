export const meta = {
  name: 'sim-smoke',
  description: 'Fixture exercising every simulator seam',
  phases: [],
}
phase('Smoke')
log('smoke')
const r = await agent(args.greeting, { model: 'haiku' })
const doubled = await pipeline([1, 2], async (n) => n * 2)
const broken = await pipeline([1], async () => { throw new Error('boom') })
return { r, doubled, broken }
