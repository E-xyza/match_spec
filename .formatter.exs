# Used by "mix format"
[
  locals_without_parens: [defmatchspec: 2, defmatchspecp: 2],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  exports: [locals_without_parens: [defmatchspec: 2, defmatchspecp: 2]]
]
