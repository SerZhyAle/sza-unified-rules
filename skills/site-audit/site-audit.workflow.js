export const meta = {
  name: 'site-audit',
  description: 'Audit published sites through read-only lenses, verify every HIGH and MED finding, write one report per site and a portfolio summary',
  whenToUse: 'Started by the sza:site-audit skill with the args that tools/site-audit/site-targets.ps1 prints',
  phases: [
    { title: 'Collect', detail: 'robot-check.ps1 and ux-probe.js write the mechanical evidence of each site' },
    { title: 'Lenses', detail: 'one read-only agent per lens per site' },
    { title: 'Verify', detail: 'a skeptic re-measures every HIGH and MED finding and refutes what does not reproduce' },
    { title: 'Report', detail: 'one merged report per site, compared with the previous run or the baseline' },
    { title: 'Portfolio', detail: 'the cross-site summary, when more than one site ran' },
  ],
}

// Every path the agents need arrives in args (site-targets.ps1 prints them); this script reads no file itself.
const A = args || {}
const ROOT = typeof A.pluginRoot === 'string' ? A.pluginRoot.replace(/\\/g, '/').replace(/\/+$/, '') : ''
const TARGETS = Array.isArray(A.targets) ? A.targets.filter(t => t && t.url && t.outDir) : []
if (!ROOT || !TARGETS.length) {
  throw new Error('site-audit: args.pluginRoot and args.targets are required - print them with tools/site-audit/site-targets.ps1 and pass that JSON as args')
}

const AUDIT_LENSES = ['robot', 'ux', 'release-facts', 'structured-data', 'i18n', 'docs']
const MODE = A.mode === 'prepublish' ? 'prepublish' : 'audit'
const PICKED = Array.isArray(A.lenses) ? A.lenses.filter(l => AUDIT_LENSES.includes(l)) : []
const LENSES = MODE === 'prepublish' ? ['prepublish'] : (PICKED.length ? PICKED : AUDIT_LENSES)
const DATE = A.date || 'undated'
const BASELINE = A.baseline || ''
const SEV_RANK = { INFO: 0, LOW: 1, MED: 2, HIGH: 3 }

const ref = name => `${ROOT}/skills/site-audit/references/${name}.md`
const tool = name => `${ROOT}/tools/site-audit/${name}`
const SAFETY = [
  'Read-only: GET and HEAD against the live site only; change no file outside the run folder; never git add, commit, push, tag or deploy.',
  'Never put "report" in the name of a file you write: the harness refuses such files from subagents.',
].join('\n')

