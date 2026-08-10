# frozen_string_literal: true

# N+1 detection.
#
# The gem is dev/test only, so this file must no-op rather than NameError when
# production boots without it.
return unless defined?(Prosopite)

Prosopite.enabled = true
# Two identical query fingerprints from one stack frame is already a pattern.
Prosopite.min_n_queries = 2
Prosopite.backtrace_cleaner = Rails.backtrace_cleaner
# Factory setup legitimately issues repeated inserts; that isn't the app's N+1.
#
# Deliberately NOT allowing spec/support: the block matcher yields from
# spec/support/n_plus_one.rb, so every query it wraps carries that path in its
# stack — allowing it turns the matcher into a no-op that quietly passes.
Prosopite.allow_stack_paths = [ %r{spec/factories}, %r{factory_bot} ]
Prosopite.ignore_queries = [ /schema_migrations/, /ar_internal_metadata/ ]

if Rails.env.development?
  # Warn, never break a page you're trying to look at.
  Prosopite.raise = false
  Prosopite.rails_logger = true
  # Its own file too, so a finding survives the noise of a request log.
  Prosopite.prosopite_logger = true
  Prosopite.ignore_queries += [ /solid_cache_entries/, /solid_queue_/ ]
elsif Rails.env.test?
  # Costs nothing globally: Prosopite is inert unless scan/finish bracket the
  # code, so only a spec that opts in (`:no_n_plus_one`, or the
  # have_n_plus_one_queries matcher) can fail on this.
  Prosopite.raise = true
  Prosopite.rails_logger = false
  # solid_cache is deliberately NOT ignored here. Rails.cache is Postgres in
  # this app, so a cache lookup inside a loop is a real N+1 and should fail.
end
