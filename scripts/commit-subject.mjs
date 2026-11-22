// Checks a commit subject: `type(scope): subject`, 72 characters at most (conventional commits; English is left to
// review).
// Used by .githooks/commit-msg on each commit, and by .github/workflows/pr-title.yml on the PR title, which GitHub
// takes as the squash commit's subject. Git's own merge and revert subjects pass.
const subject = (process.argv[2] || '').split('\n')[0];
const TYPES = 'feat|fix|chore|docs|refactor|test|perf|build|ci|style|revert';
const ok = new RegExp(`^(${TYPES})(\\([\\w-]+\\))?!?: \\S`).test(subject) || /^(Merge|Revert) /.test(subject);
const errors = [
  ...(ok ? [] : [`« type(scope): sujet » attendu, type parmi ${TYPES.replaceAll('|', ', ')}`]),
  ...(subject.length > 72 ? [`${subject.length} caractères, 72 au plus : une seule idée par sujet`] : []),
];
if (errors.length) {
  console.error(`✗ sujet de commit refusé : ${subject}\n  ${errors.join('\n  ')}`);
  process.exit(1);
}