const FINDING = {
  type: 'object',
  properties: {
    sev: { type: 'string', enum: ['HIGH', 'MED', 'LOW', 'INFO'] },
    page: { type: 'string', description: 'path relative to the base URL, "site" or "repo"' },
    area: { type: 'string' },
    what: { type: 'string' },
    evidence: { type: 'string', description: 'quoted fragment or measured number, with its source' },
    fix: { type: 'string' },
  },
  required: ['sev', 'page', 'area', 'what', 'evidence', 'fix'],
}
const COLLECTED = {
  type: 'object',
  properties: {
    ok: { type: 'boolean', description: 'true when both tools exited 0' },
    robot: { type: 'string', description: 'absolute path of robot.json, or empty' },
    ux: { type: 'string', description: 'absolute path of ux_probe.json, or empty' },
    shots: { type: 'string', description: 'absolute path of the screenshots folder, or empty' },
    notes: { type: 'string', description: 'exit codes and the last error line of a failed tool, verbatim' },
  },
  required: ['ok', 'robot', 'ux', 'shots', 'notes'],
}
const LENS = {
  type: 'object',
  properties: {
    report: { type: 'string', description: 'absolute path of the lens report written' },
    markdown: { type: 'string', description: 'the lens report text, only when writing its file failed; the main session saves it' },
    findings: { type: 'array', items: FINDING },
    good: { type: 'array', items: { type: 'string' }, description: 'already-good lines, each with evidence' },
    unmeasured: { type: 'array', items: { type: 'string' }, description: 'what could not be measured, and why' },
    verdict: { type: 'string', enum: ['pass', 'blocked', 'unknown'], description: 'prepublish lens only: its verdict line' },
    jobs: {
      type: 'array',
      description: 'UX lens only: the three visitor jobs',
      items: {
        type: 'object',
        properties: { job: { type: 'string' }, cost: { type: 'string' }, stall: { type: 'string' } },
        required: ['job', 'cost', 'stall'],
      },
    },
  },
  required: ['report', 'findings', 'good', 'unmeasured'],
}
const VERDICTS = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          index: { type: 'integer' },
          verdict: { type: 'string', enum: ['confirmed', 'refuted', 'unverifiable'] },
          evidence: { type: 'string', description: 'what was re-measured, and the result' },
          sev: { type: 'string', enum: ['HIGH', 'MED', 'LOW', 'INFO'], description: 'only to lower the severity, with the reason in evidence' },
        },
        required: ['index', 'verdict', 'evidence'],
      },
    },
  },
  required: ['verdicts'],
}
const SITE = {
  type: 'object',
  properties: {
    key: { type: 'string' },
    url: { type: 'string' },
    report: { type: 'string', description: 'absolute path where report.md belongs' },
    markdown: { type: 'string', description: 'the complete report.md text; the main session saves it' },
    counts: {
      type: 'object',
      properties: { HIGH: { type: 'integer' }, MED: { type: 'integer' }, LOW: { type: 'integer' }, INFO: { type: 'integer' } },
      required: ['HIGH', 'MED', 'LOW', 'INFO'],
    },
    top: { type: 'array', items: { type: 'string' }, description: 'up to 5 most severe finding lines' },
    fixed: { type: 'array', items: { type: 'string' } },
    open: { type: 'array', items: { type: 'string' } },
    fresh: { type: 'array', items: { type: 'string' }, description: 'findings new since the earlier run' },
    refuted: { type: 'integer' },
  },
  required: ['key', 'url', 'report', 'markdown', 'counts', 'top', 'fixed', 'open', 'fresh', 'refuted'],
}
const PORTFOLIO = {
  type: 'object',
  properties: {
    report: { type: 'string', description: 'absolute path where portfolio.md belongs' },
    markdown: { type: 'string', description: 'the complete portfolio.md text; the main session saves it' },
    baselineRows: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          row: { type: 'string', description: 'the baseline row number or id' },
          status: { type: 'string', enum: ['fixed', 'open', 'partial', 'not-remeasured', 'obsolete'] },
          evidence: { type: 'string' },
        },
        required: ['row', 'status', 'evidence'],
      },
    },
    crossCutting: { type: 'array', items: { type: 'string' } },
  },
  required: ['report', 'markdown', 'baselineRows', 'crossCutting'],
}

const NO_EVIDENCE = { ok: false, robot: '', ux: '', shots: '', notes: 'the collect stage returned nothing - measure live' }

function describe(t) {
  return [
    `Base URL: ${t.url}`,
    `Repository: ${t.repo || 'none on this machine - audit the live site only, and say so in the report'}`,
    `Served root in the repository: ${t.siteRoot || 'n/a'}`,
    `Pages the stamp declares (relative to the served root): ${(t.pages || []).join(', ') || 'none declared'}`,
    `Site kind: ${t.kind || 'unknown'}`,
    `Run folder (git-ignored, verified): ${t.outDir}`,
    `Previous run folder: ${t.prevDir || 'none'}`,
    `Earlier run to compare with (conventions section 7): ${t.prevFile || 'none - every finding is New'}`,
    `Portfolio baseline file: ${BASELINE || 'none'} (only its rows for this host)`,
  ].join('\n')
}

function collect(t) {
  const pages = (t.pages || []).length ? ` -Pages "${t.pages.join(',')}"` : ''
  return agent([
    'You collect the mechanical evidence for one site of a site audit: run two tools, report what they wrote, and interpret nothing.',
    SAFETY,
    describe(t),
    '',
    `1. pwsh -NoProfile -File "${tool('robot-check.ps1')}" -Url "${t.url}"${pages} -Out "${t.outDir}/robot.json"`,
    `2. Read the "url" of every entry in "pages" of ${t.outDir}/robot.json, home first.`,
    `3. node "${tool('ux-probe.js')}" --out "${t.outDir}" <those urls, space-separated>`,
    'A tool that exits non-zero does not stop the run: quote its exit code and last error line in notes and go on with the other.',
  ].join('\n'), { label: `collect:${t.key}`, phase: 'Collect', schema: COLLECTED, effort: 'low' })
}

