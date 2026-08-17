## Summary

<!-- What does this change do, in one or two sentences? -->

## Motivation

<!-- Why is this change needed? Link the issue it closes, e.g. "Closes #123". -->

## Changes

<!-- The notable changes, one per line. -->

-

## How to verify

<!-- Commands you ran, and anything a reviewer should run or look at. -->

```console
$ bundle exec rspec
$ bundle exec rubocop
```

## Compatibility

- [ ] Public API is unchanged, or the change is described above and reflected in the README
- [ ] Works across the supported Ruby and Rails versions declared in `recorder.gemspec`
- [ ] Generated migrations and generator output still run on a fresh application (if touched)

## Checklist

- [ ] Specs cover the new behaviour, and the suite passes locally
- [ ] RuboCop passes
- [ ] README and other docs are updated where the behaviour changed
- [ ] `Recorder::VERSION` is left alone — releases are cut separately
