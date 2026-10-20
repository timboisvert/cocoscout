# frozen_string_literal: true

# expect { ... }.to change(A, :count).and(not_change(B, :count))
RSpec::Matchers.define_negated_matcher :not_change, :change