function lens(t, name, ev) {
  return agent([
    `You are the "${name}" lens of a site audit.`,
    SAFETY,
    'Read these two files first and follow them exactly:',
    `  1. ${ref('conventions')} - evidence, the finding line, severity, canon precedence, the lens report shape`,
    `  2. ${ref(name)} - your lens`,
    '',
    describe(t),
    `Collected evidence: robot ${ev.robot || 'missing'}; ux ${ev.ux || 'missing'}; screenshots ${ev.shots || 'missing'}`,
    ev.ok ? '' : `Collection notes: ${ev.notes}`,
    '',
    `Write your lens report to ${t.outDir}/${name}.md, then return the structured result; if that write is refused, return the report text in markdown instead.`,
  ].filter(Boolean).join('\n'), { label: `${name}:${t.key}`, phase: 'Lenses', schema: LENS })
    .then(r => r && { ...r, lens: name })
}

function verify(t, results) {
  const found = results.filter(Boolean).flatMap(r => (r.findings || []).map(f => ({ ...f, lens: r.lens })))
    .map((f, index) => ({ ...f, index }))
  const check = found.filter(f => f.sev === 'HIGH' || f.sev === 'MED')
  if (!check.length) return Promise.resolve({ results, found, verdicts: [] })
  return agent([
    `You are the skeptic of a site audit of ${t.url}. Try to REFUTE each finding below with a fresh measurement: curl the live URL (GET or HEAD), read the repository file, or open the screenshot.`,
    SAFETY,
    describe(t),
    '',
    'A finding stands only when its evidence reproduces now. "refuted" when it does not, with what you saw instead; "unverifiable" when it cannot be measured from here, with the reason. You may lower a severity, never raise one, and say why in the evidence.',
    'A transient defect (rate limit, timeout) is confirmed only with a count from your own attempts.',
    '',
    ...check.map(f => `#${f.index} [${f.sev}][${f.page}][${f.area}] ${f.what} - ${f.evidence} - ${f.fix}`),
    '',
    `Write ${t.outDir}/verify.md with one line per finding ("#<index> <verdict> - <evidence>"), then return the verdicts.`,
  ].join('\n'), { label: `verify:${t.key}`, phase: 'Verify', schema: VERDICTS })
    .then(v => ({ results, found, verdicts: (v && v.verdicts) || [] }))
}

function report(t, v) {
  const byIndex = new Map(v.verdicts.map(x => [x.index, x]))
  const lines = v.found.map(f => {
    const vd = byIndex.get(f.index)
    const sev = vd && vd.sev && SEV_RANK[vd.sev] < SEV_RANK[f.sev] ? vd.sev : f.sev
    const mark = vd ? vd.verdict : (SEV_RANK[f.sev] >= 2 ? 'not verified - the skeptic returned nothing for it' : 'not checked')
    return `{${f.lens}} [${sev}][${f.page}][${f.area}] ${f.what} - ${f.evidence} - ${f.fix} => ${mark}${vd && vd.evidence ? ` (${vd.evidence})` : ''}`
  })
  const ran = v.results.filter(Boolean)
  const good = ran.flatMap(r => (r.good || []).map(g => `{${r.lens}} ${g}`))
  const unmeasured = ran.flatMap(r => (r.unmeasured || []).map(u => `{${r.lens}} ${u}`))
  const jobs = ran.flatMap(r => (r.jobs || []).map(j => `${j.job} | ${j.cost} | ${j.stall}`))
  const missing = LENSES.filter(l => !ran.some(r => r.lens === l))
  return agent([
    `Merge the lens results of the site audit of ${t.url} into one site report.`,
    SAFETY,
    `Read ${ref('conventions')} first: sections 7 (Changed since) and 9 (The site report) are your output contract.`,
    describe(t),
    `Lens reports: ${ran.filter(r => r.report).map(r => r.report).join(', ') || 'none'}; verdicts: ${t.outDir}/verify.md`,
    ran.some(r => !r.report) ? `Lenses with no report file (their findings below are all there is): ${ran.filter(r => !r.report).map(r => r.lens).join(', ')}` : '',
    missing.length ? `Lenses that returned nothing (name them in the header): ${missing.join(', ')}` : '',
    '',
    'Findings with their verdicts ("refuted" ones go to "Refuted on verification", never to Findings):',
    ...lines,
    '',
    'Already good:', ...good, '',
    'Not measured:', ...unmeasured, '',
    jobs.length ? ['Three jobs (job | cost | stall):', ...jobs].join('\n') : 'Three jobs: the UX lens returned none.',
    '',
    `Do not write report.md - the harness refuses report files from subagents. Return its complete text in markdown, with report "${t.outDir}/report.md"; the main session saves it there. Key "${t.key}", url "${t.url}". The counts are of the merged, surviving findings.`,
  ].filter(Boolean).join('\n'), { label: `report:${t.key}`, phase: 'Report', schema: SITE })
    .then(s => s && { ...s, saves: ran.filter(r => r.markdown).map(r => ({ path: `${t.outDir}/${r.lens}.md`, markdown: r.markdown })) })
}

