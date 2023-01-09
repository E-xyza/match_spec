# MatchSpec changelog

## 0.1.0

- initial commit, with support for fun2ms and ms2fun functions

## 0.2.0

- `defmatchspec`, `defmatchspecp`, `fun2msfun`
- major refactor of architecture
- comprehensive error checking

## 0.3.0

- support for `in` guard not at compile time.
- more missed errors: doesn't allow forms that aren't tuples at the head
- more documentation

## 0.3.1

- unified condition and head processing in ms2fun
- fixes issue where string literals are not turned into const expressions
- allows using external variables in ms2fun