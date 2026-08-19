# frozen_string_literal: true

# POST /signup is guarded by a signed "form served at" token (see
# AuthController#signup_gate_passed?). Specs that sign up through the real
# endpoint use this so they look like a person who loaded the form a moment
# ago, not a script posting cold.
module SignupHelpers
  def signup_params(email_address:, password:, issued_at: 30.seconds.ago, **extra)
    { user: { email_address: email_address, password: password },
      signup_token: SignupFormToken.generate(issued_at) }.merge(extra)
  end
end

RSpec.configure do |config|
  config.include SignupHelpers, type: :request
end