// What the portfolio agent gets of each site: the report is not on disk until the main session saves it.
function digest(s) {
  const fresh = s.fresh || []
  const c = s.counts || {}
  return [
    `## ${s.key} - ${s.url} (report.md saved later at ${s.report})`,
    `Counts: HIGH ${c.HIGH}, MED ${c.MED}, LOW ${c.LOW}, INFO ${c.INFO}; refuted on verification ${s.refuted}`,
    'Most severe:', ...(s.top || []),
    'Fixed since the earlier run:', ...((s.fixed || []).length ? s.fixed : ['none']),
    'Still open:', ...((s.open || []).length ? s.open : ['none']),
    `New (${fresh.length}):`, ...fresh.slice(0, 40),
    fresh.length > 40 ? `.. ${fresh.length - 40} more, in the site's lens reports` : '',
  ].filter(Boolean).join('\n')
}

if (MODE === 'prepublish') {
  const gates = await pipeline(TARGETS, t => lens(t, 'prepublish', { ...NO_EVIDENCE, ok: true, notes: '' }))
  return {
    mode: MODE,
    date: DATE,
    sites: TARGETS.map((t, i) => {
      const g = gates[i]
      return {
        key: t.key,
        url: t.url,
        report: g ? g.report : '',
        verdict: (g && g.verdict) || 'unknown',
        blockers: g ? g.findings.filter(f => f.sev === 'HIGH').length : null,
        saves: g && g.markdown ? [{ path: `${t.outDir}/prepublish.md`, markdown: g.markdown }] : [],
      }
    }),
  }
}

const sites = await pipeline(
  TARGETS,
  t => collect(t),
  (ev, t) => parallel(LENSES.map(name => () => lens(t, name, ev || NO_EVIDENCE))),
  (results, t) => verify(t, results || []),
  (v, t) => report(t, v),
)

const done = sites.filter(Boolean)
TARGETS.forEach((t, i) => { if (!sites[i]) log(`no report for ${t.key} (${t.url}): a stage failed or was skipped`) })
log(`${done.length} of ${TARGETS.length} site reports returned`)

let portfolio = null
if (TARGETS.length > 1 && done.length) {
  phase('Portfolio')
  const out = A.portfolioOut || `${TARGETS[0].outDir}/portfolio.md`
  portfolio = await agent([
    'Write the portfolio summary of a site audit that covered several sites.',
    SAFETY,
    `Read ${ref('conventions')} first. The site reports are not on disk yet - the main session saves them after this stage - so each site's digest is below; its lens reports and verify.md are in its run folder for detail.`,
    `Baseline findings file: ${BASELINE || 'none'}`,
    TARGETS.length > done.length ? `Sites with no report this run: ${TARGETS.filter((t, i) => !sites[i]).map(t => t.url).join(', ')}` : '',
    '',
    ...done.map(digest),
    '',
    `Do not write portfolio.md - the harness refuses report files from subagents. Return its complete text in markdown, with report "${out}"; it holds:`,
    '1. One row per site: url | HIGH | MED | LOW | the most severe finding | fixed since the earlier run.',
    '2. Cross-cutting patterns: one defect seen on two or more sites, named once with every site it hits and the single shared fix.',
    '3. When a baseline exists: every baseline row with its status now (fixed, open, partial, not-remeasured, obsolete) and the evidence from this run.',
    '4. The order of work: cheap cross-cutting fixes first, then per-site work, then content.',
    '5. Owner decisions the reports raised, as plain questions.',
    'Then return the summary.',
  ].filter(Boolean).join('\n'), { label: 'portfolio', phase: 'Portfolio', schema: PORTFOLIO })
}

log(`save the reports: pwsh -NoProfile -File "${tool('save-reports.ps1')}" -Output <the output file the completion notice names>`)
return { mode: MODE, date: DATE, lenses: LENSES, sites: done, missing: TARGETS.filter((t, i) => !sites[i]).map(t => t.key), portfolio }
