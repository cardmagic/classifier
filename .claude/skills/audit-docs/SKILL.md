---
name: audit-docs
description: Audit README.md and docs/ for accuracy. Runs every documented code example, checks links, anchors, and prose rules, and verifies the CLI examples against the built gem. Use when documentation changes, before a release, or when the user asks to check the docs, verify code samples, or confirm the examples still work.
---

# Audit the documentation

The docs make claims about how this gem behaves. This audit proves each claim or
finds the ones that are false.

A documented example that no longer runs is a bug. Fix the code or fix the docs.
Never weaken an assertion to make a check pass.

## 1. Run the executable examples

`test/docs/documentation_test.rb` holds one assertion per value printed in
README.md and docs/*.md.

```bash
bundle exec ruby -Ilib -Itest test/docs/documentation_test.rb
```

Every failure means the docs and the code disagree. Read the failure, decide
which side is wrong, and correct that side.

## 2. Run the static checks

```bash
ruby .claude/skills/audit-docs/check_docs.rb
```

This covers what a unit test cannot:

- em dashes and en dashes, which this repo's prose rules forbid
- relative markdown links that point at a missing file
- link fragments that point at a missing heading
- documented executables that do not exist

## 3. Run the full suite

```bash
bundle exec rake test
bundle exec rubocop
```

The documentation test is part of `rake test`, so a red suite blocks a release.

## 4. Verify the CLI examples against a real install

The shell examples are not covered by the unit test. Build the gem, install it
into a throwaway `GEM_HOME`, and run the commands as a new user would.

```bash
gem build classifier.gemspec
export GEM_HOME=$(mktemp -d) GEM_PATH=$GEM_HOME PATH=$GEM_HOME/bin:$PATH
gem install classifier-*.gem --no-document
```

Then walk the examples in `docs/cli.md` and `docs/keywords.md` in order, from an
empty directory. Order matters. A reader runs the commands top to bottom, so a
command that needs a model must come after the command that builds one.

Check that:

- the first example a new user meets actually succeeds
- printed output matches what the page shows
- exit codes match the documented table
- an error path prints the documented message

Delete the temporary `GEM_HOME` and the built `.gem` when finished.

## 5. Cross-check new public API

List what the code exposes and confirm the docs cover it:

```bash
grep -rn "^\s*def \(self\.\)\?[a-z_]" lib/classifier/*.rb | grep -v "def _"
```

Anything public and undocumented is a gap. Add it to the right page in `docs/`
and add an assertion to `test/docs/documentation_test.rb`.

## Reporting

Report every finding with the file, the claim, and the observed behavior. Say
plainly which side you changed. If the audit finds nothing, say the docs are
accurate and name what you verified, so the result is checkable.
